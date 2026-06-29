#!/bin/bash
# fleet-scan.sh — v5.3 / 전 프로젝트(fleet) 방치 이슈 크로스 스캐너
# 근본문제: 각 프로젝트가 격리돼, 한 프로젝트 세션에서 다른 프로젝트의 방치
#   READY/IN_PROGRESS 이슈를 알 수 없음 → "지시받은 적 없다는 듯 딴말" 발생.
# 해결: SessionStart 시 fleet 전체 방치 현황을 1회 요약 출력(컨텍스트 주입).
#   자기 프로젝트는 session-resume이 처리. 타 프로젝트는 "있다 + 처리법" 안내만(오버 방지).
#
# 발동: SessionStart hook에서 session-resume 다음에 호출.
# 안전: 읽기 전용. 어떤 registry도 수정하지 않는다.
set -uo pipefail

# fleet 루트 추정: 현재 프로젝트의 부모 디렉터리
CUR="$(pwd)"
FLEET_ROOT="$(dirname "$CUR")"
CUR_NAME="$(basename "$CUR")"

# 부모에 registry 보유 프로젝트가 2개 미만이면 fleet 아님 → skip
count=$(find "$FLEET_ROOT" -maxdepth 4 -name registry.json -path '*/issue-db/*' 2>/dev/null | head -3 | wc -l | tr -d ' ')
[ "$count" -lt 2 ] && exit 0

python3 - "$FLEET_ROOT" "$CUR_NAME" <<'PY'
import json, glob, os, sys
root, cur = sys.argv[1], sys.argv[2]
rows = []
for reg in glob.glob(os.path.join(root, '*/.claude/issue-db/registry.json')):
    proj = reg.split('/')[-4]
    if proj == cur:        # 자기 프로젝트는 session-resume이 처리 → 제외
        continue
    try:
        d = json.load(open(reg))
    except Exception:
        continue
    active = [i for i in d.get('issues', []) if i.get('status') in ('READY', 'IN_PROGRESS')]
    if not active:
        continue
    # 우선순위 P0/P1만 추려서 노이즈 억제
    urgent = [i for i in active if i.get('priority') in ('P0', 'P1')]
    rows.append((proj, len(active), len(urgent)))

if not rows:
    sys.exit(0)

rows.sort(key=lambda x: -x[2])  # 긴급 많은 순
total = sum(r[1] for r in rows)
print("\n🛰️  [Fleet 스캔] 다른 프로젝트에 방치된 작업이 있습니다 (자기 프로젝트 제외):")
for proj, a, u in rows[:8]:
    tag = f" — P0/P1 {u}개" if u else ""
    print(f"   • {proj}: 방치 {a}개{tag}")
if len(rows) > 8:
    print(f"   • ... 외 {len(rows)-8}개 프로젝트")
print(f"   합계: {total}개 방치 / {len(rows)}개 프로젝트")
print("   → 처리하려면 해당 프로젝트 디렉터리에서 새 세션을 열면 session-resume이 자동 착수한다.")
print("   → 또는 대표님이 특정 프로젝트를 지시하면 그쪽으로 전환해 처리한다. (지금 자동 처리 금지 — 컨텍스트 격리)")
PY
exit 0
