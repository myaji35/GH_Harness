#!/bin/bash
# budget-track-agent.sh — PreToolUse(Agent|Task): 상위 모델 서브에이전트 스폰 시점에 예산 기록 (ISS-731)
#
# 종전에는 dispatch-ready.sh 추천 단계에서만 opus-budget-check.sh 를 불러,
# 메인 세션이 Agent 도구로 직접 띄운 opus/fable 서브에이전트는 한 번도 기록되지 않았다
# (opus_budget_state 가 2026-07-15 에 멈춤). 실제 스폰 지점에서 기록한다.
#
# - 예산 대상 아님(sonnet/haiku 에이전트) → 통과
# - 강등 판정(fable→opus, opus→sonnet) → tool_input.model 을 바꿔 스폰
# - BLOCKED(Hard Cap + 강등 불가) → 스폰 거부 + BUDGET T2 안내
# 실패해도 스폰을 막지 않는다(exit 0).

DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$DIR" 2>/dev/null || exit 0
[ -f .claude/issue-db/registry.json ] || exit 0
[ -f .claude/hooks/opus-budget-check.sh ] || exit 0

INPUT=$(cat)
AGENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null)
[ -n "$AGENT" ] || exit 0

ERR=$(mktemp "${TMPDIR:-/tmp}/budget-track.XXXXXX") || exit 0
MODEL=$(bash .claude/hooks/opus-budget-check.sh "$AGENT" 2>"$ERR" | tail -1)
RC=${PIPESTATUS[0]}
DEMOTED=$(grep -c "강등" "$ERR" 2>/dev/null)
rm -f "$ERR"

if [ "$MODEL" = "BLOCKED" ] || [ "$RC" = "3" ]; then
  jq -n --arg a "$AGENT" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny",
    permissionDecisionReason: ("[opus-budget] " + $a + " 호출이 일일 상위모델 Hard Cap($20)을 초과합니다. request-user-confirm.sh 로 BUDGET T2 컨펌을 요청하세요.")}}'
  exit 0
fi

# 강등 판정이 났을 때만 모델을 바꿔 스폰한다. 예산 대상이 아닌 에이전트도 "sonnet" 을 받으므로
# 출력 모델만 보고 덮어쓰면 haiku·Explore 등까지 바뀐다.
if [ "${DEMOTED:-0}" -gt 0 ] && [ "$MODEL" = "opus" -o "$MODEL" = "sonnet" ]; then
  printf '%s' "$INPUT" | jq --arg m "$MODEL" '{hookSpecificOutput: {hookEventName: "PreToolUse",
    updatedInput: (.tool_input + {model: $m})}}'
fi
exit 0
