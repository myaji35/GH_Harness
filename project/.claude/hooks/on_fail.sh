#!/bin/bash
# on_fail Hook 핸들러
# 이슈 실패 시 재시도 또는 에스컬레이션 처리

REGISTRY=".claude/issue-db/registry.json"
ISSUE_ID="$1"
ERROR_MSG="$2"

echo "[Hook:on_fail] 이슈 실패: $ISSUE_ID"

python3 << EOF
import json, datetime, sys

try:
    with open('$REGISTRY', 'r') as f:
        registry = json.load(f)
except:
    print("registry.json 읽기 실패")
    sys.exit(1)

issue_id = '$ISSUE_ID'

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
            next_id = f"ISS-{registry['stats']['total_issues'] + 1:03d}"
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
                'payload': {'original_issue': issue_id, 'error': '$ERROR_MSG'},
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

with open('$REGISTRY', 'w') as f:
    json.dump(registry, f, indent=2, ensure_ascii=False)

print(f"[on_fail] 처리 완료")
EOF
