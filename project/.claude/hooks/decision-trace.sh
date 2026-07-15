#!/bin/bash
# decision-trace.sh — 이슈 라이프사이클 이벤트를 JSONL로 기록 (GH_Harness v4.1)
#
# 사용:
#   bash decision-trace.sh <event> <issue_id> [key=value ...]
#
# 이벤트 타입:
#   created / dispatched / started / paused / resumed
#   completed / failed / blocked / reopened
#
# 예시:
#   bash decision-trace.sh dispatched ISS-091 agent=agent-harness model=sonnet tier=T0
#   bash decision-trace.sh completed ISS-091 passed=true duration_ms=12400
#
# 저장 위치: .claude/trace/YYYY-MM-DD.jsonl

set -euo pipefail

EVENT="${1:-}"
ISSUE_ID="${2:-}"
shift 2 || true

if [ -z "$EVENT" ] || [ -z "$ISSUE_ID" ]; then
  echo "[decision-trace] usage: $0 <event> <issue_id> [key=value ...]" >&2
  exit 1
fi

TRACE_DIR=".claude/trace"
mkdir -p "$TRACE_DIR"
TRACE_FILE="$TRACE_DIR/$(date -u +%Y-%m-%d).jsonl"

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# 키=값 쌍을 JSON 조각으로 변환
EXTRA=""
for arg in "$@"; do
  if [[ "$arg" == *=* ]]; then
    K="${arg%%=*}"
    V="${arg#*=}"
    # 숫자/bool은 따옴표 없이, 나머지는 따옴표
    if [[ "$V" =~ ^-?[0-9]+(\.[0-9]+)?$ ]] || [[ "$V" == "true" ]] || [[ "$V" == "false" ]] || [[ "$V" == "null" ]]; then
      EXTRA="$EXTRA,\"$K\":$V"
    else
      V_ESC="${V//\\/\\\\}"
      V_ESC="${V_ESC//\"/\\\"}"
      EXTRA="$EXTRA,\"$K\":\"$V_ESC\""
    fi
  fi
done

LINE="{\"ts\":\"$TS\",\"event\":\"$EVENT\",\"issue\":\"$ISSUE_ID\"$EXTRA}"
echo "$LINE" >> "$TRACE_FILE"

# 디버그용: TRACE_DEBUG=1 설정 시 stderr로도 출력
if [ "${TRACE_DEBUG:-0}" = "1" ]; then
  echo "[trace] $LINE" >&2
fi
