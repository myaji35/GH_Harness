#!/usr/bin/env bash
# ============================================================
# GH_Harness — w.sh
# Git Worktree 헬퍼 (병렬 에이전트 실행 인프라)
#
# 사용법:
#   w <project> <feature> [command...]
#   w <project> <feature>            # worktree 생성 + 해당 디렉토리로 진입(shell)
#   w <project> <feature> claude     # worktree에서 claude 세션 시작
#   w <project> <feature> -- run cmd # worktree 안에서 임의 명령 실행
#   w list [project]                 # 현재 worktree 목록
#   w rm <project> <feature>         # worktree + 브랜치 삭제
#
# 동작:
#   1. <project>의 메인 디렉토리 탐색 (BATCH_BASE 기준)
#   2. worktree 디렉토리: $WORKTREE_HOME/<project>__<feature>
#   3. 새 브랜치 이름: wt/<user>/<feature> (기본)
#   4. node_modules / .next / .venv 등은 main 디렉토리에서 symlink
#   5. .gitignore 자동 패치 (.claude/worktrees, worktrees/)
#   6. 포트 충돌 방지 offset 파일 생성
#
# 환경 변수:
#   BATCH_BASE     프로젝트 루트 (기본: /Volumes/E_SSD/02_GitHub.nosync)
#   WORKTREE_HOME  worktree 저장 경로 (기본: $HOME/projects/worktrees)
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

BATCH_BASE="${BATCH_BASE:-/Volumes/E_SSD/02_GitHub.nosync}"
WORKTREE_HOME="${WORKTREE_HOME:-$HOME/projects/worktrees}"
USER_PREFIX="${USER:-gs}"

# 공유 심볼릭 대상 (프로젝트 루트 기준 상대 경로)
LINK_TARGETS=(
  "node_modules"
  ".next"
  ".venv"
  "venv"
  "vendor"
  "bundle"
  ".swc"
  ".turbo"
  ".cache"
)

# ------------------------------------------------------------
die() {
  echo -e "${RED}✖ $*${NC}" >&2
  exit 1
}

info() { echo -e "${BLUE}ℹ $*${NC}"; }
ok()   { echo -e "${GREEN}✓ $*${NC}"; }
warn() { echo -e "${YELLOW}! $*${NC}"; }

# 프로젝트 루트 찾기 (이름 exact → prefix 매치)
find_project_root() {
  local name="$1"
  local exact="$BATCH_BASE/$name"
  if [ -d "$exact/.git" ] || [ -d "$exact" ]; then
    echo "$exact"
    return 0
  fi
  local hit
  hit="$(find "$BATCH_BASE" -maxdepth 1 -type d -iname "*${name}*" 2>/dev/null | head -1)"
  [ -n "$hit" ] && echo "$hit" && return 0
  return 1
}

# .gitignore에 worktree 관련 패턴 추가
ensure_gitignore() {
  local root="$1"
  local gi="$root/.gitignore"
  local added=0
  touch "$gi"
  for pat in ".claude/worktrees" "worktrees/" ".harness-worktree-meta"; do
    if ! grep -qxF "$pat" "$gi" 2>/dev/null; then
      echo "$pat" >> "$gi"
      added=$((added+1))
    fi
  done
  [ "$added" -gt 0 ] && info ".gitignore 패턴 $added개 추가"
  return 0
}

# worktree 내부에 공유 심볼릭 링크 생성
ensure_symlinks() {
  local main_root="$1"
  local wt_root="$2"
  for target in "${LINK_TARGETS[@]}"; do
    local src="$main_root/$target"
    local dst="$wt_root/$target"
    [ -e "$src" ] || continue
    [ -e "$dst" ] && continue
    ln -s "$src" "$dst" 2>/dev/null && info "symlink: $target"
  done
}

# 포트 오프셋 계산 (같은 프로젝트 안 worktree마다 +1)
compute_port_offset() {
  local main_root="$1"
  local wt_name="$2"
  local meta="$main_root/.claude/worktrees.json"
  mkdir -p "$(dirname "$meta")"
  [ -f "$meta" ] || echo '{}' > "$meta"

  python3 - "$meta" "$wt_name" <<'PYEOF'
import json, sys
path, name = sys.argv[1], sys.argv[2]
with open(path) as f:
    data = json.load(f)
if name in data:
    print(data[name]["offset"])
else:
    offset = len(data) + 1
    data[name] = {"offset": offset}
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
    print(offset)
PYEOF
}

# ------------------------------------------------------------
cmd_list() {
  local proj="${1:-}"
  if [ -n "$proj" ]; then
    local root
    root="$(find_project_root "$proj")" || die "프로젝트 찾을 수 없음: $proj"
    ( cd "$root" && git worktree list )
  else
    info "worktree 저장소: $WORKTREE_HOME"
    [ -d "$WORKTREE_HOME" ] && ls -1 "$WORKTREE_HOME" || echo "(비어 있음)"
  fi
}

cmd_rm() {
  local proj="$1" feat="$2"
  [ -z "$proj" ] || [ -z "$feat" ] && die "usage: w rm <project> <feature>"
  local root wt_name wt_path branch
  root="$(find_project_root "$proj")" || die "프로젝트 찾을 수 없음: $proj"
  wt_name="${proj}__${feat}"
  wt_path="$WORKTREE_HOME/$wt_name"
  branch="wt/${USER_PREFIX}/${feat}"

  [ -d "$wt_path" ] || die "worktree 없음: $wt_path"

  ( cd "$root" && git worktree remove "$wt_path" --force 2>/dev/null || true )
  rm -rf "$wt_path"
  ( cd "$root" && git branch -D "$branch" 2>/dev/null || true )

  # meta 정리
  local meta="$root/.claude/worktrees.json"
  if [ -f "$meta" ]; then
    python3 - "$meta" "$wt_name" <<'PYEOF' >/dev/null 2>&1 || true
import json, sys
path, name = sys.argv[1], sys.argv[2]
with open(path) as f: d = json.load(f)
d.pop(name, None)
with open(path, 'w') as f: json.dump(d, f, indent=2)
PYEOF
  fi

  ok "제거 완료: $wt_name"
}

cmd_create() {
  local proj="$1" feat="$2"; shift 2 || true
  local cmd=("$@")

  [ -z "$proj" ] || [ -z "$feat" ] && die "usage: w <project> <feature> [command...]"

  local root
  root="$(find_project_root "$proj")" || die "프로젝트 찾을 수 없음: $proj (탐색경로: $BATCH_BASE)"

  # .git 확인 (없으면 init 제안 거절 — CLAUDE.md 규칙상 T2 아님, 그냥 에러)
  if [ ! -d "$root/.git" ]; then
    die "$root 는 git 저장소가 아님. 먼저 'git init'."
  fi

  local wt_name="${proj}__${feat}"
  local wt_path="$WORKTREE_HOME/$wt_name"
  local branch="wt/${USER_PREFIX}/${feat}"

  mkdir -p "$WORKTREE_HOME"
  ensure_gitignore "$root"

  if [ ! -d "$wt_path" ]; then
    info "worktree 생성: $wt_path"
    # 현재 브랜치에서 분기
    ( cd "$root" && git worktree add -b "$branch" "$wt_path" HEAD ) \
      || die "git worktree add 실패 (브랜치 '$branch'가 이미 있을 수 있음)"
    ensure_symlinks "$root" "$wt_path"
    local offset
    offset="$(compute_port_offset "$root" "$wt_name")"
    # 포트 offset 환경 파일 기록
    echo "# GH_Harness worktree metadata" > "$wt_path/.harness-worktree-meta"
    echo "HARNESS_PORT_OFFSET=$offset" >> "$wt_path/.harness-worktree-meta"
    echo "HARNESS_WORKTREE_NAME=$wt_name" >> "$wt_path/.harness-worktree-meta"
    echo "HARNESS_MAIN_ROOT=$root" >> "$wt_path/.harness-worktree-meta"
    ok "worktree 준비 완료 (브랜치: $branch, 포트 offset: +$offset)"
  else
    info "기존 worktree 재사용: $wt_path"
  fi

  # 명령 실행 모드
  if [ "${#cmd[@]}" -gt 0 ]; then
    case "${cmd[0]}" in
      claude)
        ( cd "$wt_path" && exec claude "${cmd[@]:1}" )
        ;;
      --)
        ( cd "$wt_path" && exec "${cmd[@]:1}" )
        ;;
      *)
        ( cd "$wt_path" && exec "${cmd[@]}" )
        ;;
    esac
  else
    # shell drop-in (대화형)
    info "cd $wt_path"
    cd "$wt_path" && exec "${SHELL:-/bin/bash}"
  fi
}

# ------------------------------------------------------------
case "${1:-}" in
  ""|-h|--help|help)
    cat <<EOF
GH_Harness w — git worktree 헬퍼

  w <project> <feature> [cmd...]   worktree 생성 + cmd 실행 (없으면 shell)
  w <project> <feature> claude     worktree에서 claude 시작
  w list [project]                 worktree 목록
  w rm <project> <feature>         worktree + 브랜치 삭제

환경:
  BATCH_BASE=$BATCH_BASE
  WORKTREE_HOME=$WORKTREE_HOME
EOF
    ;;
  list)  shift; cmd_list "$@" ;;
  rm|remove) shift; cmd_rm "$@" ;;
  *)     cmd_create "$@" ;;
esac
