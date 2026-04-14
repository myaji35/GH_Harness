#!/bin/bash
# gemma-on.sh — 로컬 개발 모드: Gemma 4 E4B 켜기
# 사용: bash .claude/hooks/gemma-on.sh  (또는 alias 'gemma-on')

set -euo pipefail

OLLAMA_HOME="/Volumes/E_SSD/ollama-models"
MODEL="gemma4:e4b"
ENDPOINT="http://localhost:11434"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

# 이미 기동 중이면 중복 실행 방지
if pgrep -x ollama >/dev/null; then
  echo -e "${YELLOW}[gemma-on] 이미 실행 중 (pid=$(pgrep ollama | head -1))${NC}"
  curl -s "$ENDPOINT/api/tags" >/dev/null 2>&1 && echo -e "${GREEN}  API 응답 정상${NC}"
  exit 0
fi

echo -e "${GREEN}[gemma-on] ollama 서버 기동 중...${NC}"
OLLAMA_MODELS="$OLLAMA_HOME" nohup ollama serve > /tmp/ollama.log 2>&1 &
sleep 3

if pgrep -x ollama >/dev/null; then
  echo -e "${GREEN}  pid=$(pgrep ollama | head -1) / endpoint=$ENDPOINT${NC}"
  if ollama list 2>/dev/null | grep -q "$MODEL"; then
    echo -e "${GREEN}  모델 확인: $MODEL${NC}"
  else
    echo -e "${RED}  경고: $MODEL 미설치 → OLLAMA_MODELS=$OLLAMA_HOME ollama pull $MODEL${NC}"
  fi
  echo ""
  echo "사용 종료 시: bash .claude/hooks/gemma-off.sh  (또는 'gemma-off')"
else
  echo -e "${RED}[gemma-on] 기동 실패 — /tmp/ollama.log 확인${NC}"
  exit 1
fi
