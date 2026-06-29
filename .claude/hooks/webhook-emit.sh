#!/bin/bash
# webhook-emit.sh — 외부 알림 발신 (Slack / GitHub)
#
# 사용법:
#   bash webhook-emit.sh <EVENT_TYPE> <ISSUE_ID> <TITLE> <PRIORITY> [EXTRA_MSG]
#
# 환경변수:
#   SLACK_WEBHOOK_URL   — 미설정 시 Slack 발신 스킵 (silent)
#   GITHUB_REPO         — 미설정 시 GitHub 발신 스킵 (silent)
#
# 설계 원칙:
#   - 환경변수 미설정 / curl 실패 / gh 미설치 등 모든 오류에서 exit 0 (silent fail)
#   - 본 파이프라인에 절대 영향 없음 (fire-and-forget)
#   - 로그: .claude/hooks/.webhook.log 에 append

set -e

EVENT_TYPE="${1:-UNKNOWN}"
ISSUE_ID="${2:-UNKNOWN}"
TITLE="${3:-No title}"
PRIORITY="${4:-P1}"
EXTRA_MSG="${5:-}"

LOG_FILE="$(dirname "${BASH_SOURCE[0]}")/.webhook.log"
NOW="$(date '+%Y-%m-%dT%H:%M:%S')"

# 로그 기록 함수
_log() {
  echo "[$NOW] [$EVENT_TYPE] $ISSUE_ID [$PRIORITY] — $1" >> "$LOG_FILE" 2>/dev/null || true
}

# ─── Slack 발신 ───────────────────────────────────────────────
if [ -n "$SLACK_WEBHOOK_URL" ]; then
  # 우선순위별 이모지
  case "$PRIORITY" in
    P0) ICON=":red_circle:" ;;
    P1) ICON=":large_yellow_circle:" ;;
    P2) ICON=":large_blue_circle:" ;;
    *)  ICON=":white_circle:" ;;
  esac

  # 이벤트별 한글 레이블
  case "$EVENT_TYPE" in
    T2_USER_CONFIRM_REQUESTED) LABEL="[T2 컨펌 요청]" ;;
    P0_ISSUE_CREATED)          LABEL="[P0 이슈 생성]" ;;
    BUILD_FAILED)              LABEL="[빌드 실패]" ;;
    RACE_MODE_VERDICT)         LABEL="[레이스 판정]" ;;
    DEPLOY_READY)              LABEL="[배포 준비]" ;;
    ROLLBACK)                  LABEL="[롤백]" ;;
    *)                         LABEL="[$EVENT_TYPE]" ;;
  esac

  HEADER_TEXT="[Harness] $PRIORITY $EVENT_TYPE — $ISSUE_ID: $TITLE"
  BODY_TEXT="$LABEL $ISSUE_ID ($PRIORITY)\n$TITLE"
  if [ -n "$EXTRA_MSG" ]; then
    BODY_TEXT="$BODY_TEXT\n$EXTRA_MSG"
  fi

  SLACK_PAYLOAD=$(cat <<JSON
{
  "text": "$HEADER_TEXT",
  "blocks": [
    {
      "type": "section",
      "text": {
        "type": "mrkdwn",
        "text": "$ICON *$LABEL* \`$ISSUE_ID\` [$PRIORITY]\n>$TITLE"
      }
    },
    {
      "type": "context",
      "elements": [
        {
          "type": "mrkdwn",
          "text": "Harness Self-Evolving System • $NOW"
        }
      ]
    }
  ]
}
JSON
)

  # fire-and-forget: 백그라운드, 타임아웃 5초, 출력 버림
  curl -X POST \
    -H 'Content-type: application/json' \
    --data "$SLACK_PAYLOAD" \
    --max-time 5 \
    -s -o /dev/null \
    "$SLACK_WEBHOOK_URL" &
  _log "Slack 발신 시도"
else
  _log "SLACK_WEBHOOK_URL 미설정 — skip"
fi

# ─── GitHub Issue Comment 발신 ────────────────────────────────
if [ -n "$GITHUB_REPO" ] && command -v gh >/dev/null 2>&1; then
  GH_COMMENT="**[Harness] $EVENT_TYPE** — \`$ISSUE_ID\` [$PRIORITY]

> $TITLE

$( [ -n "$EXTRA_MSG" ] && echo "$EXTRA_MSG" || true )

*발신 시각: $NOW*"

  # 이슈 번호 추출 시도 (ISSUE_ID에 숫자가 있으면 사용, 없으면 1)
  ISSUE_NUM=$(echo "$ISSUE_ID" | grep -oE '[0-9]+$' | head -1)
  if [ -z "$ISSUE_NUM" ]; then
    ISSUE_NUM=1
  fi

  gh issue comment "$ISSUE_NUM" \
    --body "$GH_COMMENT" \
    --repo "$GITHUB_REPO" \
    >/dev/null 2>&1 || true

  _log "GitHub comment 시도 (repo=$GITHUB_REPO issue=$ISSUE_NUM)"
else
  _log "GITHUB_REPO 미설정 또는 gh CLI 없음 — skip"
fi

exit 0
