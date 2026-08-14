#!/bin/bash
# moa-route.sh — Mixture of Agents 합의 라우터 (Agent OS ①)
#
# 하나의 프롬프트를 여러 참조 모델에 병렬 전달한 뒤, aggregator(Opus)가
# 응답들을 하나로 종합한다. 영상2(Alex Finn)의 /moa 재현.
#
# 사용법:
#   moa-route.sh "<프롬프트>" [refs]
#     refs: 참조 모델 콤마목록. 생략 시 자동 탐지(무료/로컬 1순위).
#
# 모델 선택 룰 (대표님 전역 룰 준수):
#   - 무료/로컬 후보(codex, ollama 등)를 1순위 참조 모델로 사용
#   - 유료 API는 refs 인자로 명시할 때만
#
# exit 0 = 정상, 1 = 사용법 오류, 2 = 참조 모델 0개(단독 폴백도 불가)

# set -e 미사용: 참조 모델 개별 실패(codex/ollama 시그널 등)는 의도적으로 격리한다.
set -uo pipefail

HARNESS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
REGISTRY="$HARNESS_ROOT/.claude/issue-db/registry.json"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

PROMPT="${1:-}"
REFS="${2:-}"

if [ -z "$PROMPT" ]; then
  echo "[moa] 사용법: moa-route.sh \"<프롬프트>\" [참조모델,콤마목록]" >&2
  echo "[moa] 예: moa-route.sh \"이번 주 할 SaaS 아이디어 5개\"" >&2
  exit 1
fi

# --- 참조 모델 자동 탐지 (무료/로컬 1순위) -----------------------------
detect_refs() {
  local found=()
  # 1순위: codex CLI (무료 second-opinion)
  if command -v codex >/dev/null 2>&1; then found+=("codex"); fi
  # 1순위: 로컬 ollama
  if command -v ollama >/dev/null 2>&1; then found+=("ollama"); fi
  # 항상 가능한 aggregator 계열: claude non-interactive (참조 샘플용)
  if command -v claude >/dev/null 2>&1; then found+=("claude"); fi
  ( IFS=,; echo "${found[*]}" )
}

if [ -z "$REFS" ]; then
  REFS="$(detect_refs)"
fi

if [ -z "$REFS" ]; then
  echo "[moa] 참조 모델을 찾을 수 없습니다 (codex/ollama/claude 미설치)." >&2
  echo "[moa] 하나라도 설치하거나 refs 인자로 모델을 지정하세요." >&2
  exit 2
fi

echo "[moa] 참조 모델: $REFS" >&2

# --- 각 참조 모델에 병렬 질의 ------------------------------------------
query_ref() {
  local ref="$1" out="$2"
  case "$ref" in
    codex)
      # codex를 second-opinion 모드로 (있으면). 실패/시그널 시 빈 출력.
      ( codex exec "$PROMPT" 2>/dev/null ) >"$out" || : >"$out"
      ;;
    ollama)
      # 첫 로컬 모델로 질의. 없으면 빈 출력.
      local m; m="$(ollama list 2>/dev/null | awk 'NR==2{print $1}')"
      [ -n "$m" ] && ollama run "$m" "$PROMPT" >"$out" 2>/dev/null || echo "" >"$out"
      ;;
    claude)
      claude -p "$PROMPT" >"$out" 2>/dev/null || echo "" >"$out"
      ;;
    *)
      echo "" >"$out"
      ;;
  esac
}

i=0
pids=()
IFS=',' read -ra REF_ARR <<< "$REFS"
for ref in "${REF_ARR[@]}"; do
  ref="$(echo "$ref" | tr -d ' ')"
  [ -z "$ref" ] && continue
  query_ref "$ref" "$WORKDIR/ref-$i.txt" &
  pids+=($!)
  echo "$ref" > "$WORKDIR/name-$i.txt"
  i=$((i+1))
done
for p in "${pids[@]}"; do wait "$p" || true; done

# --- 응답 취합 ---------------------------------------------------------
COMBINED="$WORKDIR/combined.txt"
: > "$COMBINED"
valid=0
for n in $(seq 0 $((i-1))); do
  name="$(cat "$WORKDIR/name-$n.txt")"
  body="$(cat "$WORKDIR/ref-$n.txt" 2>/dev/null || true)"
  if [ -n "$(echo "$body" | tr -d '[:space:]')" ]; then
    printf '### [참조 모델: %s]\n%s\n\n' "$name" "$body" >> "$COMBINED"
    valid=$((valid+1))
  fi
done

if [ "$valid" -eq 0 ]; then
  echo "[moa] 모든 참조 모델이 빈 응답을 반환했습니다." >&2
  exit 2
fi

# --- Aggregator 합의 (Opus 우선) --------------------------------------
AGG_PROMPT="다음은 동일한 질문에 대한 여러 AI 모델의 답변입니다. 이것들을 비판적으로 검토하여 가장 정확하고 유용한 하나의 답변으로 종합하세요. 상충하는 부분은 근거로 판단하고, 중복은 제거하세요. 한국어로 답하세요.

[원 질문]
$PROMPT

[모델 답변들]
$(cat "$COMBINED")"

SYNTH=""
if command -v claude >/dev/null 2>&1; then
  SYNTH="$(claude -p "$AGG_PROMPT" 2>/dev/null || true)"
fi
# claude 없거나 실패 시: 참조 응답을 그대로 병렬 제시 (종합 실패 안내)
if [ -z "$(echo "$SYNTH" | tr -d '[:space:]')" ]; then
  echo "[moa] aggregator(claude) 미가용 — 참조 응답을 그대로 출력합니다." >&2
  SYNTH="$(cat "$COMBINED")"
fi

echo "$SYNTH"

# --- registry에 MOA_RUN 기록 (원자적) --------------------------------
if [ -f "$REGISTRY" ] && command -v python3 >/dev/null 2>&1; then
  python3 - "$REGISTRY" "$PROMPT" "$REFS" "$valid" <<'PY' 2>/dev/null || true
import json, sys, datetime, tempfile, os, shutil
reg, prompt, refs, valid = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
with open(reg, encoding="utf-8") as f:
    data = json.load(f)
data.setdefault("moa_runs", []).append({
    "ts": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "prompt": prompt[:200],
    "refs": refs,
    "valid_responses": valid,
})
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(reg))
with os.fdopen(fd, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
shutil.move(tmp, reg)
PY
fi
