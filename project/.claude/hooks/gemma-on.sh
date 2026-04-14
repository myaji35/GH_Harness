#!/bin/bash
# gemma-on.sh — 로컬 개발 모드: Gemma 4 E4B 안전 기동
# 특징:
#   - 중복 기동 방지 (락 파일 + pgrep 이중 체크)
#   - RAM 사전 체크 (여유 3GB 미만이면 거부)
#   - 좀비 프로세스 자동 정리
#   - 모델 존재 검증

set -uo pipefail

OLLAMA_HOME="/Volumes/E_SSD/ollama-models"
MODEL="gemma4:e4b"
ENDPOINT="http://localhost:11434"
LOCK_FILE="/tmp/ollama-harness.lock"
MIN_FREE_MB=3072

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

# ── 1. 이미 실행 중이면 즉시 반환 (락 + 프로세스 이중 체크) ──
if [ -f "$LOCK_FILE" ] && [ -s "$LOCK_FILE" ]; then
  locked_pid=$(cat "$LOCK_FILE" 2>/dev/null | tr -dc '0-9')
  if [ -n "$locked_pid" ] && kill -0 "$locked_pid" 2>/dev/null; then
    echo -e "${YELLOW}[gemma-on] 이미 실행 중 (pid=$locked_pid, 락 파일 유효)${NC}"
    exit 0
  fi
  # 고아 락 파일 정리
  rm -f "$LOCK_FILE"
fi

if pgrep -x ollama >/dev/null; then
  existing_pid=$(pgrep -x ollama | head -1)
  echo -e "${YELLOW}[gemma-on] ollama 실행 중 (pid=$existing_pid) → 락 파일 복구${NC}"
  echo "$existing_pid" > "$LOCK_FILE"
  exit 0
fi

# ── 2. 좀비 runner 프로세스 정리 ────────────────────
if pgrep -f "ollama runner" >/dev/null 2>&1; then
  echo -e "${YELLOW}[gemma-on] 좀비 runner 감지 → 정리${NC}"
  pkill -9 -f "ollama runner" 2>/dev/null || true
  sleep 1
fi

# ── 3. RAM 여유 체크 ────────────────────────────────
mem_line=$(top -l 1 | grep "PhysMem" | head -1)
unused_gb=$(echo "$mem_line" | grep -oE '[0-9]+G unused' | grep -oE '[0-9]+' || echo 0)
unused_mb=$(echo "$mem_line" | grep -oE '[0-9]+M unused' | grep -oE '[0-9]+' || echo 0)
free_mb=$(( unused_gb * 1024 + unused_mb ))

if [ "$free_mb" -lt "$MIN_FREE_MB" ]; then
  echo -e "${RED}[gemma-on] ⚠ RAM 여유 부족 (${free_mb} MB < ${MIN_FREE_MB} MB)${NC}"
  echo "  기동하면 시스템 스왑 발생 가능. 다른 앱 종료 후 재시도 권장."
  echo "  강제 기동: FORCE=1 bash .claude/hooks/gemma-on.sh"
  if [ "${FORCE:-0}" != "1" ]; then
    exit 1
  fi
  echo -e "${YELLOW}  FORCE=1 — 강제 기동${NC}"
fi

# ── 4. 모델 파일 존재 확인 ──────────────────────────
if [ ! -d "$OLLAMA_HOME/blobs" ] || [ -z "$(ls -A "$OLLAMA_HOME/blobs" 2>/dev/null)" ]; then
  echo -e "${RED}[gemma-on] ⚠ 모델 저장소 비어있음: $OLLAMA_HOME${NC}"
  echo "  설치: OLLAMA_MODELS=$OLLAMA_HOME ollama pull $MODEL"
  exit 1
fi

# ── 5. 서버 기동 ────────────────────────────────────
echo -e "${GREEN}[gemma-on] 서버 기동 중 (RAM 여유 ${free_mb} MB)...${NC}"
OLLAMA_MODELS="$OLLAMA_HOME" nohup ollama serve > /tmp/ollama.log 2>&1 &
new_pid=$!
echo "$new_pid" > "$LOCK_FILE"
sleep 3

# ── 6. 기동 검증 ────────────────────────────────────
if ! pgrep -x ollama >/dev/null; then
  echo -e "${RED}[gemma-on] 기동 실패 — /tmp/ollama.log 확인${NC}"
  tail -20 /tmp/ollama.log
  rm -f "$LOCK_FILE"
  exit 1
fi

# 모델 확인
if ! ollama list 2>/dev/null | grep -q "$MODEL"; then
  echo -e "${RED}[gemma-on] ⚠ $MODEL 미등록 — pull 필요${NC}"
  exit 1
fi

echo -e "${GREEN}  ✓ pid=$(pgrep -x ollama | head -1)  endpoint=$ENDPOINT  model=$MODEL${NC}"
echo ""
echo "다음 단계:"
echo "  gemma-warm    # 첫 호출 로딩 타임(15~30초) 감수 → 이후 30분간 즉시"
echo "  gemma-status  # 헬스체크"
echo "  gemma-off     # 종료 + RAM 회수"
