#!/bin/bash
# post-code-change.sh — 코드 변경(Write|Edit) 감지 후 처리
# PostToolUse hook에서 Write|Edit 매처로 호출됨
#
# 역할:
#   1. 현재 IN_PROGRESS 이슈의 payload.files에 변경 파일 기록
#   2. 변경 사항 추적 (Meta Agent 분석 데이터)

REGISTRY=".claude/issue-db/registry.json"

if [ ! -f "$REGISTRY" ]; then
  exit 0
fi

# Hook 입력에서 파일 경로 추출 (TOOL_INPUT 환경변수 또는 stdin)
CHANGED_FILE="${TOOL_INPUT_FILE_PATH:-unknown}"

python3 << PYEOF
import json, datetime, sys

try:
    with open('$REGISTRY', 'r') as f:
        registry = json.load(f)
except Exception:
    sys.exit(0)

changed_file = '$CHANGED_FILE'

# 현재 IN_PROGRESS 이슈에 변경 파일 기록
for issue in registry.get('issues', []):
    if issue.get('status') == 'IN_PROGRESS':
        if 'files_changed' not in issue.get('payload', {}):
            issue.setdefault('payload', {})['files_changed'] = []
        if changed_file != 'unknown' and changed_file not in issue['payload']['files_changed']:
            issue['payload']['files_changed'].append(changed_file)
        break

with open('$REGISTRY', 'w') as f:
    json.dump(registry, f, indent=2, ensure_ascii=False)
PYEOF
