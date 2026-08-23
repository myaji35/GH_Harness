#!/bin/bash
# health-gate.sh — git commit 직전 프로젝트 건강 점수를 계산하는 비차단 게이트.
# 근거: 검증 품질의 직전 대비 회귀를 커밋 전에 알리되, 오탐으로 파이프라인을 막지 않는다.
# 동작: 사용 가능한 검사만 전체 45초·각 20초 이내로 실행하고 이력을 남긴 뒤 5점 이상 하락할 때만 경고한다.
set +e

# 심볼릭 링크 설치 경로를 끝까지 해제해 실제 스크립트 디렉터리를 구한다.
_src="${BASH_SOURCE[0]}"
while [ -L "$_src" ]; do
  _dir="$(cd -P "$(dirname "$_src")" 2>/dev/null && pwd)"
  _src="$(readlink "$_src" 2>/dev/null)"
  [[ "$_src" != /* ]] && _src="$_dir/$_src"
done
SCRIPT_DIR="$(cd -P "$(dirname "$_src")" 2>/dev/null && pwd)" || exit 0

REGISTRY=".claude/issue-db/registry.json"
[ -f "$REGISTRY" ] || exit 0

# 전체 실행도 제한한다. timeout 재호출 실패를 포함해 모든 경로는 통과한다.
if [ "${HEALTH_GATE_WORKER:-}" != "1" ]; then
  INPUT="$(cat 2>/dev/null)"
  COMMAND="$(printf '%s' "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null)"
  [ -n "$COMMAND" ] || exit 0
  case "$COMMAND" in *"git commit"*) ;; *) exit 0 ;; esac
  command -v timeout >/dev/null 2>&1 || exit 0
  printf '%s' "$INPUT" | HEALTH_GATE_WORKER=1 timeout 45 bash "$SCRIPT_DIR/health-gate.sh" >/tmp/health-gate-output.$$ 2>/dev/null
  cat /tmp/health-gate-output.$$ 2>/dev/null
  rm -f /tmp/health-gate-output.$$ 2>/dev/null
  exit 0
fi

INPUT="$(cat 2>/dev/null)"
COMMAND="$(printf '%s' "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null)"
[ -n "$COMMAND" ] || exit 0
case "$COMMAND" in *"git commit"*) ;; *) exit 0 ;; esac

score=100
ran=0
started_at="$(date +%s)"
truncated=false
checks_file="$(mktemp 2>/dev/null)" || exit 0
skipped_file="$(mktemp 2>/dev/null)" || { rm -f "$checks_file"; exit 0; }
trap 'rm -f "$checks_file" "$skipped_file" /tmp/health-gate-check.$$ 2>/dev/null' EXIT

record_check() { printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$checks_file" 2>/dev/null; }
skip_check() { printf '%s\n' "$1" >> "$skipped_file" 2>/dev/null; }
prepare_check() {
  elapsed=$(( $(date +%s) - started_at ))
  remaining=$((45 - elapsed))
  if [ "$remaining" -lt 3 ]; then
    skip_check "$1 (시간 예산 초과)"
    truncated=true
    return 1
  fi
  check_timeout=$remaining
  [ "$check_timeout" -gt 20 ] && check_timeout=20
  return 0
}

type_script=""
if [ -f package.json ]; then
  type_script="$(python3 -c "import json; d=json.load(open('package.json')); s=d.get('scripts',{}); print('typecheck' if 'typecheck' in s else ('type-check' if 'type-check' in s else ''))" 2>/dev/null)"
fi
if [ -n "$type_script" ] && command -v npm >/dev/null 2>&1; then
  if prepare_check "typecheck"; then
  ran=$((ran + 1)); timeout "$check_timeout" npm run "$type_script" >/tmp/health-gate-check.$$ 2>&1; rc=$?
  penalty=0; [ "$rc" -eq 0 ] || penalty=30; score=$((score - penalty))
  record_check "typecheck" "$penalty" "exit=$rc"
  fi
else skip_check "typecheck"; fi

if [ -f tsconfig.json ] && command -v npx >/dev/null 2>&1; then
  if prepare_check "tsc"; then
    if timeout "$check_timeout" npx --no-install tsc --version >/dev/null 2>&1; then
      if prepare_check "tsc"; then
        ran=$((ran + 1)); timeout "$check_timeout" npx --no-install tsc --noEmit >/tmp/health-gate-check.$$ 2>&1; rc=$?
        errors="$(grep -Eic 'error TS[0-9]+:' /tmp/health-gate-check.$$ 2>/dev/null)"; errors=${errors:-0}
        penalty=$errors; [ "$penalty" -gt 30 ] && penalty=30; score=$((score - penalty))
        record_check "tsc" "$penalty" "errors=$errors,exit=$rc"
      fi
    else
      skip_check "tsc"
    fi
  fi
else skip_check "tsc"; fi

if command -v ruff >/dev/null 2>&1; then
  if prepare_check "ruff"; then
  ran=$((ran + 1)); timeout "$check_timeout" ruff check . --output-format concise >/tmp/health-gate-check.$$ 2>&1; rc=$?
  warnings="$(grep -Ec ':[0-9]+:[0-9]+:' /tmp/health-gate-check.$$ 2>/dev/null)"; warnings=${warnings:-0}
  penalty=$(((warnings / 5) * 2)); [ "$penalty" -gt 20 ] && penalty=20; score=$((score - penalty))
  record_check "ruff" "$penalty" "warnings=$warnings,exit=$rc"
  fi
elif command -v eslint >/dev/null 2>&1 || [ -x node_modules/.bin/eslint ]; then
  eslint_cmd="eslint"; [ -x node_modules/.bin/eslint ] && eslint_cmd="node_modules/.bin/eslint"
  if prepare_check "eslint"; then
  ran=$((ran + 1)); timeout "$check_timeout" "$eslint_cmd" . >/tmp/health-gate-check.$$ 2>&1; rc=$?
  warnings="$(grep -Eic 'warning|problems? \(' /tmp/health-gate-check.$$ 2>/dev/null)"; warnings=${warnings:-0}
  penalty=$(((warnings / 5) * 2)); [ "$penalty" -gt 20 ] && penalty=20; score=$((score - penalty))
  record_check "eslint" "$penalty" "warnings=$warnings,exit=$rc"
  fi
else skip_check "ruff/eslint"; fi

if [ -f Gemfile ] && command -v bundle >/dev/null 2>&1; then
  if prepare_check "rubocop"; then
  ran=$((ran + 1)); timeout "$check_timeout" bundle exec rubocop --format simple >/tmp/health-gate-check.$$ 2>&1; rc=$?
  offenses="$(sed -nE 's/.*([0-9]+) offenses? detected.*/\1/p' /tmp/health-gate-check.$$ 2>/dev/null | tail -1)"; offenses=${offenses:-0}
  penalty=$(((offenses / 5) * 2)); [ "$penalty" -gt 20 ] && penalty=20; score=$((score - penalty))
  record_check "rubocop" "$penalty" "offenses=$offenses,exit=$rc"
  fi
else skip_check "rubocop"; fi

if command -v rg >/dev/null 2>&1; then
  if prepare_check "todo_markers"; then
  ran=$((ran + 1)); timeout "$check_timeout" rg -n --hidden --glob '!.git/**' --glob '!node_modules/**' --glob '!.venv/**' --glob '!venv/**' --glob '!vendor/**' --glob '!dist/**' --glob '!build/**' --glob '!.next/**' --glob '!target/**' --glob '!__pycache__/**' --glob '!*.min.js' --glob '!*.lock' 'TODO|FIXME|HACK' . >/tmp/health-gate-check.$$ 2>/dev/null
  todos="$(wc -l < /tmp/health-gate-check.$$ 2>/dev/null | tr -d ' ')"; todos=${todos:-0}
  penalty=$((todos / 10)); [ "$penalty" -gt 10 ] && penalty=10; score=$((score - penalty))
  record_check "todo_markers" "$penalty" "count=$todos"
  fi
else skip_check "todo_markers"; fi

[ "$ran" -gt 0 ] || exit 0
[ "$score" -lt 0 ] && score=0
history=".claude/knowledge-db/health-history.jsonl"
mkdir -p "$(dirname "$history")" 2>/dev/null || exit 0
previous="$(python3 -c "import sys,json
previous=''
for line in sys.stdin:
    try: record=json.loads(line)
    except (ValueError, TypeError): continue
    if not record.get('truncated', False): previous=record.get('score','')
print(previous)" < "$history" 2>/dev/null)"
line="$(python3 - "$score" "$checks_file" "$skipped_file" "$truncated" <<'PY'
import sys,json,datetime
score=int(sys.argv[1]); checks={}
for line in open(sys.argv[2], errors='replace'):
    name, penalty, detail=line.rstrip('\n').split('\t',2)
    checks[name]={'penalty':int(penalty),'detail':detail}
skipped=[x.rstrip('\n') for x in open(sys.argv[3], errors='replace') if x.rstrip('\n')]
print(json.dumps({'at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'score':score,'checks':checks,'skipped':skipped,'truncated':sys.argv[4]=='true'},ensure_ascii=False))
PY
)" || exit 0
[ -n "$line" ] || exit 0
printf '%s\n' "$line" >> "$history" 2>/dev/null || exit 0

case "$previous" in ''|*[!0-9]*) exit 0 ;; esac
drop=$((previous - score)); [ "$drop" -ge 5 ] || exit 0
items="$(awk -F '\t' '$2 > 0 {printf "%s%s(-%s)", sep, $1, $2; sep=", "}' "$checks_file" 2>/dev/null)"
[ -n "$items" ] || items="상세 검사 결과"
echo "⚠️ [health-gate] 점수 하락: 이전 $previous → 현재 $score (-$drop). 감점 항목: $items / 회귀 가능성을 확인하고 커밋하라."
exit 0
