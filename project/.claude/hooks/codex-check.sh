#!/bin/bash
# codex-check.sh — CHECK 축 외부 LLM(Codex) 호출 래퍼
#
# 현재 상태: 스켈레톤 (비활성). Phase 2 이후 활성화 예정.
# 환경변수 CHECK_PROVIDER=codex 설정 시에만 호출됨.
#
# 사용법:
#   bash codex-check.sh <이슈ID> <check_mode> <payload_json>
#
# 출력: JSON result (on_complete.sh 포맷 호환)
#   { "passed": bool, "critical_count": N, "major_count": N,
#     "findings": [...], "provider": "codex" }
#
# Fallback: codex CLI 미설치/실패 시 claude로 자동 전환 (exit 78)

set -euo pipefail

ISSUE_ID="${1:-}"
CHECK_MODE="${2:-}"
PAYLOAD="${3:-{}}"

if [ -z "$ISSUE_ID" ] || [ -z "$CHECK_MODE" ]; then
  echo '{"error":"missing args","provider":"codex","passed":false}' >&2
  exit 1
fi

# Phase 1: 기능 비활성 — 명시적 차단
if [ "${CHECK_PROVIDER:-claude}" != "codex" ] && [ "${CHECK_PROVIDER:-claude}" != "hybrid" ]; then
  echo '{"error":"codex provider disabled (CHECK_PROVIDER=claude)","provider":"codex","passed":false,"fallback":"claude"}'
  exit 78  # fallback signal
fi

# codex CLI 존재 확인
if ! command -v codex >/dev/null 2>&1; then
  echo '{"error":"codex CLI not installed","provider":"codex","passed":false,"fallback":"claude"}'
  exit 78
fi

# 모드별 프롬프트 파일 결정
MODE_FILE_MAP=(
  "code:code-quality.md"
  "test:test-harness.md"
  "eval:eval-harness.md"
  "biz:biz-validator.md"
  "journey:journey-validator.md"
  "scenario:scenario-player.md"
  "design:design-critic.md"
  "brand:brand-guardian.md"
  "qa:qa-reviewer.md"
  "meta:meta-agent.md"
)

MODE_FILE=""
for entry in "${MODE_FILE_MAP[@]}"; do
  key="${entry%%:*}"
  val="${entry##*:}"
  if [ "$key" = "$CHECK_MODE" ]; then
    MODE_FILE="$HOME/.claude/agents/$val"
    break
  fi
done

if [ -z "$MODE_FILE" ] || [ ! -f "$MODE_FILE" ]; then
  echo "{\"error\":\"mode file not found for $CHECK_MODE\",\"provider\":\"codex\",\"passed\":false,\"fallback\":\"claude\"}"
  exit 78
fi

# Phase 2+ 실제 구현 위치 (현재는 주석으로만 남김)
# -----------------------------------------------------------
# INSTRUCTION=$(cat "$MODE_FILE")
# PROMPT=$(cat <<EOF
# You are acting as CHECK agent in mode: $CHECK_MODE
# Issue: $ISSUE_ID
# Payload: $PAYLOAD
#
# Instruction:
# $INSTRUCTION
#
# Output strictly as JSON:
# {"passed":bool, "critical_count":N, "major_count":N, "minor_count":N,
#  "findings":[{"severity":"critical|major|minor","msg":"...","location":"..."}],
#  "provider":"codex"}
# EOF
# )
#
# echo "$PROMPT" | codex review --json 2>/dev/null || exit 78
# -----------------------------------------------------------

# 현재는 스켈레톤 응답
echo '{"error":"codex integration not yet implemented (Phase 2)","provider":"codex","passed":false,"fallback":"claude"}'
exit 78
