#!/bin/bash
# sandbox-enforce.sh — PreToolUse Bash 명령 검사 (v4.1 C-lite)
#
# 정책: SANDBOX_POLICY.md (3-Tier: BLOCK / WARN+T2 / ALLOW)
#
# 입력 (PreToolUse hook 표준):
#   stdin: tool_input JSON
#   환경: CLAUDE_TOOL_NAME, CLAUDE_TOOL_INPUT
#
# 출력:
#   exit 0 = 허용
#   exit 1 = 거부 (stderr에 사유)
#
# Bypass:
#   HARNESS_SANDBOX_BYPASS=1 → BLOCK도 WARN으로 강등
#   HARNESS_SANDBOX_BYPASS=2 → 완전 비활성 (디버그용)

set -euo pipefail

# tool이 Bash가 아니면 통과
TOOL_NAME="${CLAUDE_TOOL_NAME:-}"
if [ -n "$TOOL_NAME" ] && [ "$TOOL_NAME" != "Bash" ]; then
  exit 0
fi

# stdin 우선, 실패 시 env fallback
INPUT=""
if [ ! -t 0 ]; then
  INPUT="$(cat 2>/dev/null || true)"
fi
if [ -z "$INPUT" ] && [ -n "${CLAUDE_TOOL_INPUT:-}" ]; then
  INPUT="$CLAUDE_TOOL_INPUT"
fi

# JSON에서 command 추출 (간단 파싱, jq 없어도 동작)
CMD="$(printf '%s' "$INPUT" | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin); print(d.get("command",""))
except: pass' 2>/dev/null || true)"

# 파싱 실패 시 INPUT 자체를 CMD로
if [ -z "$CMD" ]; then
  CMD="$INPUT"
fi

# 완전 비활성 모드
if [ "${HARNESS_SANDBOX_BYPASS:-0}" = "2" ]; then
  exit 0
fi

# ── BLOCK 패턴 ──────────────────────────────────────
BLOCK_PATTERNS=(
  'rm[[:space:]]+-[rRf]{1,3}[[:space:]]+/([[:space:]]|$)'
  'rm[[:space:]]+-[rRf]{1,3}[[:space:]]+~([[:space:]]|$|/)'
  'rm[[:space:]]+-[rRf]{1,3}[[:space:]]+\*'
  ':[[:space:]]*\(\)[[:space:]]*\{'
  'mkfs\.'
  'dd[[:space:]]+.*of=/dev/'
  'chmod[[:space:]]+-R[[:space:]]+777[[:space:]]+/'
  'curl[[:space:]].*\|[[:space:]]*(sh|bash|zsh)([[:space:]]|$)'
  'wget[[:space:]].*\|[[:space:]]*(sh|bash|zsh)([[:space:]]|$)'
  'sudo[[:space:]]+rm'
)

# ── WARN + T2 패턴 ──────────────────────────────────
# 형식: "pattern<TAB>T2_CATEGORY<TAB>사유"  (정규식 내 | 충돌 회피)
TAB=$'\t'
WARN_PATTERNS=(
  "git[[:space:]]+push[[:space:]]+(-f|--force)${TAB}EXTERNAL${TAB}git push -f 히스토리 덮어쓰기"
  "git[[:space:]]+reset[[:space:]]+--hard${TAB}EXTERNAL${TAB}로컬 변경 소실 위험"
  "git[[:space:]]+clean[[:space:]]+-f${TAB}EXTERNAL${TAB}추적되지 않은 파일 삭제"
  "DROP[[:space:]]+TABLE${TAB}SECURITY${TAB}DB 테이블 파괴"
  "DROP[[:space:]]+DATABASE${TAB}SECURITY${TAB}DB 삭제"
  "TRUNCATE[[:space:]]+${TAB}SECURITY${TAB}데이터 전량 삭제"
  "kubectl[[:space:]]+delete${TAB}EXTERNAL${TAB}쿠버네티스 리소스 삭제"
  "kamal[[:space:]]+(app[[:space:]]+)?remove${TAB}EXTERNAL${TAB}배포 삭제"
  "npm[[:space:]]+publish${TAB}EXTERNAL${TAB}npm 레지스트리 배포"
  "pip[[:space:]]+upload${TAB}EXTERNAL${TAB}pip 레지스트리 배포"
)

# 로그 함수
log_sandbox() {
  local event="$1"
  local cmd_preview="${2:0:200}"
  local trace_sh="$(dirname "${BASH_SOURCE[0]}")/decision-trace.sh"
  if [ -x "$trace_sh" ]; then
    bash "$trace_sh" "sandbox_$event" "-" "command=$cmd_preview" 2>/dev/null || true
  fi
}

# BLOCK 검사
for pat in "${BLOCK_PATTERNS[@]}"; do
  if printf '%s' "$CMD" | grep -qE "$pat"; then
    if [ "${HARNESS_SANDBOX_BYPASS:-0}" = "1" ]; then
      echo "⚠️ [Sandbox] BYPASS 모드 — BLOCK 패턴이지만 WARN으로 강등: $pat" >&2
      log_sandbox "bypass" "$CMD"
      exit 0
    fi
    echo "🛑 [Sandbox BLOCK] 명령 거부" >&2
    echo "    패턴: $pat" >&2
    echo "    명령: ${CMD:0:200}" >&2
    echo "    정책: GH_Harness/global/policy/SANDBOX_POLICY.md" >&2
    echo "    우회: 필요 시 HARNESS_SANDBOX_BYPASS=1 후 재실행 (위험)" >&2
    log_sandbox "block" "$CMD"
    exit 1
  fi
done

# WARN 검사
for entry in "${WARN_PATTERNS[@]}"; do
  pat="${entry%%$'\t'*}"
  rest="${entry#*$'\t'}"
  cat="${rest%%$'\t'*}"
  reason="${rest#*$'\t'}"
  if printf '%s' "$CMD" | grep -qE "$pat"; then
    # T2 컨펌 요청 (request-user-confirm.sh 있으면)
    rcf="$(dirname "${BASH_SOURCE[0]}")/request-user-confirm.sh"
    if [ -x "$rcf" ]; then
      echo "⚠️ [Sandbox WARN] $cat — $reason" >&2
      echo "    명령: ${CMD:0:200}" >&2
      echo "    → T2 컨펌 요청 (request-user-confirm.sh)" >&2
      # 이슈 ID 없으면 "-" 전달
      bash "$rcf" "-" "$cat" "명령 실행 승인 필요: $reason. 명령: ${CMD:0:120}" 2>/dev/null || true
      log_sandbox "warn_t2" "$CMD"
      # T2는 사용자 응답을 기다리지 않고 일단 차단 (User가 다시 트리거하도록)
      exit 1
    else
      echo "⚠️ [Sandbox WARN] $cat — $reason (T2 hook 부재 → 경고만)" >&2
      log_sandbox "warn_only" "$CMD"
      exit 0
    fi
  fi
done

# ALLOW (로그 생략 — 너무 많음)
exit 0
