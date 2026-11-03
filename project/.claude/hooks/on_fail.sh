#!/bin/bash
export HARNESS_HOOK_LIB="$(dirname "$(realpath "${BASH_SOURCE[0]}")")/lib"
# on_fail Hook 핸들러
# 이슈 실패 시 재시도 또는 에스컬레이션 처리

REGISTRY=".claude/issue-db/registry.json"
ISSUE_ID="$1"
ERROR_MSG="$2"

echo "[Hook:on_fail] 이슈 실패: $ISSUE_ID"

python3 - "$REGISTRY" "$ISSUE_ID" "$ERROR_MSG" << 'EOF'
import sys as _sysargv
# 인자는 argv로 받는다 (heredoc 보간 = RCE 경로. 2026-07-15 감사)
_REGISTRY, _ISSUE_ID, _ERROR_MSG = (_sysargv.argv[1:4] + ['']*3)[:3]

import json, datetime, sys
import os as _atomic_os, sys as _atomic_sys
for _atomic_lib in (_atomic_os.environ.get("HARNESS_HOOK_LIB", ""),
                    _atomic_os.path.join(_atomic_os.environ.get("HOME", ""), ".claude/harness-core/hooks/lib"),
                    _atomic_os.path.realpath(".claude/hooks/lib")):
    if _atomic_os.path.isdir(_atomic_lib) and _atomic_lib not in _atomic_sys.path:
        _atomic_sys.path.insert(0, _atomic_lib)
from registry_lock import atomic_write_json
from issue_id import next_id as _alloc_id

try:
    with open(_REGISTRY, 'r') as f:
        registry = json.load(f)
except:
    print("registry.json 읽기 실패")
    sys.exit(1)

issue_id = _ISSUE_ID

for issue in registry['issues']:
    if issue['id'] == issue_id:
        issue['retry_count'] = issue.get('retry_count', 0) + 1
        registry['stats']['failed'] += 1

        if issue['retry_count'] < 3:
            # 재시도
            issue['status'] = 'READY'
            print(f"[재시도] {issue_id} → {issue['retry_count']}회차")
        else:
            # 에스컬레이션
            issue['status'] = 'ESCALATED'
            next_id = _alloc_id(registry)  # 카드 수+1 은 기존 번호와 겹칠 수 있다
            escalation = {
                'id': next_id,
                'title': f"[에스컬레이션] {issue['title']} 반복 실패",
                'type': 'SYSTEMIC_ISSUE',
                'status': 'READY',
                'priority': 'P0',
                'assign_to': 'meta-agent',
                'depth': issue.get('depth', 0) + 1,
                'retry_count': 0,
                'parent_id': issue_id,
                'depends_on': [],
                'created_at': datetime.datetime.now().isoformat(),
                'payload': {'original_issue': issue_id, 'error': _ERROR_MSG},
                'result': None,
                'spawn_rules': []
            }
            registry['issues'].append(escalation)
            registry['stats']['total_issues'] += 1
            print(f"[에스컬레이션] {next_id} 생성 → meta-agent")

        # Hook 이력 기록
        registry['hooks']['on_fail'].append({
            'issue_id': issue_id,
            'retry_count': issue['retry_count'],
            'timestamp': datetime.datetime.now().isoformat()
        })
        break

atomic_write_json(_REGISTRY, registry)

print(f"[on_fail] 처리 완료")
EOF

# 재시도/에스컬레이션 이슈 생성 후 자동 디스패치
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "[on_fail] → dispatch-ready 실행"
bash "$SCRIPT_DIR/dispatch-ready.sh" "$REGISTRY"
