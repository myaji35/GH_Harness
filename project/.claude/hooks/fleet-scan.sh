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
shopt -s nullglob
registries=("$FLEET_ROOT"/*/.claude/issue-db/registry.json)
count=${#registries[@]}
[ "$count" -lt 2 ] && exit 0

python3 - "$FLEET_ROOT" "$CUR_NAME" <<'PY'
import json, glob, os, sys, tempfile
root, cur = sys.argv[1], sys.argv[2]
rows = []
cache_path = os.path.join(os.environ.get('XDG_CACHE_HOME', os.path.expanduser('~/.cache')), 'claude-fleet-scan.json')
try:
    with open(cache_path) as f:
        cache = json.load(f)
    if not isinstance(cache, dict):
        cache = {}
except Exception:
    cache = {}
for reg in glob.glob(os.path.join(root, '*/.claude/issue-db/registry.json')):
    proj = reg.split('/')[-4]
    if proj == cur:        # 자기 프로젝트는 session-resume이 처리 → 제외
        continue
    try:
        mtime = os.path.getmtime(reg)
        cached = cache.get(reg)
        if (isinstance(cached, dict) and cached.get('mtime') == mtime
                and isinstance(cached.get('active'), int) and isinstance(cached.get('urgent'), int)):
            active_count = cached['active']
            urgent_count = cached['urgent']
        else:
            with open(reg) as f:
                d = json.load(f)
            active = [i for i in d.get('issues', []) if i.get('status') in ('READY', 'IN_PROGRESS')]
            # 우선순위 P0/P1만 추려서 노이즈 억제
            urgent = [i for i in active if i.get('priority') in ('P0', 'P1')]
            active_count = len(active)
            urgent_count = len(urgent)
            cache[reg] = {'mtime': mtime, 'active': active_count, 'urgent': urgent_count}
    except Exception:
        continue
    if not active_count:
        continue
    rows.append((proj, active_count, urgent_count))

try:
    cache_dir = os.path.dirname(cache_path)
    os.makedirs(cache_dir, exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(dir=cache_dir)
    try:
        with os.fdopen(fd, 'w') as f:
            json.dump(cache, f)
        os.replace(tmp_path, cache_path)
    except Exception:
        try:
            os.unlink(tmp_path)
        except Exception:
            pass
except Exception:
    pass

if not rows:
    sys.exit(0)

rows.sort(key=lambda x: -x[2])  # 긴급 많은 순
total = sum(r[1] for r in rows)
print(f"⚠️ 타 프로젝트 방치 이슈 {total}건 / {len(rows)}개 — 정리하려면 해당 프로젝트에서 새 세션")
PY
exit 0
