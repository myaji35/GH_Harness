#!/bin/bash
# freeze-guard.sh — PreToolUse hook
# Edit/Write 도구 호출 시 FREEZE_DIR 외 경로 차단
#
# 활성화 조건: /tmp/harness-freeze-${KEY}.env 파일 존재 (KEY: 프로젝트 루트 sha256 앞 12자)
# 차단 시: exit 2 (PreToolUse가 도구 실행을 중단함)

PROJECT_ROOT="$(pwd)"
KEY="$(printf %s "$PROJECT_ROOT" | shasum -a 256 | awk '{print substr($1,1,12)}')"
FREEZE_FILE="/tmp/harness-freeze-${KEY}.env"

# freeze 미설정이면 통과
[ ! -f "$FREEZE_FILE" ] && exit 0

source "$FREEZE_FILE"
[ -z "$FREEZE_DIR" ] && exit 0

# ⚠️ v2 (2026-07-20): 잔류 freeze 무효화 — 실제 착수된 이슈만 잠근다.
#    dispatch-ready.sh는 이슈를 "추천"하는 시점에 freeze를 쓴다(READY 상태에서).
#    그 이슈가 실제로 착수되지 않으면 잠금만 남아 *무관한 작업*을 차단한다.
#    실제 사고: ISS-160·161·162·164가 전부 READY(미착수)인 채 rails-api/app/views
#    (나중엔 rails-api 전체)를 잠갔고, 해제해도 다음 디스패치가 다음 이슈 명의로
#    재생성 → 전역 hook 작성·secret-guard 수정이 연달아 막혔다.
#    "진행 중 작업 보호"가 목적인데 진행되지 않는 작업이 진행 중 작업을 막는 역전.
#    프로젝트별 잠금이므로 현재 프로젝트 registry에서 IN_PROGRESS만 인정한다.
if [ -n "$FREEZE_ISSUE" ] && [ -f ".claude/issue-db/registry.json" ]; then
  _st=$(python3 -c "
import json,sys
try:
    d=json.load(open('.claude/issue-db/registry.json'))
    for i in d.get('issues',[]):
        if i.get('id')=='$FREEZE_ISSUE':
            print(i.get('status','')); break
except Exception: pass
" 2>/dev/null)
  # 착수 상태가 아니면 잔류 잠금으로 보고 통과 (BACKGROUND_RUNNING도 실행 중으로 인정)
  case "$_st" in
    IN_PROGRESS|BACKGROUND_RUNNING) ;;
    *) exit 0 ;;
  esac
fi

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
