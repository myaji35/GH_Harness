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

# graphify 그래프 증분 갱신 신호 (게이트는 autobuild.sh 내부, 미설치 시 즉시 skip)
bash .claude/hooks/graphify-autobuild.sh change "$CHANGED_FILE" >/dev/null 2>&1 || true

python3 - "$REGISTRY" "$CHANGED_FILE" << 'PYEOF'
import sys as _sysargv
# 인자는 argv로 받는다 (heredoc 보간 = RCE 경로. 2026-07-15 감사)
_REGISTRY, _CHANGED_FILE = (_sysargv.argv[1:3] + ['']*2)[:2]

import json, datetime, sys

try:
    with open(_REGISTRY, 'r') as f:
        registry = json.load(f)
except Exception:
    sys.exit(0)

changed_file = _CHANGED_FILE

# 현재 IN_PROGRESS 이슈에 변경 파일 기록
for issue in registry.get('issues', []):
    if issue.get('status') == 'IN_PROGRESS':
        if 'files_changed' not in issue.get('payload', {}):
            issue.setdefault('payload', {})['files_changed'] = []
        if changed_file != 'unknown' and changed_file not in issue['payload']['files_changed']:
            issue['payload']['files_changed'].append(changed_file)
        break

with open(_REGISTRY, 'w') as f:
    json.dump(registry, f, indent=2, ensure_ascii=False)
PYEOF
