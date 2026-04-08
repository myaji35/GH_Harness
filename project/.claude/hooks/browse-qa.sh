#!/bin/bash
# browse-qa.sh — gstack browse CLI 기반 브라우저 QA hook
#
# 사용법: bash browse-qa.sh <ISSUE_ID> [URL]
# 출력: BROWSER_QA result JSON (on_complete.sh가 받음)
#
# 동작:
#   1. URL 결정: 인자 → .harness.env DEV_URL → 기본값
#   2. gstack browse navigate
#   3. console --errors 캡처
#   4. network 에러 캡처
#   5. screenshot 저장
#   6. on_complete.sh BROWSER_QA 호출

set -e

ISSUE_ID="${1:-UNKNOWN}"
URL="${2:-}"

# gstack browse 바이너리 위치 (글로벌 설치)
BROWSE_BIN="$HOME/.claude/skills/gstack/browse/dist/browse"

if [ ! -x "$BROWSE_BIN" ]; then
  echo "[browse-qa] gstack browse 미설치 → 스킵"
  bash "$(dirname "$0")/on_complete.sh" "$ISSUE_ID" "BROWSER_QA" \
    '{"skipped":true,"reason":"gstack_not_installed","console_errors":[],"network_errors":[]}'
  exit 0
fi

# .harness.env 로드 (DEV_URL 등)
if [ -f ".harness.env" ]; then
  set -a; source ".harness.env"; set +a
fi

URL="${URL:-${DEV_URL:-http://localhost:3000}}"

ARTIFACT_DIR=".claude/issue-db/$ISSUE_ID"
mkdir -p "$ARTIFACT_DIR"

echo "[browse-qa] $ISSUE_ID → $URL"

# 1. Navigate (실패해도 진행 — 결과에 기록)
NAVIGATE_OK=true
"$BROWSE_BIN" goto "$URL" >/dev/null 2>&1 || NAVIGATE_OK=false

if [ "$NAVIGATE_OK" = false ]; then
  echo "[browse-qa] navigate 실패: $URL"
  bash "$(dirname "$0")/on_complete.sh" "$ISSUE_ID" "BROWSER_QA" \
    "{\"navigate_failed\":true,\"url\":\"$URL\",\"console_errors\":[{\"type\":\"navigate\",\"message\":\"unreachable: $URL\"}],\"network_errors\":[]}"
  exit 0
fi

# 2. 페이지 안정 대기
"$BROWSE_BIN" wait --networkidle 2>/dev/null || true

# 3. Console errors
CONSOLE_ERR=$("$BROWSE_BIN" console --errors 2>/dev/null || echo "")
# 4. Network errors
NET_ERR=$("$BROWSE_BIN" network 2>/dev/null | grep -E "^[45][0-9][0-9]" || echo "")
# 5. Screenshot
"$BROWSE_BIN" screenshot "$ARTIFACT_DIR/after.png" 2>/dev/null || true

# 결과 JSON 생성 (Python으로 안전하게)
python3 << PYEOF
import json, os

console_lines = """$CONSOLE_ERR""".strip().split("\n") if """$CONSOLE_ERR""".strip() else []
net_lines = """$NET_ERR""".strip().split("\n") if """$NET_ERR""".strip() else []

result = {
    "url": "$URL",
    "console_errors": [{"message": l} for l in console_lines if l],
    "network_errors": [{"line": l} for l in net_lines if l],
    "screenshot": "$ARTIFACT_DIR/after.png",
    "navigate_ok": True
}

with open("$ARTIFACT_DIR/browser-qa-result.json", "w") as f:
    json.dump(result, f, ensure_ascii=False, indent=2)

print(json.dumps(result, ensure_ascii=False))
PYEOF

# on_complete 호출
RESULT_JSON=$(cat "$ARTIFACT_DIR/browser-qa-result.json")
bash "$(dirname "$0")/on_complete.sh" "$ISSUE_ID" "BROWSER_QA" "$RESULT_JSON"
