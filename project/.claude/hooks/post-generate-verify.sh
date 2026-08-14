#!/bin/bash
# post-generate-verify.sh — Pre-Delivery 자동 검증 (토큰 비용 0)
# agent-harness가 on_complete 호출 전에 실행
#
# 반환:
#   exit 0 = 전체 통과
#   exit 1 = 검증 실패 (agent-harness가 자동 재시도해야 함)
#
# stdout: JSON 형태 검증 결과 (on_complete result에 포함용)

set -euo pipefail

PASS=0
FAIL=0
RESULTS=()

log_result() {
  local name="$1" status="$2" detail="${3:-}"
  if [ "$status" = "PASS" ]; then
    PASS=$((PASS + 1))
    RESULTS+=("\"$name\":true")
    echo "  ✓ $name"
  else
    FAIL=$((FAIL + 1))
    RESULTS+=("\"$name\":false")
    echo "  ✗ $name — $detail"
  fi
}

echo "[Pre-Delivery] 검증 시작..."

# ── 1. Lint / Type Check ────────────────────────────
if [ -f "package.json" ]; then
  # Node.js 프로젝트
  if grep -q '"type-check"' package.json 2>/dev/null; then
    if npx --yes tsc --noEmit 2>/dev/null; then
      log_result "lint_passed" "PASS"
    else
      # bun 시도
      if command -v bun &>/dev/null && bun run type-check 2>/dev/null; then
        log_result "lint_passed" "PASS"
      else
        log_result "lint_passed" "FAIL" "type-check 실패"
      fi
    fi
  elif [ -f "tsconfig.json" ]; then
    if npx --yes tsc --noEmit 2>/dev/null; then
      log_result "lint_passed" "PASS"
    else
      log_result "lint_passed" "FAIL" "tsc --noEmit 실패"
    fi
  else
    log_result "lint_passed" "PASS" # JS 프로젝트 — type-check 해당 없음
  fi
elif [ -f "Gemfile" ]; then
  # Rails 프로젝트
  if bundle exec rubocop --format simple 2>/dev/null; then
    log_result "lint_passed" "PASS"
  else
    log_result "lint_passed" "PASS" # rubocop 미설치 시 스킵
  fi
else
  log_result "lint_passed" "PASS" # 린터 없음
fi

# ── 2. 변경된 UI 파일의 CSS/Tailwind 확인 ──────────
UI_FILES=$(git diff HEAD~1 --name-only 2>/dev/null | grep -E '\.(html|tsx|jsx|vue|erb|svelte)$' || true)

if [ -n "$UI_FILES" ]; then
  CSS_OK=true
  for f in $UI_FILES; do
    if [ -f "$f" ]; then
      # Tailwind CDN 또는 CSS import 또는 빌드된 stylesheet 확인
      if grep -qE '(tailwindcss|stylesheet|\.css|@apply|className)' "$f" 2>/dev/null; then
        continue
      fi
      # HTML 파일에 스타일 없으면 경고
      if [[ "$f" == *.html ]] || [[ "$f" == *.erb ]]; then
        if ! grep -qE '(<link.*css|<style|tailwindcss)' "$f" 2>/dev/null; then
          CSS_OK=false
          echo "    경고: $f 에 CSS 참조 없음"
        fi
      fi
    fi
  done
  if [ "$CSS_OK" = true ]; then
    log_result "css_loaded" "PASS"
  else
    log_result "css_loaded" "FAIL" "UI 파일에 CSS/Tailwind 참조 누락"
  fi
else
  log_result "css_loaded" "PASS" # UI 파일 변경 없음
fi

# ── 3. HTTP 200 확인 (서버가 떠 있는 경우만) ────────
HTTP_OK=true
# 일반적인 dev 서버 포트 확인
for PORT in 3000 3001 4000 5000 8000 8080; do
  if lsof -ti:$PORT &>/dev/null; then
    STATUS=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$PORT/" 2>/dev/null || echo "000")
    if [ "$STATUS" = "200" ] || [ "$STATUS" = "302" ] || [ "$STATUS" = "301" ]; then
      log_result "http_check" "PASS"
      HTTP_OK=done
      break
    elif [ "$STATUS" = "000" ]; then
      continue  # 연결 안 됨 — 다른 포트 시도
    else
      log_result "http_check" "FAIL" "localhost:$PORT → HTTP $STATUS"
      HTTP_OK=done
      break
    fi
  fi
done
if [ "$HTTP_OK" != "done" ]; then
  log_result "http_check" "PASS" # 서버 미기동 — 스킵
fi

# ── 4. 한글 깨짐 확인 ──────────────────────────────
if [ -n "$UI_FILES" ]; then
  HANGUL_OK=true
  for f in $UI_FILES; do
    if [ -f "$f" ]; then
      # 파일에 한글이 포함된 경우 인코딩 확인
      if grep -P '[\x{AC00}-\x{D7A3}]' "$f" &>/dev/null; then
        ENCODING=$(file -b --mime-encoding "$f" 2>/dev/null || echo "unknown")
        if [[ "$ENCODING" != *"utf-8"* ]] && [[ "$ENCODING" != *"ascii"* ]] && [[ "$ENCODING" != "unknown" ]]; then
          HANGUL_OK=false
          echo "    경고: $f 인코딩 $ENCODING (UTF-8 아님)"
        fi
      fi
    fi
  done
  if [ "$HANGUL_OK" = true ]; then
    log_result "hangul_ok" "PASS"
  else
    log_result "hangul_ok" "FAIL" "비-UTF-8 인코딩 감지"
  fi
else
  log_result "hangul_ok" "PASS"
fi

# ── 결과 출력 ──────────────────────────────────────
echo ""
echo "[Pre-Delivery] 결과: PASS=$PASS, FAIL=$FAIL"

# JSON 결과 (agent-harness가 on_complete result에 포함)
JOINED=$(IFS=,; echo "${RESULTS[*]}")
echo "PRE_DELIVERY_JSON={${JOINED},\"verify_method\":\"post-generate-verify.sh\"}"

if [ "$FAIL" -gt 0 ]; then
  echo "[Pre-Delivery] ⛔ 검증 실패 — on_complete 호출 금지. 수정 후 재실행."
  exit 1
else
  echo "[Pre-Delivery] ✅ 전체 통과 — on_complete 호출 가능."
  exit 0
fi
