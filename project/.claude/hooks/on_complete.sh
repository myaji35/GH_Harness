#!/bin/bash
# on_complete Hook 핸들러
# 이슈 완료 시 자동으로 파생 이슈 생성 및 다음 하네스 알림

REGISTRY=".claude/issue-db/registry.json"
ISSUE_ID="$1"
ISSUE_TYPE="$2"
RESULT="$3"

echo "[Hook:on_complete] 이슈 완료: $ISSUE_ID ($ISSUE_TYPE)"

# Python으로 registry 업데이트 및 파생 이슈 생성
python3 << EOF
import json, datetime, sys

try:
    with open('$REGISTRY', 'r') as f:
        registry = json.load(f)
except:
    print("registry.json 읽기 실패")
    sys.exit(1)

issue_id = '$ISSUE_ID'
issue_type = '$ISSUE_TYPE'

# 이슈 상태 업데이트
for issue in registry['issues']:
    if issue['id'] == issue_id:
        issue['status'] = 'DONE'
        issue['completed_at'] = datetime.datetime.now().isoformat()
        registry['stats']['completed'] += 1

        # spawn_rules 평가 (단순화된 버전)
        spawn_rules = issue.get('spawn_rules', [])
        next_id = f"ISS-{registry['stats']['total_issues'] + 1:03d}"

        # 타입별 기본 파생 이슈
        spawn_map = {
            'GENERATE_CODE': {'type': 'RUN_TESTS', 'assign_to': 'test-harness'},
            'FIX_BUG':       {'type': 'RUN_TESTS', 'assign_to': 'test-harness'},
            'RUN_TESTS':     {'type': 'SCORE',     'assign_to': 'eval-harness'},
            'SCORE':         {'type': 'DEPLOY_READY', 'assign_to': 'cicd-harness'},
        }

        if issue_type in spawn_map:
            spawn = spawn_map[issue_type]
            new_issue = {
                'id': next_id,
                'title': f"[파생] {spawn['type']} from {issue_id}",
                'type': spawn['type'],
                'status': 'READY',
                'priority': 'P1',
                'assign_to': spawn['assign_to'],
                'depth': issue.get('depth', 0) + 1,
                'retry_count': 0,
                'parent_id': issue_id,
                'depends_on': [],
                'created_at': datetime.datetime.now().isoformat(),
                'payload': {},
                'result': None,
                'spawn_rules': []
            }

            # 깊이 제한 체크
            if new_issue['depth'] <= 3:
                registry['issues'].append(new_issue)
                registry['stats']['total_issues'] += 1
                print(f"[파생 이슈 생성] {next_id}: {spawn['type']} → {spawn['assign_to']}")
            else:
                print(f"[깊이 제한] 파생 이슈 생성 안 함 (depth={new_issue['depth']})")

        # Hook 이력 기록
        registry['hooks']['on_complete'].append({
            'issue_id': issue_id,
            'timestamp': datetime.datetime.now().isoformat()
        })

        break

with open('$REGISTRY', 'w') as f:
    json.dump(registry, f, indent=2, ensure_ascii=False)

print(f"[on_complete] 처리 완료")
EOF
