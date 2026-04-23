#!/usr/bin/env bash
# ============================================================
# race-dispatch.sh — RACE_MODE 이슈를 받아 provider별 worktree에서 병렬 구현
#
# 사용법:
#   bash race-dispatch.sh <ISSUE_ID>
#   (registry.json의 issues[].payload를 읽어 실행)
#
# 선행조건:
#   - w.sh 가 PATH에 있거나 $HARNESS_BIN/w.sh 존재
#   - 현재 디렉토리가 프로젝트 루트 (.git 포함)
#   - registry.json에 ISSUE_ID가 존재하고 type=RACE_MODE
#
# 산출물:
#   - race-artifacts/<ISSUE_ID>/<provider>/
#     ├── stdout.log
#     ├── stderr.log
#     ├── exit_code
#     ├── duration_sec
#     └── diff.patch (base 대비 변경)
# ============================================================

# 일부 payload 필드가 없어 빈 배열이 될 수 있으므로 set -u 사용 금지

ISSUE_ID="${1:-}"
REGISTRY="${REGISTRY:-.claude/issue-db/registry.json}"
ARTIFACT_ROOT="${ARTIFACT_ROOT:-.claude/race-artifacts}"
HARNESS_BIN="${HARNESS_BIN:-/Volumes/E_SSD/02_GitHub.nosync/GH_Harness/bin}"
W_CMD="${W_CMD:-$HARNESS_BIN/w.sh}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

die() { echo -e "${RED}✖ $*${NC}" >&2; exit 1; }
info() { echo -e "${BLUE}ℹ $*${NC}"; }
ok() { echo -e "${GREEN}✓ $*${NC}"; }
warn() { echo -e "${YELLOW}! $*${NC}"; }

[ -z "$ISSUE_ID" ] && die "usage: race-dispatch.sh <ISSUE_ID>"
[ -f "$REGISTRY" ] || die "registry.json 없음: $REGISTRY"
[ -f "$W_CMD" ] || die "w.sh 없음: $W_CMD"

# payload 추출
PAYLOAD="$(python3 - "$REGISTRY" "$ISSUE_ID" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
for iss in d.get("issues", []):
    if iss.get("id") == sys.argv[2]:
        if iss.get("type") != "RACE_MODE":
            print(f"ERR:type is {iss.get('type')}, not RACE_MODE", file=sys.stderr)
            sys.exit(2)
        print(json.dumps(iss.get("payload", {})))
        sys.exit(0)
print("ERR:issue not found", file=sys.stderr)
sys.exit(3)
PYEOF
)" || die "payload 추출 실패"

[ -z "$PAYLOAD" ] && die "빈 payload"

# jq 없이도 동작하게 python 사용
extract_field() {
  python3 - "$PAYLOAD" "$1" <<'PYEOF'
import json, sys
d = json.loads(sys.argv[1])
v = d.get(sys.argv[2])
if isinstance(v, list):
    print("\n".join(str(x) for x in v))
elif v is not None:
    print(v)
PYEOF
}

TASK_BRIEF="$(extract_field task_brief)"
TIMEOUT_SEC="$(extract_field timeout_sec)"
TIMEOUT_SEC="${TIMEOUT_SEC:-900}"
BASE_BRANCH="$(extract_field base_branch)"
BASE_BRANCH="${BASE_BRANCH:-main}"

# providers 배열 (bash 3.2 호환)
PROVIDERS=()
while IFS= read -r _line; do
  [ -n "$_line" ] && PROVIDERS+=("$_line")
done < <(extract_field providers)
if [ "${#PROVIDERS[@]}" -eq 0 ]; then
  PROVIDERS=("claude" "codex")
  warn "providers 미지정 → 기본 [claude, codex]"
fi

# target_files (bash 3.2 호환)
TARGET_FILES=()
while IFS= read -r _line; do
  [ -n "$_line" ] && TARGET_FILES+=("$_line")
done < <(extract_field target_files)

[ -z "$TASK_BRIEF" ] && die "task_brief 비어 있음"

# 프로젝트 이름 추정 (현재 dir의 basename)
PROJECT_NAME="$(basename "$(pwd)")"
PROJECT_ROOT="$(pwd)"

ART_DIR="$ARTIFACT_ROOT/$ISSUE_ID"
mkdir -p "$ART_DIR"
echo "$PAYLOAD" > "$ART_DIR/payload.json"

info "RACE_MODE 시작: $ISSUE_ID"
info "  provides=${PROVIDERS[*]}"
info "  timeout=${TIMEOUT_SEC}s base=$BASE_BRANCH"

# 각 provider를 위한 프롬프트 생성
PROMPT_FILE="$ART_DIR/prompt.txt"
{
  echo "# Task (from harness RACE_MODE $ISSUE_ID)"
  echo
  echo "$TASK_BRIEF"
  echo
  if [ "${#TARGET_FILES[@]}" -gt 0 ] && [ -n "${TARGET_FILES[0]}" ]; then
    echo "## Target files (이 파일들만 편집)"
    for f in "${TARGET_FILES[@]}"; do
      echo "- $f"
    done
    echo
  fi
  echo "## 제약"
  echo "- git push 금지 (판정 전 업스트림 반영 차단)"
  echo "- 작업 완료 후 바로 종료"
  echo "- 새 의존성 추가는 가능한 피할 것"
} > "$PROMPT_FILE"

# provider별 실행 커맨드
provider_cmd() {
  local prov="$1"
  local prompt_file="$2"
  case "$prov" in
    claude)
      echo "claude --print --dangerously-skip-permissions < $prompt_file"
      ;;
    codex)
      echo "codex exec --sandbox workspace-write - < $prompt_file"
      ;;
    gemini)
      echo "gemini --yolo - < $prompt_file"
      ;;
    ollama)
      echo "ollama run ${OLLAMA_MODEL:-qwen2.5-coder} < $prompt_file"
      ;;
    *)
      # 알 수 없는 provider: 실행 파일이면 stdin으로 prompt 주입 (mock/커스텀 지원)
      if command -v "$prov" >/dev/null 2>&1; then
        echo "$prov < $prompt_file"
      else
        echo "echo 'unsupported provider: $prov' >&2; exit 99"
      fi
      ;;
  esac
}

# 백그라운드 실행
PIDS=()
for prov in "${PROVIDERS[@]}"; do
  # CLI 존재 여부 체크
  if ! command -v "$prov" >/dev/null 2>&1; then
    warn "provider '$prov' CLI 없음 → skip"
    continue
  fi

  feat_name="race-${ISSUE_ID}-${prov}"
  prov_art="$ART_DIR/$prov"
  mkdir -p "$prov_art"

  # worktree 생성
  info "[$prov] worktree 생성"
  _WT_HOME="${WORKTREE_HOME:-$HOME/projects/worktrees}"
  _BATCH_BASE="${BATCH_BASE:-$(dirname "$PROJECT_ROOT")}"
  BATCH_BASE="$_BATCH_BASE" WORKTREE_HOME="$_WT_HOME" \
    bash "$W_CMD" "$PROJECT_NAME" "$feat_name" -- echo "worktree ready" \
    > "$prov_art/worktree-setup.log" 2>&1 || {
      warn "[$prov] worktree 생성 실패 → skip"
      continue
    }

  wt_path="$_WT_HOME/${PROJECT_NAME}__${feat_name}"
  [ -d "$wt_path" ] || {
    warn "[$prov] worktree 경로 확인 실패: $wt_path → skip"
    continue
  }

  CMD="$(provider_cmd "$prov" "$(pwd)/$PROMPT_FILE")"

  info "[$prov] 실행 시작 (timeout=${TIMEOUT_SEC}s)"
  (
    cd "$wt_path" || exit 98
    START_T=$(date +%s)
    # macOS는 gtimeout 또는 perl로 대체
    if command -v timeout >/dev/null 2>&1; then
      TO="timeout ${TIMEOUT_SEC}"
    elif command -v gtimeout >/dev/null 2>&1; then
      TO="gtimeout ${TIMEOUT_SEC}"
    else
      TO="perl -e 'alarm shift; exec @ARGV' ${TIMEOUT_SEC}"
    fi
    eval "$TO bash -c \"$CMD\"" \
      > "$PROJECT_ROOT/$prov_art/stdout.log" \
      2> "$PROJECT_ROOT/$prov_art/stderr.log"
    EC=$?
    END_T=$(date +%s)
    echo "$EC" > "$PROJECT_ROOT/$prov_art/exit_code"
    echo "$((END_T - START_T))" > "$PROJECT_ROOT/$prov_art/duration_sec"
    # diff 수집
    git diff "$BASE_BRANCH" > "$PROJECT_ROOT/$prov_art/diff.patch" 2>/dev/null || true
    git diff --stat "$BASE_BRANCH" > "$PROJECT_ROOT/$prov_art/diff.stat" 2>/dev/null || true
    ls -1 "$wt_path" > "$PROJECT_ROOT/$prov_art/files.txt" 2>/dev/null || true
  ) &
  PIDS+=($!)
done

if [ "${#PIDS[@]}" -eq 0 ]; then
  die "실행 가능한 provider가 0개"
fi

info "병렬 실행 중 (${#PIDS[@]}개 provider)… 대기"

# 모든 provider 완료 대기 (추가 안전 버퍼 +60초)
WAIT_MAX=$((TIMEOUT_SEC + 60))
ELAPSED=0
STEP=5
while [ "$ELAPSED" -lt "$WAIT_MAX" ]; do
  RUNNING=0
  for pid in "${PIDS[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
      RUNNING=$((RUNNING+1))
    fi
  done
  [ "$RUNNING" -eq 0 ] && break
  sleep "$STEP"
  ELAPSED=$((ELAPSED+STEP))
done

# 잔여 프로세스 강제 종료
for pid in "${PIDS[@]}"; do
  kill -0 "$pid" 2>/dev/null && kill -TERM "$pid" 2>/dev/null
done

ok "RACE_MODE 실행 완료 → $ART_DIR"
echo "$ART_DIR"
