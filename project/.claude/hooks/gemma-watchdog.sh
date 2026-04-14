#!/bin/bash
# gemma-watchdog.sh — Gemma idle 자동 종료 감시자
# 사용: bash .claude/hooks/gemma-watchdog.sh &
#
# 동작:
#   - 15분마다 /api/ps 체크
#   - RAM에 로드된 모델이 없고 ollama만 떠있으면 N 분 후 자동 종료
#   - ollama가 꺼져있으면 watchdog도 스스로 종료

IDLE_THRESHOLD_MIN=${GEMMA_IDLE_MIN:-15}
CHECK_INTERVAL_SEC=${GEMMA_CHECK_SEC:-60}
ENDPOINT="http://localhost:11434"
WATCHDOG_PID_FILE="/tmp/gemma-watchdog.pid"

# 중복 실행 방지
if [ -f "$WATCHDOG_PID_FILE" ]; then
  old_pid=$(cat "$WATCHDOG_PID_FILE")
  if kill -0 "$old_pid" 2>/dev/null; then
    echo "[watchdog] 이미 실행 중 (pid=$old_pid) — skip"
    exit 0
  fi
fi
echo $$ > "$WATCHDOG_PID_FILE"

idle_accum_min=0

cleanup() { rm -f "$WATCHDOG_PID_FILE"; exit 0; }
trap cleanup INT TERM

while true; do
  # ollama 꺼지면 watchdog 종료
  if ! pgrep -x ollama >/dev/null; then
    echo "[watchdog] ollama OFF → watchdog 종료"
    cleanup
  fi

  # API 응답 체크 (로드된 모델 수)
  loaded_count=$(curl -s --max-time 2 "$ENDPOINT/api/ps" 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('models',[])))" 2>/dev/null || echo 0)

  if [ "$loaded_count" -eq 0 ]; then
    idle_accum_min=$((idle_accum_min + CHECK_INTERVAL_SEC / 60))
    if [ "$idle_accum_min" -ge "$IDLE_THRESHOLD_MIN" ]; then
      echo "[watchdog] idle ${idle_accum_min}분 → ollama 자동 종료"
      pkill -TERM ollama 2>/dev/null || true
      sleep 2
      pkill -9 ollama 2>/dev/null || true
      rm -f /tmp/ollama-harness.lock
      cleanup
    fi
  else
    idle_accum_min=0  # 로드된 모델 있으면 idle 리셋
  fi

  sleep "$CHECK_INTERVAL_SEC"
done
