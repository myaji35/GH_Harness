#!/bin/bash
# on-agent-complete.sh — 에이전트 완료 시 자동 파이프라인 연결
# Stop hook에서 호출됨: 에이전트가 멈출 때마다 실행
#
# 흐름:
#   에이전트 작업 완료 → on_complete.sh (파생 이슈 생성)
#                     → dispatch-ready.sh (다음 이슈 자동 감지/스폰 지시)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY=".claude/issue-db/registry.json"

if [ ! -f "$REGISTRY" ]; then
  exit 0
fi

# 1. IN_PROGRESS 이슈 감지 + 좌초(stall) 판정
#
# [2026-07-15] on_fail 배선 문제 해결:
#   on_fail.sh는 (이슈ID, 에러메시지)를 인자로 받으므로 Stop hook에 직접 걸 수 없다
#   (Stop hook은 어떤 이슈가 왜 실패했는지 모른다). 그래서 4개월간 어디에도 연결되지
#   않았고 retry_count>0 이슈가 0건이었다 — 재시도가 한 번도 작동한 적이 없다.
#
#   해결: 여기서 좌초를 감지해 on_fail.sh를 호출한다.
#   에이전트가 Stop 했는데 이슈가 아직 IN_PROGRESS면 = 완료 보고 없이 죽은 것.
#   STALL_MIN(기본 30분) 이상 IN_PROGRESS면 좌초로 판정한다.
#   (짧게 잡으면 정상 장기작업을 죽인다 — background 작업은 60초+가 정상)
STALL_MIN="${HARNESS_STALL_MIN:-30}"

STALLED=$(python3 - "$REGISTRY" "$STALL_MIN" << 'PYEOF'
import json, sys, datetime
reg_path, stall_min = sys.argv[1], int(sys.argv[2])
try:
    registry = json.load(open(reg_path, encoding='utf-8'))
except Exception:
    sys.exit(0)

now = datetime.datetime.now()
stalled = []
for iss in registry.get("issues", []):
    if iss.get("status") != "IN_PROGRESS":
        continue
    print(f"IN_PROGRESS: {iss['id']} ({iss.get('type')}) → {iss.get('assign_to')}", file=sys.stderr)
    ts = iss.get("started_at") or iss.get("updated_at") or iss.get("created_at")
    if not ts:
        continue
    try:
        started = datetime.datetime.fromisoformat(str(ts).replace("Z", ""))
    except Exception:
        continue
    if (now - started).total_seconds() > stall_min * 60:
        stalled.append(iss["id"])

# 좌초 이슈 ID만 stdout으로 (호출부가 읽어서 on_fail 실행)
for i in stalled:
    print(i)
PYEOF
)

# 좌초 이슈에 on_fail 실행 → retry_count 증가 → READY 복귀 또는 에스컬레이션
for iss_id in $STALLED; do
  [ -n "$iss_id" ] || continue
  echo "⏱️  [Stall] $iss_id 가 ${STALL_MIN}분 이상 IN_PROGRESS — 좌초 판정, on_fail 실행"
  bash "$SCRIPT_DIR/on_fail.sh" "$iss_id" "agent stopped without completion (stall > ${STALL_MIN}min)"
done

# 2. READY 이슈 디스패치 확인
bash "$SCRIPT_DIR/dispatch-ready.sh" "$REGISTRY"
