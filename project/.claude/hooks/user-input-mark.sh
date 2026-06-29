#!/bin/bash
# user-input-mark.sh — v5/A2
# UserPromptSubmit 시점에 호출. .user-input-pending 파일 생성 → dispatch-ready가 큐 보류.
# Claude가 응답하는 동안만 유효. on-agent-complete.sh 끝에서 자동 제거.

MARK_FILE=".claude/.user-input-pending"
mkdir -p "$(dirname "$MARK_FILE")"
date -u +%Y-%m-%dT%H:%M:%SZ > "$MARK_FILE"
exit 0
