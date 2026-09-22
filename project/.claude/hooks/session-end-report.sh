#!/usr/bin/env bash
# SessionEnd에서 전체 포트폴리오 일일활동보고서 PDF를 KST 하루 1회 생성한다.
# launchd의 macOS TCC 외장 볼륨 읽기 차단을 피해 FDA 보유 세션에서 실행한다.
# 공용 잠금으로 중복 실행을 막고, 백그라운드 실행 성공 시에만 날짜를 기록한다.

set +e  # 어떤 오류도 Claude Code 세션 종료에 전파하지 않는다.

HARNESS_DIR="/Volumes/E_SSD/02_GitHub.nosync/GH_Harness"
REPORT_SH="$HARNESS_DIR/bin/daily-report.sh"
STAMP_FILE="$HARNESS_DIR/Report/.report.last_run"
LOG_FILE="$HARNESS_DIR/Report/.report.session.log"
LOCK_DIR="$HARNESS_DIR/Report/.report.session.lock"

log() {
  local message="[$(date -u +%FT%TZ)] $1"
  { printf '%s\n' "$message" >> "$LOG_FILE"; } 2>/dev/null ||
    printf '%s\n' "$message" >&2
}

if [[ ! -d "$HARNESS_DIR" ]]; then
  log 'report SKIPPED — volume not mounted'
  exit 0
fi
mkdir -p "$HARNESS_DIR/Report" 2>/dev/null || {
  log 'report SKIPPED — Report directory unavailable'
  exit 0
}
if [[ ! -f "$REPORT_SH" ]]; then
  log "report SKIPPED — daily-report.sh not found at $REPORT_SH"
  exit 0
fi

(
  mkdir "$LOCK_DIR" 2>/dev/null || {
    log 'report SKIPPED — lock unavailable (another run may be active)'
    exit 0
  }
  trap 'rmdir "$LOCK_DIR" 2>/dev/null' EXIT
  trap 'exit 0' HUP INT TERM
  today_kst=$(TZ="Asia/Seoul" date +%Y-%m-%d 2>/dev/null) || exit 0
  last_run=""
  [[ ! -f "$STAMP_FILE" ]] || last_run=$(cat "$STAMP_FILE" 2>/dev/null)
  if [[ "$last_run" == "$today_kst" ]]; then
    log "report skipped — already ran today ($today_kst)"
    exit 0
  fi
  export OPEN_AFTER=0
  bash "$REPORT_SH" >> "$LOG_FILE" 2>&1
  rc=$?
  if [[ $rc -eq 0 ]]; then
    { printf '%s\n' "$today_kst" > "$STAMP_FILE"; } 2>/dev/null ||
      log 'report WARNING — stamp write failed'
    log 'report completed OK'
  else
    log "report exited rc=$rc (stamp not updated)"
  fi
  exit 0
) </dev/null >/dev/null 2>&1 &
disown 2>/dev/null

exit 0
