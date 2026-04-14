#!/bin/bash
# gemma-off.sh — 로컬 개발 모드: Gemma 4 E4B 종료 (RAM 회수)
# 사용: bash .claude/hooks/gemma-off.sh  (또는 alias 'gemma-off')

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

if ! pgrep -x ollama >/dev/null; then
  echo -e "${YELLOW}[gemma-off] 실행 중인 ollama 프로세스 없음${NC}"
  exit 0
fi

BEFORE=$(ps -o rss= -p $(pgrep ollama) 2>/dev/null | awk '{sum+=$1} END {print int(sum/1024)}')
pkill -TERM ollama 2>/dev/null
sleep 2
# 좀비 잔존 시 SIGKILL
pkill -9 ollama 2>/dev/null || true
sleep 1

if pgrep -x ollama >/dev/null; then
  echo -e "${YELLOW}[gemma-off] 일부 프로세스 잔존 → 재시도${NC}"
  pkill -9 ollama 2>/dev/null || true
fi

echo -e "${GREEN}[gemma-off] 종료 완료 (회수 RAM: 약 ${BEFORE:-?} MB)${NC}"
