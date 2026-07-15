#!/bin/bash
# freeze-guard.sh — PreToolUse hook
# Edit/Write 도구 호출 시 FREEZE_DIR 외 경로 차단
#
# 활성화 조건: /tmp/harness-freeze.env 파일 존재
# 차단 시: exit 2 (PreToolUse가 도구 실행을 중단함)

FREEZE_FILE="/tmp/harness-freeze.env"

# freeze 미설정이면 통과
[ ! -f "$FREEZE_FILE" ] && exit 0

source "$FREEZE_FILE"
[ -z "$FREEZE_DIR" ] && exit 0

# stdin으로 들어온 도구 입력에서 file_path 추출
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    # tool_input.file_path 추출
    fp = data.get('tool_input', {}).get('file_path', '')
    print(fp)
except Exception:
    print('')
" 2>/dev/null)

# file_path 없으면 통과
[ -z "$FILE_PATH" ] && exit 0

# FREEZE_DIR 절대 경로화
FREEZE_DIR_ABS="$(cd "$FREEZE_DIR" 2>/dev/null && pwd || echo "$FREEZE_DIR")"

# file_path가 FREEZE_DIR 하위면 통과
case "$FILE_PATH" in
  "$FREEZE_DIR_ABS"/*|"$FREEZE_DIR"/*)
    exit 0
    ;;
  *)
    echo "🔒 [Harness Freeze] 편집 차단: $FILE_PATH" >&2
    echo "    허용 디렉터리: $FREEZE_DIR_ABS" >&2
    echo "    해제: rm $FREEZE_FILE" >&2
    exit 2
    ;;
esac
