#!/usr/bin/env bash
# 오케스트레이션 규칙 사후 강제 #1 — 직접 코딩 감지 (전역 PreToolUse: Edit|Write)
#
# 목적: 규칙(코딩=Codex, Opus=오케스트레이터)을 "읽고도 안 지키는" 상태를 사후 검사로 교정.
#       orchestration-label.sh는 사전 리마인더일 뿐 위반을 못 막는다. 이 hook이 실제 강제.
#
# 동작: Opus 메인 세션이 코드 파일을 직접 Edit/Write하려 하면 stderr로 경고를 띄운다.
#       차단(exit 2)이 아니라 경고(exit 0)다 — 예외(1~2줄/문서/설정)를 죽이지 않기 위함.
#       경고는 대표님·나 양쪽 화면에 떠서 "지금 Codex 위임 규칙을 건너뛰고 있다"를 자각시킨다.
#
# 예외(경고 안 함):
#   - 문서/설정 파일(.md .json .txt .yaml .yml .sh .toml .cfg) — 코드 로직 아님
#   - 서브에이전트 실행 컨텍스트(CLAUDE_AGENT_* 존재) — 이미 위임된 상태
#   - registry/hook/scratchpad 등 하네스 내부 파일
#
# 근거: ~/.claude/CLAUDE.md "LLM 오케스트레이션 — 코딩=Codex" + 규칙2(검증자 독립성)
set -uo pipefail

INPUT="$(cat 2>/dev/null || true)"

# 서브에이전트 안에서의 편집은 이미 위임된 것 — 통과
[ -n "${CLAUDE_AGENT_NAME:-}${CLAUDE_SUBAGENT:-}${HARNESS_HEADLESS:-}" ] && exit 0

FILE="$(printf '%s' "$INPUT" | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    ti=d.get('tool_input',{})
    print(ti.get('file_path') or ti.get('path') or '')
except: print('')
" 2>/dev/null || true)"

[ -z "$FILE" ] && exit 0

# 코드 파일 확장자만 대상 (로직이 담기는 파일)
case "$FILE" in
  *.py|*.js|*.jsx|*.ts|*.tsx|*.vue|*.svelte|*.rb|*.go|*.rs|*.java|*.kt|*.swift|*.c|*.cpp|*.h|*.php|*.ex|*.exs|*.scala) ;;
  *) exit 0 ;;  # 문서/설정/스크립트 등은 예외
esac

# ERB/뷰 템플릿은 UI 작업 — Codex 위임 대상이지만 경고는 약하게(뷰는 직접 손대는 빈도 높음)
# (확장자 필터에서 이미 .erb 제외됨 — 뷰는 통과)

# 하네스 내부 경로는 예외
case "$FILE" in
  */.claude/*|*/hooks/*|*/harness-core/*|*/scratchpad/*|*/node_modules/*) exit 0 ;;
esac

VIOLATION_LOG="$HOME/.claude/.orch-violations.log"
TS="$(python3 -c 'import datetime;print(datetime.datetime.now().isoformat())' 2>/dev/null || echo now)"
echo "$TS PRECODE $FILE" >> "$VIOLATION_LOG" 2>/dev/null || true

cat >&2 <<WARN

⚠️ [오케스트레이션 규칙 경고] 코드 파일 직접 편집 감지: $(basename "$FILE")
   규약: 코딩=Codex, Opus(나)=오케스트레이터·검수자.
   → 실작업 구현이면 codex exec로 위임하라. 다음 3가지만 직접 허용:
     ① 1~2줄 기계적 수정  ② Codex CLI 미설치/미연동  ③ 대표님이 "직접 짜" 명시
   → 위 예외에 해당하면 그대로 진행. 아니면 지금 편집을 멈추고 Codex에 위임하라.
   (이 경고는 차단이 아니다. 판단은 나에게 있다 — 단, 어긴 채 진행하면 규칙 위반이다.)
WARN

exit 0
