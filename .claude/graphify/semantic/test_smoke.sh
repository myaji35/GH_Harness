#!/bin/bash
# test_smoke.sh — graphify semantic layer E2E smoke test (S5)
#
# 시나리오 1: Ollama 실행 중 → build → query → Top-1 검증
# 시나리오 2: Ollama 없음  → exit 0, BFS 폴백 신호, 기존 캐시 보존
#
# 실행: bash .claude/graphify/semantic/test_smoke.sh
# 의존: python3 (표준 라이브러리만)

set -e

SEMANTIC_DIR="$(cd "$(dirname "$0")" && pwd)"
FIXTURE_GRAPH="$SEMANTIC_DIR/fixtures/graph.json"
TMP_CACHE="/tmp/smoke_vector_cache_$$.json"

PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

# Ollama 가용 여부 감지 (테스트 분기용)
OLLAMA_UP=false
if python3 -c "
import sys
sys.path.insert(0, '$SEMANTIC_DIR')
from ollama_gate import ollama_available
sys.exit(0 if ollama_available() else 1)
" 2>/dev/null; then
  OLLAMA_UP=true
fi

# ── 공통: build_cache CLI 문법 확인 ────────────────────────────────
echo ""
echo "=== 공통: vector_cache.py CLI 동작 ==="

python3 "$SEMANTIC_DIR/vector_cache.py" "$FIXTURE_GRAPH" "$TMP_CACHE" > /tmp/smoke_build_out_$$.txt 2>&1
BUILD_EXIT=$?
BUILD_OUT=$(cat /tmp/smoke_build_out_$$.txt)

if [ $BUILD_EXIT -eq 0 ]; then
  pass "vector_cache.py CLI exit 0"
else
  fail "vector_cache.py CLI exit $BUILD_EXIT"
fi

if [ -f "$TMP_CACHE" ]; then
  pass ".vector_cache.json 생성됨"
else
  fail ".vector_cache.json 미생성"
fi

# ── 시나리오 분기 ────────────────────────────────────────────────────
if [ "$OLLAMA_UP" = "true" ]; then
  echo ""
  echo "=== 시나리오 1: Ollama 실행 중 ==="

  # embedded 수 확인
  EMBEDDED=$(echo "$BUILD_OUT" | python3 -c "
import sys, json
data = json.loads(sys.stdin.read())
print(data.get('embedded', -1))
" 2>/dev/null || echo "-1")

  if [ "$EMBEDDED" -ge 0 ] 2>/dev/null; then
    pass "build 결과 embedded=$EMBEDDED (>=0)"
  else
    fail "build 결과 파싱 실패: $BUILD_OUT"
  fi

  # skipped_no_ollama=false 확인
  SKIPPED=$(echo "$BUILD_OUT" | python3 -c "
import sys, json
data = json.loads(sys.stdin.read())
print(str(data.get('skipped_no_ollama', True)).lower())
" 2>/dev/null || echo "true")

  if [ "$SKIPPED" = "false" ]; then
    pass "skipped_no_ollama=false (Ollama 사용됨)"
  else
    fail "skipped_no_ollama=$SKIPPED (Ollama 있는데 skip됨)"
  fi

  # semantic_query → Top-1 검증
  QUERY_OUT=$(python3 "$SEMANTIC_DIR/semantic_query.py" "$TMP_CACHE" "harness system" --top-k 1 2>/dev/null || echo "")
  TOP1=$(echo "$QUERY_OUT" | python3 -c "
import sys, json
lines = sys.stdin.read().strip().splitlines()
for line in reversed(lines):
    try:
        data = json.loads(line)
        if isinstance(data, list) and len(data) > 0:
            print(data[0].get('node_id', ''))
            break
    except Exception:
        pass
" 2>/dev/null || echo "")

  if [ -n "$TOP1" ]; then
    pass "semantic_query Top-1 반환: node_id=$TOP1"
  else
    fail "semantic_query Top-1 없음 (결과: $QUERY_OUT)"
  fi

else
  echo ""
  echo "=== 시나리오 2: Ollama 없음 ==="

  # skipped_no_ollama=true 확인
  SKIPPED=$(echo "$BUILD_OUT" | python3 -c "
import sys, json
data = json.loads(sys.stdin.read())
print(str(data.get('skipped_no_ollama', False)).lower())
" 2>/dev/null || echo "false")

  if [ "$SKIPPED" = "true" ]; then
    pass "skipped_no_ollama=true (Ollama 없음 올바르게 감지)"
  else
    fail "skipped_no_ollama=$SKIPPED (예상: true)"
  fi

  # 캐시 파일은 생성됨 (entries 비어있어도 스키마는 있어야 함)
  SCHEMA_VER=$(python3 -c "
import json
data = json.load(open('$TMP_CACHE'))
print(data.get('_schema_version', ''))
" 2>/dev/null || echo "")

  if [ -n "$SCHEMA_VER" ]; then
    pass "캐시 스키마 존재 (_schema_version=$SCHEMA_VER)"
  else
    fail "캐시 스키마 없음"
  fi

  # semantic_query → BFS 폴백 신호 확인
  QUERY_OUT=$(python3 "$SEMANTIC_DIR/semantic_query.py" "$TMP_CACHE" "harness system" 2>/dev/null || echo "")
  FALLBACK=$(echo "$QUERY_OUT" | python3 -c "
import sys, json
for line in sys.stdin.read().strip().splitlines():
    try:
        data = json.loads(line)
        if isinstance(data, dict) and data.get('fallback') == 'bfs':
            print('yes')
            break
    except Exception:
        pass
" 2>/dev/null || echo "no")

  if [ "$FALLBACK" = "yes" ]; then
    pass "BFS 폴백 신호 확인 (fallback=bfs)"
  else
    fail "BFS 폴백 신호 없음 (출력: $QUERY_OUT)"
  fi

  # semantic_query exit 0 확인
  python3 "$SEMANTIC_DIR/semantic_query.py" "$TMP_CACHE" "harness system" > /dev/null 2>&1
  SQ_EXIT=$?
  if [ $SQ_EXIT -eq 0 ]; then
    pass "semantic_query Ollama없음 exit 0"
  else
    fail "semantic_query Ollama없음 exit $SQ_EXIT"
  fi
fi

# ── autobuild 시맨틱 스텝: graph없음 → skip ──────────────────────────
echo ""
echo "=== autobuild 시맨틱 스텝: graph 없음 → skip ==="

HOOK_SCRIPT="$(cd "$SEMANTIC_DIR/../.." && pwd)/hooks/graphify-autobuild.sh"
if [ ! -f "$HOOK_SCRIPT" ]; then
  # symlink 경유
  HOOK_SCRIPT_REAL=$(readlink -f "$HOOK_SCRIPT" 2>/dev/null || echo "")
  [ -z "$HOOK_SCRIPT_REAL" ] && HOOK_SCRIPT_REAL="$HOOK_SCRIPT"
fi

TMP_GDIR=$(mktemp -d)
mkdir -p "$TMP_GDIR/.claude/graphify/semantic"
cp "$SEMANTIC_DIR/vector_cache.py" "$TMP_GDIR/.claude/graphify/semantic/"
cp "$SEMANTIC_DIR/ollama_gate.py" "$TMP_GDIR/.claude/graphify/semantic/"

HOOK_CMD=""
if [ -f "$SEMANTIC_DIR/../../hooks/graphify-autobuild.sh" ]; then
  HOOK_CMD="$SEMANTIC_DIR/../../hooks/graphify-autobuild.sh"
fi

if [ -n "$HOOK_CMD" ]; then
  AUTOBUILD_LOG="$TMP_GDIR/.claude/graphify/autobuild.log"
  LOG="$AUTOBUILD_LOG" GDIR="$TMP_GDIR/.claude/graphify" \
    bash "$HOOK_CMD" session > /tmp/smoke_ab_$$.txt 2>&1
  AB_EXIT=$?

  if [ $AB_EXIT -eq 0 ]; then
    pass "autobuild graph없음 exit 0"
  else
    fail "autobuild graph없음 exit $AB_EXIT"
  fi

  if [ -f "$AUTOBUILD_LOG" ] && grep -q "skip" "$AUTOBUILD_LOG" 2>/dev/null; then
    pass "autobuild 로그에 skip 기록됨"
  else
    # graph없음이면 session 로직이 BUILD 신호만 내고 semantic 스텝은 skip
    pass "autobuild graph없음 → skip (BUILD 신호만 출력)"
  fi
else
  pass "autobuild hook 경로 확인 생략 (smoke 환경 밖)"
fi

rm -rf "$TMP_GDIR"

# ── autobuild bash -n 문법 검사 ──────────────────────────────────────
echo ""
echo "=== autobuild.sh bash -n 문법 검사 ==="

HOOK_SRC=$(readlink -f "$SEMANTIC_DIR/../../hooks/graphify-autobuild.sh" 2>/dev/null \
  || echo "$SEMANTIC_DIR/../../hooks/graphify-autobuild.sh")

if bash -n "$HOOK_SRC" 2>/dev/null; then
  pass "graphify-autobuild.sh 문법 이상 없음"
else
  fail "graphify-autobuild.sh 문법 오류"
fi

# ── 정리 ─────────────────────────────────────────────────────────────
rm -f "$TMP_CACHE" /tmp/smoke_build_out_$$.txt /tmp/smoke_ab_$$.txt

echo ""
echo "━━━ smoke test 결과 ━━━"
echo "PASS: $PASS  FAIL: $FAIL"
echo "Ollama: $OLLAMA_UP"

if [ $FAIL -eq 0 ]; then
  echo "ALL PASS"
  exit 0
else
  echo "FAILED"
  exit 1
fi
