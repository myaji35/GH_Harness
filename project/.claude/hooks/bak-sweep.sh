#!/bin/bash
# bak-sweep.sh — 프로젝트에 누적된 오래된 백업 파일을 세션 시작 시 정리한다.
# 근거: 하네스 규칙4가 생성하는 .bak-* 파일에 삭제 규약이 없어 무한 누적되는 문제를 방지한다.
# 동작: KST 기준 하루 1회, 7일이 지난 백업을 최대 20개까지 삭제하고 내역을 기록한다.
set +e

_src="${BASH_SOURCE[0]}"
while [ -L "$_src" ]; do
  _dir="$(cd -P "$(dirname "$_src")" 2>/dev/null && pwd)"
  _src="$(readlink "$_src" 2>/dev/null)"
  [[ "$_src" != /* ]] && _src="$_dir/$_src"
done
SCRIPT_DIR="$(cd -P "$(dirname "$_src")" 2>/dev/null && pwd)" || exit 0

DRY_RUN=0
CORE_MODE=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --core) CORE_MODE=1 ;;
    --help|-h)
      printf '사용법: %s [--dry-run] [--core]\n' "$(basename "$0")"
      printf '  --dry-run  삭제하지 않고 대상만 출력\n'
      printf '  --core     harness-core/hooks의 7일 경과 백업 파일도 삭제 대상에 포함\n'
      exit 0
      ;;
  esac
done

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -n "$PROJECT_ROOT" ] || PROJECT_ROOT="$PWD"
KNOWLEDGE_DIR="$PROJECT_ROOT/.claude/knowledge-db"
STAMP_FILE="$KNOWLEDGE_DIR/.bak-sweep.last_run"
LOG_FILE="$KNOWLEDGE_DIR/bak-sweep.log"

if [ "$DRY_RUN" -eq 0 ]; then
  TODAY_KST="$(TZ=Asia/Seoul date +%Y-%m-%d 2>/dev/null)" || exit 0
fi
if [ "$DRY_RUN" -eq 0 ] && [ "$CORE_MODE" -eq 0 ]; then
  LAST_RUN=""
  [ -f "$STAMP_FILE" ] && LAST_RUN="$(cat "$STAMP_FILE" 2>/dev/null)"
  [ "$LAST_RUN" = "$TODAY_KST" ] && exit 0
fi

TARGETS="$(mktemp "${TMPDIR:-/tmp}/bak-sweep.XXXXXX" 2>/dev/null)" || exit 0
trap 'rm -f -- "$TARGETS" 2>/dev/null' EXIT

BACKUP_DIRS=()
while IFS= read -r -d '' backup_dir; do
  BACKUP_DIRS[${#BACKUP_DIRS[@]}]="$backup_dir"
done < <(find "$PROJECT_ROOT" -maxdepth 4 -type d \
  \( -name '*.bak' -o -name '*.bak-*' -o -name '*.bak.*' -o -name '*.bak.[0-9]*' -o -name '*.backup' \) \
  -print0 -prune 2>/dev/null)

print_backup_dirs() {
  local count="${#BACKUP_DIRS[@]}" listed remaining paths="" i
  [ "$count" -gt 0 ] || return
  listed="$count"
  [ "$listed" -gt 5 ] && listed=5
  for ((i = 0; i < listed; i++)); do
    [ -n "$paths" ] && paths="$paths, "
    paths="$paths${BACKUP_DIRS[$i]}"
  done
  remaining=$((count - listed))
  [ "$remaining" -gt 0 ] && paths="$paths 외 ${remaining}개"
  printf 'ℹ️ [bak-sweep] 디렉터리 백업 %s개는 자동 삭제 대상이 아니다: %s\n' "$count" "$paths"
}

find "$PROJECT_ROOT" -maxdepth 4 \
  \( -type d \( -name '*.bak' -o -name '*.bak-*' -o -name '*.bak.*' -o -name '*.bak.[0-9]*' -o -name '*.backup' \) -prune \) \
  -o \( -type f -not -name '._*' \
    \( -name '*.bak' -o -name '*.bak-*' -o -name '*.bak.[0-9]*' \
       -o -name '*.backup' -o -name '*.orig' -o -name '*~' \) \
    -mtime +7 \
    ! -path "$PROJECT_ROOT/.git/*" \
    ! -path '*/node_modules/*' \
    ! -path '*/.venv/*' \
    ! -path '*/venv/*' \
    ! -path '*/vendor/*' \
    ! -path '*/dist/*' \
    ! -path '*/build/*' \
    ! -path '*/__pycache__/*' \
    -print0 \) > "$TARGETS" 2>/dev/null || exit 0

find "$PROJECT_ROOT" -maxdepth 4 \
  \( -type d \( -name '*.bak' -o -name '*.bak-*' -o -name '*.bak.*' -o -name '*.bak.[0-9]*' -o -name '*.backup' \) -prune \) \
  -o \( -type l -not -name '._*' \
    \( -name '*.bak' -o -name '*.bak-*' -o -name '*.bak.[0-9]*' \
       -o -name '*.backup' -o -name '*.orig' -o -name '*~' \) \
    ! -path "$PROJECT_ROOT/.git/*" \
    ! -path '*/node_modules/*' \
    ! -path '*/.venv/*' \
    ! -path '*/venv/*' \
    ! -path '*/vendor/*' \
    ! -path '*/dist/*' \
    ! -path '*/build/*' \
    ! -path '*/__pycache__/*' \
    -print0 \) 2>/dev/null | while IFS= read -r -d '' link; do
      [ ! -e "$link" ] && printf '%s\0' "$link"
    done >> "$TARGETS"

CORE_COUNT="$(find "$SCRIPT_DIR" -maxdepth 1 -type f -not -name '._*' \
  \( -name '*.bak' -o -name '*.bak-*' -o -name '*.bak.[0-9]*' \
     -o -name '*.backup' -o -name '*.orig' -o -name '*~' \) \
  -mtime +7 -print 2>/dev/null | wc -l | tr -d ' ')"

if [ "$CORE_MODE" -eq 1 ]; then
  find "$SCRIPT_DIR" -maxdepth 1 -type f -not -name '._*' \
    \( -name '*.bak' -o -name '*.bak-*' -o -name '*.bak.[0-9]*' \
       -o -name '*.backup' -o -name '*.orig' -o -name '*~' \) \
    -mtime +7 -print0 >> "$TARGETS" 2>/dev/null
fi

print_core_notice() {
  if [ "$CORE_MODE" -eq 0 ] && [ "${CORE_COUNT:-0}" -gt 0 ]; then
    printf 'ℹ️ [bak-sweep] harness-core 에 7일 경과 백업 %s개 — 전 프로젝트에 링크로 퍼진다. 정리하려면: bash ~/.claude/harness-core/hooks/bak-sweep.sh --core\n' "$CORE_COUNT"
  fi
}

if [ "$DRY_RUN" -eq 1 ]; then
  while IFS= read -r -d '' target; do
    printf '%s\n' "$target"
  done < "$TARGETS"
  print_backup_dirs
  print_core_notice
  exit 0
fi

COUNT="$(python3 - "$TARGETS" <<'PY' 2>/dev/null
import sys

with open(sys.argv[1], "rb") as f:
    print(sum(1 for path in f.read().split(b"\0") if path))
PY
)"
case "$COUNT" in
  ''|*[!0-9]*) exit 0 ;;
esac

mkdir -p "$KNOWLEDGE_DIR" 2>/dev/null || exit 0
printf '%s\n' "$TODAY_KST" > "$STAMP_FILE" 2>/dev/null || exit 0

if [ "$COUNT" -gt 20 ]; then
  printf '⚠️ [bak-sweep] 정리 대상 %s개 발견 — 20개 초과로 자동 삭제 보류. 확인 후 수동 정리하라.\n' "$COUNT"
  print_backup_dirs
  print_core_notice
  exit 0
fi

DELETED=0
while IFS= read -r -d '' target; do
  broken_link=0
  [ -L "$target" ] && [ ! -e "$target" ] && broken_link=1
  rm -f -- "$target" 2>/dev/null
  if [ ! -e "$target" ] && [ ! -L "$target" ]; then
    apple_double="$(dirname "$target")/._$(basename "$target")"
    rm -f -- "$apple_double" 2>/dev/null
    AT="$(TZ=Asia/Seoul date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)"
    if [ "$broken_link" -eq 1 ]; then
      printf '%s %s (깨진 링크)\n' "$AT" "$target" >> "$LOG_FILE" 2>/dev/null
    else
      printf '%s %s\n' "$AT" "$target" >> "$LOG_FILE" 2>/dev/null
    fi
    DELETED=$((DELETED + 1))
  fi
done < "$TARGETS"

if [ "$DELETED" -gt 0 ]; then
  printf '🧹 [bak-sweep] 백업/깨진 링크 %s개 정리 (로그: .claude/knowledge-db/bak-sweep.log)\n' "$DELETED"
fi
print_backup_dirs
print_core_notice
exit 0
