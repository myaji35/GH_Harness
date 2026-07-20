#!/bin/bash
# on-agent-complete.sh — 에이전트 완료 시 자동 파이프라인 연결
# Stop hook에서 호출됨: 에이전트가 멈출 때마다 실행
#
# 흐름:
#   에이전트 작업 완료 → on_complete.sh (파생 이슈 생성)
#                     → dispatch-ready.sh (다음 이슈 자동 감지/스폰 지시)

# 심볼릭 링크 설치(프로젝트 .claude/hooks/ → harness-core/hooks/) 대응
_src="${BASH_SOURCE[0]}"
while [ -L "$_src" ]; do
  _dir="$(cd -P "$(dirname "$_src")" && pwd)"
  _src="$(readlink "$_src")"
  [[ "$_src" != /* ]] && _src="$_dir/$_src"
done
SCRIPT_DIR="$(cd -P "$(dirname "$_src")" && pwd)"
REGISTRY=".claude/issue-db/registry.json"

# stdin의 Stop hook 입력 JSON을 먼저 읽는다(아래 stop_hook_active 판정에 필요).
HOOK_INPUT="$(cat 2>/dev/null || true)"

# ── 무한 루프 차단 (공식 규약) ──
# Stop hook이 exit 2를 반환하면 "멈추지 말고 대화를 계속하라"는 뜻이다.
# 그런데 이 hook은 READY 이슈가 있으면 무조건 exit 2를 낸다. READY는 디스패치
# 지시만으로는 사라지지 않으므로 조건이 영원히 참 → 매 턴 재개 요구가 반복된다.
# 공식 문서: "stop_hook_active is true when Claude Code is already continuing as a
# result of a stop hook. Check this value ... to avoid blocking on a condition that
# will never resolve."  ← 이 체크가 하네스 전체에 0건이었다(2026-07-20 실측).
#
# 증상: claude -p(비대화 단발)에서 이 루프에 갇혀 "Execution error"로 죽는다.
#       저니2~5가 전부 두뇌 스폰에 의존하므로 저니 검증 체계 전체가 마비됐다.
# 처방: 이미 stop-hook으로 재개된 턴이면 블로킹하지 않고 통과(exit 0)한다.
#       디스패치 안내는 그 턴에 이미 전달됐다.
if printf '%s' "$HOOK_INPUT" | python3 -c "
import sys, json
try:
    sys.exit(0 if json.load(sys.stdin).get('stop_hook_active') else 1)
except Exception:
    sys.exit(1)
" 2>/dev/null; then
  exit 0
fi

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
