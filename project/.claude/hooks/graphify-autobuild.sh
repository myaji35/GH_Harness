#!/bin/bash
# graphify-autobuild.sh — graphify 그래프 자동 증분 갱신 (전 프로젝트 상시 운영)
#
# 호출 방식:
#   SessionStart:  graphify-autobuild.sh session   → 그래프 없으면 초기 1회 빌드, 있으면 증분
#   PostToolUse:   graphify-autobuild.sh change <file>  → 변경 파일 기준 증분 갱신 (디바운스)
#
# 설계 원칙 (v5.1 Fable 정책 정합):
#   - .claude/graphify/ 미설치 → 즉시 skip (게이트)
#   - graph.json 본체가 없으면 = 초기 빌드 필요 (scaffold만 깔린 상태)
#   - 증분(--update)만 사용해 LLM 비용 최소화. 전체 재빌드 안 함.
#   - PostToolUse는 디바운스(기본 90초) — 매 편집마다 빌드하면 파이프라인 저하.
#   - 비대화/대화 모두 동작하되, 실패해도 파이프라인 절대 막지 않음(exit 0 보장).

set +e  # graphify 실패가 harness를 멈추면 안 됨

MODE="${1:-session}"
CHANGED_FILE="${2:-}"
GDIR=".claude/graphify"
GRAPH="$GDIR/graphify-out/graph.json"
DEBOUNCE_FILE="$GDIR/.last-autobuild"
DEBOUNCE_SEC="${GRAPHIFY_DEBOUNCE_SEC:-90}"
LOG="$GDIR/autobuild.log"

# ── 게이트 1: scaffold 미설치 → skip ──────────────────
[ -d "$GDIR" ] || exit 0

# ── 게이트 2: graphify CLI 가용성 ─────────────────────
# /graphify는 스킬(LLM 경유)이라 셸에서 직접 못 부른다.
# 이 hook은 "갱신이 필요하다"는 신호 파일만 남기고, 실제 빌드는
# Claude Code가 graphify 스킬을 호출해 수행한다(아래 SIGNAL).
SIGNAL="$GDIR/.rebuild-needed"

now=$(date +%s)

log() { echo "[$(date -u +%H:%M:%S)] $*" >> "$LOG" 2>/dev/null; }

# ── 디바운스 검사 ─────────────────────────────────────
debounced() {
  [ -f "$DEBOUNCE_FILE" ] || return 1
  local last; last=$(cat "$DEBOUNCE_FILE" 2>/dev/null || echo 0)
  [ $((now - last)) -lt "$DEBOUNCE_SEC" ]
}

case "$MODE" in
  session)
    if [ ! -f "$GRAPH" ]; then
      # 초기 빌드 필요 — scaffold만 있고 그래프 본체 없음
      echo "build" > "$SIGNAL"
      log "session: 초기 그래프 없음 → BUILD 신호"
      echo "GRAPHIFY_SIGNAL=build"   # Claude Code가 읽어 /graphify . --update 실행
    elif [ -f "$SIGNAL" ]; then
      log "session: 대기 중 rebuild 신호 존재 → UPDATE"
      echo "GRAPHIFY_SIGNAL=update"
    else
      log "session: 그래프 최신 → noop"
    fi
    ;;
  change)
    # 변경 파일이 그래프 대상(코드/문서)인지 가벼운 필터
    case "$CHANGED_FILE" in
      *.md|*.py|*.ts|*.tsx|*.js|*.jsx|*.rb|*.go|*.rs|*.java|*.vue|*.svelte|*.yaml|*.yml|*.json)
        if debounced; then
          log "change($CHANGED_FILE): 디바운스 — 신호만 누적"
          echo "update" > "$SIGNAL"
        else
          echo "$now" > "$DEBOUNCE_FILE"
          echo "update" > "$SIGNAL"
          log "change($CHANGED_FILE): UPDATE 신호"
          echo "GRAPHIFY_SIGNAL=update"
        fi
        ;;
      *)
        : # 그래프 비대상 파일 — 무시
        ;;
    esac
    ;;
esac

exit 0
