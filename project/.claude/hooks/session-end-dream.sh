#!/usr/bin/env bash
# ============================================================
# session-end-dream.sh — SessionEnd 훅 래퍼
# Claude Code 세션 종료 시 daily-dream.sh를 호출하되,
# 하루 1회만 실행하도록 가드한다. (launchd 대체)
#
# 동작:
#   - 마지막 실행 날짜를 .claude/knowledge-db/.dream.last_run에 기록
#   - 같은 날(KST 기준) 재호출 시 skip
#   - 다른 날이면 daily-dream.sh 백그라운드 실행
#   - daily-dream.sh가 없으면 skip 로그를 남기고 종료, 있으면 실행 직전 triggered 로그 기록
#   - 어떤 에러도 부모(Claude Code)에 전파하지 않음 (fire-and-forget)
# ============================================================

set +e  # 절대 에러 전파 금지

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || exit 0
if [[ -n "$CLAUDE_PROJECT_DIR" && -d "$CLAUDE_PROJECT_DIR/.claude" ]]; then
  PROJECT_ROOT="$CLAUDE_PROJECT_DIR"
elif [[ -d "$PWD/.claude" ]]; then
  PROJECT_ROOT="$PWD"
else
  PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." 2>/dev/null && pwd)" || exit 0
fi
STAMP_FILE="$PROJECT_ROOT/.claude/knowledge-db/.dream.last_run"
DREAM_SH="$SCRIPT_DIR/daily-dream.sh"
LOG_FILE="$PROJECT_ROOT/.claude/knowledge-db/.dream.session.log"

mkdir -p "$(dirname "$STAMP_FILE")" 2>/dev/null

if [[ ! -f "$PROJECT_ROOT/.claude/issue-db/registry.json" ]]; then
  echo "[$(date -u +%FT%TZ)] dream SKIPPED — no registry at $PROJECT_ROOT/.claude/issue-db/registry.json" >> "$LOG_FILE" 2>/dev/null
  exit 0
fi

# KST 기준 오늘 날짜 (YYYY-MM-DD)
today_kst=$(TZ="Asia/Seoul" date +%Y-%m-%d 2>/dev/null) || exit 0

# 마지막 실행 날짜 비교
last_run=""
if [[ -f "$STAMP_FILE" ]]; then
  last_run=$(cat "$STAMP_FILE" 2>/dev/null)
fi

if [[ "$last_run" == "$today_kst" ]]; then
  # 오늘 이미 실행함 — skip
  echo "[$(date -u +%FT%TZ)] dream skipped — already ran today ($today_kst)" >> "$LOG_FILE" 2>/dev/null
  exit 0
fi

# 실행 — 백그라운드, stdout/stderr 모두 로그로

if [[ -x "$DREAM_SH" ]] || [[ -f "$DREAM_SH" ]]; then
  echo "[$(date -u +%FT%TZ)] dream triggered — last_run=$last_run today=$today_kst" >> "$LOG_FILE" 2>/dev/null
  (
    cd "$PROJECT_ROOT" 2>/dev/null || exit 0
    bash "$DREAM_SH" >> "$LOG_FILE" 2>&1
    rc=$?
    if [[ $rc -eq 0 ]]; then
      echo "$today_kst" > "$STAMP_FILE" 2>/dev/null
      echo "[$(date -u +%FT%TZ)] dream completed OK" >> "$LOG_FILE" 2>/dev/null
    else
      echo "[$(date -u +%FT%TZ)] dream exited rc=$rc (stamp not updated)" >> "$LOG_FILE" 2>/dev/null
    fi
  ) &
  disown 2>/dev/null
else
  echo "[$(date -u +%FT%TZ)] dream SKIPPED — daily-dream.sh not found at $DREAM_SH" >> "$LOG_FILE" 2>/dev/null
  exit 0
fi

exit 0
