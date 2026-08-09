#!/usr/bin/env bash
# run-server: 프로젝트 디렉토리명 앞 4자리 숫자를 3000번대 포트로 매핑해 백엔드를 실행한다.
#   규칙: 포트 = 3000 + (앞4자리 % 1000)   예) 0029_XimTier_ENG → 3029, 0050_… → 3050
# 검증환경 자동보정: 스크래치패드 venv 재사용/생성, 누락 의존성(pytz 등) 보정, 포트 충돌 시 기존 종료, 200 헬스체크.
#
# 사용: bash serve.sh [PROJECT_DIR]
#   PROJECT_DIR 생략 시 현재 작업 디렉토리 기준.
set -uo pipefail

PROJECT_DIR="${1:-$PWD}"
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
BASENAME="$(basename "$PROJECT_DIR")"

# ── 1. 포트 산출: 디렉토리명 앞 4자리 숫자 → 3000번대 ──────────────────────
NUM4="$(printf '%s' "$BASENAME" | grep -oE '^[0-9]{4}' | head -1)"
if [ -z "$NUM4" ]; then
  echo "[run-server] ERROR: 디렉토리명 '$BASENAME' 앞에 4자리 숫자가 없습니다. 포트 산출 불가." >&2
  echo "[run-server] 앞 4자리 숫자로 시작하는 프로젝트 디렉토리에서 실행하세요 (예: 0029_XimTier_ENG)." >&2
  exit 2
fi
PORT=$(( 3000 + (10#$NUM4 % 1000) ))
echo "[run-server] 프로젝트: $BASENAME  →  앞4자리 $NUM4  →  포트 $PORT"

# ── 2. 앱(app.py)이 있는 서브디렉토리 탐색 ──────────────────────────────────
APP_DIR=""
if [ -f "$PROJECT_DIR/app.py" ]; then
  APP_DIR="$PROJECT_DIR"
else
  # 한 단계 아래에서 app.py 탐색 (XimTierV06191535P01 같은 하위 프로젝트)
  CAND="$(find "$PROJECT_DIR" -maxdepth 2 -name app.py -not -path '*/.*' -not -path '*/__pycache__/*' 2>/dev/null | head -1)"
  [ -n "$CAND" ] && APP_DIR="$(dirname "$CAND")"
fi
if [ -z "$APP_DIR" ]; then
  echo "[run-server] ERROR: app.py 를 찾지 못했습니다 ($PROJECT_DIR 하위)." >&2
  exit 3
fi
echo "[run-server] 앱 디렉토리: $APP_DIR"

# ── 3. 스크래치패드 venv (외장 SSD AppleDouble 문제 회피 → 로컬 디스크) ──────
#   CLAUDE_SCRATCHPAD 가 있으면 사용, 없으면 프로젝트 로컬 .venv 폴백.
SCRATCH="${CLAUDE_SCRATCHPAD:-}"
if [ -n "$SCRATCH" ]; then
  VENV="$SCRATCH/serve_venv_${NUM4}"
else
  VENV="$APP_DIR/.venv"
fi

# uv 우선, 없으면 python -m venv
have_uv=0; command -v uv >/dev/null 2>&1 && have_uv=1

if [ ! -x "$VENV/bin/python" ]; then
  echo "[run-server] venv 생성: $VENV"
  if [ "$have_uv" = 1 ]; then
    UV_LINK_MODE=copy uv venv "$VENV" --python 3.12 >/dev/null 2>&1
    if [ -f "$APP_DIR/pyproject.toml" ]; then
      echo "[run-server] 의존성 설치 (uv, pyproject.toml)…"
      UV_LINK_MODE=copy VIRTUAL_ENV="$VENV" uv pip install -r "$APP_DIR/pyproject.toml" 2>&1 | tail -3
    fi
  else
    python3 -m venv "$VENV"
    [ -f "$APP_DIR/pyproject.toml" ] && "$VENV/bin/pip" install -q -r "$APP_DIR/pyproject.toml" 2>&1 | tail -3
  fi
fi
PYBIN="$VENV/bin/python"

# ── 4. 누락 의존성 자동 보정 (streamlit import 시 ModuleNotFound 잡아 설치) ──
ensure_mod() {
  local mod="$1"
  "$PYBIN" -c "import $mod" >/dev/null 2>&1 && return 0
  echo "[run-server] 누락 모듈 보정: $mod"
  if [ "$have_uv" = 1 ]; then UV_LINK_MODE=copy VIRTUAL_ENV="$VENV" uv pip install "$mod" >/dev/null 2>&1
  else "$VENV/bin/pip" install -q "$mod" >/dev/null 2>&1; fi
}
# 알려진 상습 누락(pyproject에 빠지는 것). 필요 시 여기에 추가.
for m in streamlit pytz; do ensure_mod "$m"; done

# ── 5. 포트 충돌: 기존 프로세스 종료 후 재실행 ──────────────────────────────
if lsof -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "[run-server] 포트 $PORT 사용 중 → 기존 프로세스 종료"
  pkill -f "streamlit run .*app.py.*--server.port $PORT" 2>/dev/null
  # streamlit 특정 패턴이 안 잡히면 포트 점유 PID 직접 종료
  lsof -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null | xargs -r kill 2>/dev/null
  sleep 1.5
fi

# ── 6. 실행 (백그라운드) + 200 헬스체크 ─────────────────────────────────────
LOG="${SCRATCH:-/tmp}/serve_${NUM4}.log"
echo "[run-server] 실행: streamlit run app.py --server.port $PORT"
export OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1
( cd "$APP_DIR" && nohup "$VENV/bin/streamlit" run app.py \
    --server.port "$PORT" --server.address 127.0.0.1 \
    --server.headless true --browser.gatherUsageStats false \
    > "$LOG" 2>&1 & echo $! > "${SCRATCH:-/tmp}/serve_${NUM4}.pid" )

# 헬스체크: 200 또는 에러 감지까지 최대 90초
for i in $(seq 1 180); do
  if curl -s -o /dev/null "http://127.0.0.1:$PORT/" 2>/dev/null; then
    echo "[run-server] ✅ READY → http://127.0.0.1:$PORT/  (로그: $LOG)"
    exit 0
  fi
  if grep -qiE "Traceback|ModuleNotFoundError|Error:" "$LOG" 2>/dev/null; then
    echo "[run-server] ⚠️ 부팅 중 에러 감지:" >&2
    tail -15 "$LOG" >&2
    exit 4
  fi
  sleep 0.5
done
echo "[run-server] ⚠️ 90초 내 200 응답 없음. 로그 확인: $LOG" >&2
tail -15 "$LOG" >&2
exit 5
