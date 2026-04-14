#!/bin/bash
# gemma-off.sh — 로컬 개발 모드: Gemma 4 E4B 완전 종료 + RAM 회수
# - SIGTERM → 2초 → SIGKILL 순차
# - runner 프로세스까지 확실히 종료
# - 락 파일 제거

LOCK_FILE="/tmp/ollama-harness.lock"
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

if ! pgrep -f "ollama" >/dev/null 2>&1; then
  echo -e "${YELLOW}[gemma-off] 실행 중인 ollama 없음${NC}"
  rm -f "$LOCK_FILE"
  exit 0
fi

# RAM 사용량 기록 (회수량 추정용)
before_mb=$(ps -eo rss,command | grep -E "ollama" | grep -v grep | awk '{sum+=$1} END {print int(sum/1024)}')

pkill -TERM -f "ollama" 2>/dev/null || true
sleep 2
pkill -9 -f "ollama" 2>/dev/null || true
sleep 1

if pgrep -f "ollama" >/dev/null 2>&1; then
  echo -e "${YELLOW}[gemma-off] 일부 잔존 → 재시도${NC}"
  pkill -9 -f "ollama" 2>/dev/null || true
  sleep 1
fi

rm -f "$LOCK_FILE"

# 회수량 표시
unused=$(top -l 1 | grep "PhysMem" | head -1)
echo -e "${GREEN}[gemma-off] 종료 완료 (회수 ~${before_mb:-?} MB)${NC}"
echo "  현재: $unused"
