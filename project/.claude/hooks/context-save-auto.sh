#!/bin/bash
# context-save-auto.sh — 세션 종료·압축 직전 작업 상태를 자동 보존한다.
# 근거: 세션 경계에서 진행 이슈와 Git 작업 맥락이 유실되는 사고의 재발을 방지한다.
# 동작: 프로젝트별 마크다운 스냅샷을 조용히 저장하고 최신 20개만 유지한다.
set +e

_src="${BASH_SOURCE[0]}"
while [ -L "$_src" ]; do
  _dir="$(cd -P "$(dirname "$_src")" 2>/dev/null && pwd)"
  _src="$(readlink "$_src" 2>/dev/null)"
  [[ "$_src" != /* ]] && _src="$_dir/$_src"
done
SCRIPT_DIR="$(cd -P "$(dirname "$_src")" 2>/dev/null && pwd)" || exit 0

INPUT="$(cat 2>/dev/null)"
TRIGGER="$(printf '%s' "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('hook_event_name','') or 'auto')" 2>/dev/null)"
[ -n "$TRIGGER" ] || TRIGGER="auto"
SAFE_TRIGGER="$(printf '%s' "$TRIGGER" | tr -cd 'A-Za-z0-9_-')"
[ -n "$SAFE_TRIGGER" ] || SAFE_TRIGGER="auto"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -n "$PROJECT_ROOT" ] || PROJECT_ROOT="$PWD"
SNAP_DIR="$PROJECT_ROOT/.claude/context-snapshots"
mkdir -p "$SNAP_DIR" 2>/dev/null || exit 0
STAMP="$(TZ=Asia/Seoul date +%Y-%m-%d-%H%M%S 2>/dev/null)" || exit 0
AT="$(TZ=Asia/Seoul date '+%Y-%m-%d %H:%M:%S KST' 2>/dev/null)"
SNAPSHOT="$SNAP_DIR/$STAMP-$SAFE_TRIGGER.md"
BRANCH="$(git -C "$PROJECT_ROOT" branch --show-current 2>/dev/null)"
[ -n "$BRANCH" ] || BRANCH="(없음)"
REGISTRY="$PROJECT_ROOT/.claude/issue-db/registry.json"

{
  echo "# 작업 컨텍스트 스냅샷"
  echo
  echo "- 저장 시각: $AT"
  echo "- 트리거: $TRIGGER"
  echo "- 프로젝트 경로: $PROJECT_ROOT"
  echo "- git 브랜치: $BRANCH"
  if [ -f "$REGISTRY" ]; then
    issues="$(python3 - "$REGISTRY" <<'PY' 2>/dev/null
import sys,json
d=json.load(open(sys.argv[1]))
for x in d.get('issues',[]):
    if x.get('status') in ('IN_PROGRESS','AWAITING_USER'):
        print(f"- {x.get('id','')} | {x.get('type','')} | {x.get('priority','')} | {x.get('title','')}")
PY
)"
    echo
    echo "## 진행 중 이슈"
    [ -n "$issues" ] && printf '%s\n' "$issues" || echo "(없음)"
  fi
  echo
  echo "## 미커밋 변경"
  echo '```text'
  git -C "$PROJECT_ROOT" status --short 2>/dev/null | head -40
  echo '```'
  echo
  echo "## 최근 커밋"
  echo '```text'
  git -C "$PROJECT_ROOT" log --oneline -10 2>/dev/null
  echo '```'
  echo
  echo "## 최근 변경 파일"
  echo '```text'
  git -C "$PROJECT_ROOT" diff --stat HEAD 2>/dev/null | head -30
  echo '```'
} > "$SNAPSHOT" 2>/dev/null || exit 0

find "$SNAP_DIR" -maxdepth 1 -type f -name '*.md' -print0 2>/dev/null \
  | xargs -0 ls -1t 2>/dev/null \
  | tail -n +21 \
  | while IFS= read -r old; do [ -n "$old" ] && rm -f -- "$old" 2>/dev/null; done
exit 0
