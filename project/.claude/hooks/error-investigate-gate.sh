#!/bin/bash
# error-investigate-gate.sh — 오류 입력에 근본원인 조사 절차를 주입하는 게이트.
# 근거: 증상 위주의 성급한 수정과 반복 실패를 막고 재현·조사·가설을 먼저 강제한다.
# 동작: 시스템 알림은 제외하고 독립적인 오류 신호가 둘 이상일 때만 안내문을 출력한다.
set +e

_src="${BASH_SOURCE[0]}"
while [ -L "$_src" ]; do
  _dir="$(cd -P "$(dirname "$_src")" 2>/dev/null && pwd)"
  _src="$(readlink "$_src" 2>/dev/null)"
  [[ "$_src" != /* ]] && _src="$_dir/$_src"
done
SCRIPT_DIR="$(cd -P "$(dirname "$_src")" 2>/dev/null && pwd)" || exit 0
REGISTRY=".claude/issue-db/registry.json"
[ -f "$REGISTRY" ] || exit 0

INPUT="$(cat 2>/dev/null)"
PROMPT="$(printf '%s' "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('prompt',''))" 2>/dev/null)"
[ -n "$PROMPT" ] || exit 0

case "$PROMPT" in
  "[자율실행]"*|*"<task-notification>"*|*"<system-reminder>"*|*"[SYSTEM NOTIFICATION"*|\
  *"Stop hook feedback"*|*"Harness Auto-Dispatch"*|*"[자동 실행 지시]"*|\
  *"[지시 분류 게이트]"*|*"hook blocking error"*|*"[Harness Freeze]"*)
    exit 0 ;;
esac

matched="$(printf '%s' "$PROMPT" | python3 -c '
import sys,re
p=sys.stdin.read(); n=0
if ("Traceback (most recent call last)" in p or
    re.search(r"^\s+at\s+\S+\s*\(.*:\d+:\d+\)",p,re.M) or
    re.search(r"^\s+File \"[^\"]+\", line \d+",p,re.M) or
    re.search(r"^\s+from\s+\S+:\d+:in ",p,re.M) or
    re.search(r"goroutine \d+ \[",p) or
    re.search(r"^\s+\S+\.go:\d+",p,re.M)): n+=1
if re.search(r"Error:|Exception|FATAL|panic:|SyntaxError|TypeError|NameError|undefined method|NoMethodError|segmentation fault",p,re.I): n+=1
if re.search(r"\b(?:500|502|503)\b",p) and re.search(r"error",p,re.I): n+=1
if any(x in p for x in ("안 된다","안돼","에러 나","터진다","죽는다","실패한다","왜 이래")): n+=1
if len(p.splitlines()) >= 5 and len(re.findall(r"\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}|^\[\d{2}:\d{2}:\d{2}",p,re.M)) >= 2: n+=1
print(n)' 2>/dev/null)"
case "$matched" in ''|*[!0-9]*) exit 0 ;; esac
[ "$matched" -ge 2 ] || exit 0

cat <<'EOF'
━━━ [근본원인 게이트] 오류 입력 감지 ━━━
증상만 고치지 마라. 아래 순서를 지켜라:
1. 재현 — 실패를 재현하는 최소 케이스를 먼저 만들어라
2. 조사 — 로그·스택·최근 diff에서 사실만 수집하라 (추측 금지)
3. 가설 — 근본원인 가설을 1문장으로 세우고 반증 시도하라
4. 수정 — 근본원인이 확정된 뒤에만 코드를 고쳐라
5. 검증 — 재현 케이스가 통과하는지 네가 직접 실행해 확인하라
Iron Law: 근본원인 없이 수정 금지. 첫 수정 시도 전에 1~3을 마쳐라.
심층 절차가 필요하면 Skill 도구로 investigate 를 호출하라.
━━━━━━━━━━━━━━━━━━━━━━━━
EOF
exit 0
