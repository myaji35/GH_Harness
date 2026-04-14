#!/bin/bash
# gemma-health.sh — Gemma 4 E4B 헬스체크 + 좀비 정리
# 사용: bash .claude/hooks/gemma-health.sh [--auto-clean]
# 출력: 사람이 읽을 수 있는 리포트 + 종료코드
#   0 = 정상 또는 의도적 OFF
#   1 = 이상 (좀비 프로세스 / RAM 위험 / 모델 누락)
#
# M2 16GB RAM 환경 기준 임계값:
#   - RAM 여유 < 3GB + ollama ON = WARN (곧 스왑 시작)
#   - RAM 여유 < 1GB + ollama ON = CRITICAL (강제 종료 권장)
#   - ollama 프로세스 2개 이상 = 좀비

set -uo pipefail

OLLAMA_HOME="/Volumes/E_SSD/ollama-models"
MODEL="gemma4:e4b"
ENDPOINT="http://localhost:11434"
AUTO_CLEAN=false
[ "${1:-}" = "--auto-clean" ] && AUTO_CLEAN=true

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'

# ── 1. ollama 프로세스 스캔 ──────────────────────────
pids=($(pgrep -x ollama 2>/dev/null || true))
runner_pids=($(pgrep -f "ollama runner" 2>/dev/null || true))
total=${#pids[@]}
runners=${#runner_pids[@]}

echo -e "${BLUE}━━━ Gemma 4 Health Check ━━━${NC}"
echo ""

# ── 2. 프로세스 상태 ─────────────────────────────────
if [ "$total" -eq 0 ]; then
  echo -e "프로세스: ${GREEN}OFF (정상)${NC}"
elif [ "$total" -eq 1 ] && [ "$runners" -le 1 ]; then
  echo -e "프로세스: ${GREEN}ON (정상, pid=${pids[0]})${NC}"
else
  echo -e "프로세스: ${RED}⚠ 좀비 의심 (serve=${total}, runner=${runners})${NC}"
  for p in "${pids[@]}" "${runner_pids[@]}"; do
    ps -p "$p" -o pid=,etime=,%mem=,rss=,command= 2>/dev/null | head -c 200
    echo ""
  done
  if [ "$AUTO_CLEAN" = true ]; then
    echo -e "${YELLOW}→ --auto-clean: SIGTERM → SIGKILL 순차 정리${NC}"
    pkill -TERM ollama 2>/dev/null || true
    sleep 2
    pkill -9 ollama 2>/dev/null || true
    echo -e "${GREEN}  정리 완료${NC}"
  else
    echo -e "${YELLOW}→ bash .claude/hooks/gemma-health.sh --auto-clean 으로 정리${NC}"
  fi
fi

# ── 3. 메모리 상태 ───────────────────────────────────
mem_info=$(top -l 1 | grep "PhysMem" | head -1)
unused_mb=$(echo "$mem_info" | grep -oE '[0-9]+M unused' | grep -oE '[0-9]+')
unused_gb=$(echo "$mem_info" | grep -oE '[0-9]+G unused' | grep -oE '[0-9]+')
[ -n "$unused_gb" ] && free_mb=$((unused_gb * 1024)) || free_mb="${unused_mb:-0}"
load_1m=$(uptime | awk -F'load averages:' '{print $2}' | awk '{print $1}' | tr -d ',')

echo ""
echo "RAM 여유:   ${free_mb} MB"
echo "Load 1m:    ${load_1m}"

# ── 4. RAM 임계 경보 ────────────────────────────────
if [ "$total" -gt 0 ]; then
  if [ "${free_mb:-0}" -lt 1024 ]; then
    echo -e "            ${RED}⚠ CRITICAL — ollama 종료 권장 (gemma-off)${NC}"
  elif [ "${free_mb:-0}" -lt 3072 ]; then
    echo -e "            ${YELLOW}⚠ 여유 부족 — 곧 스왑 발생 가능${NC}"
  else
    echo -e "            ${GREEN}✓ 정상${NC}"
  fi
fi

# ── 5. 모델 / API 상태 ───────────────────────────────
if [ "$total" -gt 0 ]; then
  if curl -s --max-time 2 "$ENDPOINT/api/tags" | grep -q "$MODEL" 2>/dev/null; then
    echo -e "모델 API:   ${GREEN}✓ $MODEL 응답 정상${NC}"
  else
    echo -e "모델 API:   ${RED}⚠ 응답 없음 또는 $MODEL 미등록${NC}"
  fi

  # 로드된 모델 목록 (현재 RAM 상주)
  loaded=$(curl -s --max-time 2 "$ENDPOINT/api/ps" 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); [print(m['name'], int(m.get('size',0)/1024/1024), 'MB') for m in d.get('models',[])]" 2>/dev/null)
  if [ -n "$loaded" ]; then
    echo "RAM 상주:   $loaded"
  else
    echo "RAM 상주:   (없음 — 첫 호출 시 로드됨)"
  fi
fi

# ── 6. 모델 파일 존재 ────────────────────────────────
if [ -d "$OLLAMA_HOME/blobs" ]; then
  blob_size=$(du -sh "$OLLAMA_HOME" 2>/dev/null | awk '{print $1}')
  echo "저장소:     $OLLAMA_HOME ($blob_size)"
else
  echo -e "저장소:     ${RED}⚠ $OLLAMA_HOME 없음${NC}"
fi

# ── 7. 종합 판정 ────────────────────────────────────
echo ""
if [ "$total" -eq 0 ]; then
  echo -e "${GREEN}[OK] 의도적 OFF 상태 — 필요 시 gemma-on${NC}"
  exit 0
elif [ "$total" -gt 2 ] || { [ "$total" -gt 0 ] && [ "${free_mb:-0}" -lt 1024 ]; }; then
  echo -e "${RED}[CRITICAL] 즉시 조치 필요${NC}"
  exit 1
else
  echo -e "${GREEN}[OK] 정상 작동${NC}"
  exit 0
fi
