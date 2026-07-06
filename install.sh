#!/bin/bash

# ============================================
# GH_Harness 설치 스크립트 (v4.1 — Symlink + 체크섬 최적화)
# Self-Evolving Agent Harness System
# ============================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GLOBAL_DIR="$HOME/.claude"
PROJECT_DIR="$(pwd)/.claude"

# v4.1: 중앙 hook 저장소 (symlink 원본)
HARNESS_CORE_DIR="$HOME/.claude/harness-core"

# 모드 감지
UPDATE_MODE=false
BATCH_MODE=false
BATCH_BASE=""
TOKEN_OPTIMIZE=false
WITH_GRAPHIFY=true   # v5.1: graphify 전 프로젝트 기본 운영 (--no-graphify로 비활성)
FORCE_MODE=false
WITH_WIKI=false
FORCE_WIKI=false
AUTO_SERVE=false

for arg in "$@"; do
  case "$arg" in
    --update) UPDATE_MODE=true ;;
    --batch) BATCH_MODE=true ;;
    --batch-dir=*) BATCH_MODE=true; BATCH_BASE="${arg#*=}" ;;
    --optimize-tokens) TOKEN_OPTIMIZE=true ;;
    --with-graphify) WITH_GRAPHIFY=true ;;
    --no-graphify) WITH_GRAPHIFY=false ;;
    --force) FORCE_MODE=true ;;
    --with-wiki) WITH_WIKI=true ;;
    --force-wiki) FORCE_WIKI=true ;;
    --auto-serve) AUTO_SERVE=true ;;
  esac
done

# ────────────────────────────────────────────────────────
# v4.1 최적화 유틸 (Symlink + 체크섬)
# ────────────────────────────────────────────────────────

is_appledouble() {
  local name
  name="$(basename "$1")"
  [[ "$name" == ._* ]]
}

# 현재 harness 버전 SHA 계산
compute_harness_sha() {
  {
    find "$SCRIPT_DIR/project/.claude/hooks" -type f ! -name '._*' 2>/dev/null | sort | while read -r f; do shasum "$f" 2>/dev/null; done
    find "$SCRIPT_DIR/global/agents" -type f -name '*.md' ! -name '._*' 2>/dev/null | sort | while read -r f; do shasum "$f" 2>/dev/null; done
    find "$SCRIPT_DIR/global/skills" -type f -name '*.md' ! -name '._*' 2>/dev/null | sort | while read -r f; do shasum "$f" 2>/dev/null; done
    find "$SCRIPT_DIR/global/graphify/semantic" -type f ! -name '._*' 2>/dev/null | sort | while read -r f; do shasum "$f" 2>/dev/null; done
    find "$SCRIPT_DIR/bin" -type f -name '*.sh' ! -name '._*' 2>/dev/null | sort | while read -r f; do shasum "$f" 2>/dev/null; done
    find "$SCRIPT_DIR/templates/wiki" -type f ! -name '._*' 2>/dev/null | sort | while read -r f; do shasum "$f" 2>/dev/null; done
    [ -f "$SCRIPT_DIR/project/.claude/settings.json" ] && shasum "$SCRIPT_DIR/project/.claude/settings.json"
    [ -f "$SCRIPT_DIR/project/.claude/CLAUDE.md" ] && shasum "$SCRIPT_DIR/project/.claude/CLAUDE.md"
  } | shasum | cut -d' ' -f1
}

# ─── Worktree 지원 유틸 (v4.2) ─────────────────────────────
# w.sh를 PATH(~/.local/bin)에 symlink로 노출
ensure_w_cli_symlink() {
  local src="$SCRIPT_DIR/bin/w.sh"
  [ -f "$src" ] || return 0
  chmod +x "$src" 2>/dev/null || true
  mkdir -p "$HOME/.local/bin"
  local link="$HOME/.local/bin/w"
  if [ -L "$link" ]; then
    local cur
    cur="$(readlink "$link")"
    [ "$cur" = "$src" ] && return 0
  fi
  [ -e "$link" ] && rm -f "$link"
  ln -s "$src" "$link"
  echo -e "  ${GREEN}w CLI → ~/.local/bin/w${NC}"
}

# datago CLI를 PATH(~/.local/bin)에 symlink로 노출 (v4.4: 공공데이터포털 자동화)
ensure_datago_cli_symlink() {
  local src="$SCRIPT_DIR/global/bin/datago"
  [ -f "$src" ] || return 0
  chmod +x "$src" 2>/dev/null || true
  chmod +x "$SCRIPT_DIR/global/lib/crawler-common/keychain.sh" 2>/dev/null || true
  mkdir -p "$HOME/.local/bin"
  local link="$HOME/.local/bin/datago"
  if [ -L "$link" ]; then
    local cur
    cur="$(readlink "$link")"
    [ "$cur" = "$src" ] && return 0
  fi
  [ -e "$link" ] && rm -f "$link"
  ln -s "$src" "$link"
  echo -e "  ${GREEN}datago CLI → ~/.local/bin/datago${NC}"
}

# RTK(Rust Token Killer) 토큰 절약 도구 자동 설치 (v5.3)
# rtk-guard.sh hook이 미설치 시 no-op이라 필수는 아니지만, 있으면 60~90% CLI 출력 절감.
ensure_rtk() {
  command -v rtk >/dev/null 2>&1 && return 0   # 이미 설치됨
  if command -v brew >/dev/null 2>&1; then
    brew install rtk >/dev/null 2>&1 \
      && echo -e "  ${GREEN}RTK 토큰절약 도구 설치 완료 (rtk $(rtk --version 2>/dev/null | awk '{print $2}'))${NC}" \
      || echo -e "  ${YELLOW}RTK 설치 실패 — rtk-guard.sh는 no-op으로 안전 동작${NC}"
  else
    echo -e "  ${YELLOW}brew 없음 — RTK 설치 건너뜀(rtk-guard.sh no-op). 수동: brew install rtk${NC}"
  fi
}

# 프로젝트 .gitignore에 worktree 관련 패턴 추가
ensure_project_gitignore_worktree() {
  local proj="$1"
  local gi="$proj/.gitignore"
  [ -d "$proj/.git" ] || return 0
  touch "$gi"
  local added=0
  for pat in ".claude/worktrees" "worktrees/" ".harness-worktree-meta" ".claude/worktrees.json"; do
    if ! grep -qxF "$pat" "$gi" 2>/dev/null; then
      echo "$pat" >> "$gi"
      added=$((added+1))
    fi
  done
  [ "$added" -gt 0 ] && echo -e "    ${BLUE}gitignore +${added} (worktree)${NC}"
  return 0
}

# 중앙 harness-core 동기화 (변경된 파일만)
sync_harness_core() {
  mkdir -p "$HARNESS_CORE_DIR/hooks"
  mkdir -p "$HARNESS_CORE_DIR/agents"
  mkdir -p "$HARNESS_CORE_DIR/skills"
  mkdir -p "$HARNESS_CORE_DIR/policy"

  local changed=0

  # hooks
  for hook in "$SCRIPT_DIR/project/.claude/hooks/"*; do
    [ -f "$hook" ] || continue
    is_appledouble "$hook" && continue
    local name dst
    name="$(basename "$hook")"
    dst="$HARNESS_CORE_DIR/hooks/$name"
    if [ ! -f "$dst" ] || ! cmp -s "$hook" "$dst"; then
      cp "$hook" "$dst"
      chmod +x "$dst"
      changed=$((changed+1))
    fi
  done

  # agents
  for agent in "$SCRIPT_DIR/global/agents/"*.md; do
    [ -f "$agent" ] || continue
    is_appledouble "$agent" && continue
    local name dst
    name="$(basename "$agent")"
    dst="$HARNESS_CORE_DIR/agents/$name"
    if [ ! -f "$dst" ] || ! cmp -s "$agent" "$dst"; then
      cp "$agent" "$dst"
      changed=$((changed+1))
    fi
  done

  # skills
  for skill_dir in "$SCRIPT_DIR/global/skills/"*/; do
    [ -d "$skill_dir" ] || continue
    local sname
    sname="$(basename "$skill_dir")"
    is_appledouble "$sname" && continue
    mkdir -p "$HARNESS_CORE_DIR/skills/$sname"
    if [ -f "$skill_dir/skill.md" ]; then
      local dst="$HARNESS_CORE_DIR/skills/$sname/skill.md"
      if [ ! -f "$dst" ] || ! cmp -s "$skill_dir/skill.md" "$dst"; then
        cp "$skill_dir/skill.md" "$dst"
        changed=$((changed+1))
      fi
    fi
  done

  # policy
  if [ -d "$SCRIPT_DIR/global/policy" ]; then
    for p in "$SCRIPT_DIR/global/policy/"*; do
      [ -f "$p" ] || continue
      is_appledouble "$p" && continue
      local name dst
      name="$(basename "$p")"
      dst="$HARNESS_CORE_DIR/policy/$name"
      if [ ! -f "$dst" ] || ! cmp -s "$p" "$dst"; then
        cp "$p" "$dst"
        changed=$((changed+1))
      fi
    done
  fi

  # graphify semantic 모듈 (로컬 Ollama 임베딩 기반 시맨틱 검색)
  if [ -d "$SCRIPT_DIR/global/graphify/semantic" ]; then
    mkdir -p "$HARNESS_CORE_DIR/graphify/semantic"
    for sf in "$SCRIPT_DIR/global/graphify/semantic/"*; do
      [ -f "$sf" ] || continue
      is_appledouble "$sf" && continue
      local name dst
      name="$(basename "$sf")"
      dst="$HARNESS_CORE_DIR/graphify/semantic/$name"
      if [ ! -f "$dst" ] || ! cmp -s "$sf" "$dst"; then
        cp "$sf" "$dst"
        changed=$((changed+1))
      fi
    done
  fi

  # CI/CD 템플릿 (cicd-harness가 CICD_BOOTSTRAP 처리 시 참조)
  if [ -d "$SCRIPT_DIR/global/templates/ci" ]; then
    mkdir -p "$HARNESS_CORE_DIR/templates/ci"
    for tf in "$SCRIPT_DIR/global/templates/ci/"*; do
      [ -f "$tf" ] || continue
      is_appledouble "$tf" && continue
      local name dst
      name="$(basename "$tf")"
      dst="$HARNESS_CORE_DIR/templates/ci/$name"
      if [ ! -f "$dst" ] || ! cmp -s "$tf" "$dst"; then
        cp "$tf" "$dst"
        changed=$((changed+1))
      fi
    done
  fi

  if [ "$changed" -gt 0 ]; then
    echo -e "  ${GREEN}harness-core 동기화: ${changed}개 파일 갱신${NC}"
  else
    echo -e "  ${YELLOW}harness-core 최신 (변경 없음)${NC}"
  fi
}

# 전역 agents/skills를 harness-core로 symlink
ensure_global_symlinks() {
  mkdir -p "$GLOBAL_DIR/agents"
  mkdir -p "$GLOBAL_DIR/skills"

  for core_agent in "$HARNESS_CORE_DIR/agents/"*.md; do
    [ -f "$core_agent" ] || continue
    local name link
    name="$(basename "$core_agent")"
    link="$GLOBAL_DIR/agents/$name"
    if [ -L "$link" ]; then
      continue
    fi
    [ -e "$link" ] && rm -f "$link"
    ln -s "$core_agent" "$link"
  done

  for core_skill_dir in "$HARNESS_CORE_DIR/skills/"*/; do
    [ -d "$core_skill_dir" ] || continue
    local name link
    name="$(basename "$core_skill_dir")"
    link="$GLOBAL_DIR/skills/$name"
    if [ -L "$link" ]; then
      continue
    fi
    [ -e "$link" ] && rm -rf "$link"
    ln -s "$core_skill_dir" "$link"
  done
}

# 프로젝트 hooks를 core로 symlink
install_project_hooks_symlink() {
  local proj_hooks="$1"
  mkdir -p "$proj_hooks"

  for core_hook in "$HARNESS_CORE_DIR/hooks/"*; do
    [ -f "$core_hook" ] || continue
    local name link
    name="$(basename "$core_hook")"
    link="$proj_hooks/$name"
    if [ -L "$link" ]; then
      local target
      target="$(readlink "$link")"
      if [ "$target" = "$core_hook" ]; then
        continue
      fi
    fi
    [ -e "$link" ] && rm -rf "$link"
    ln -s "$core_hook" "$link"
  done
}

write_version_sha() {
  echo "$2" > "$1/.harness-version"
}

read_version_sha() {
  if [ -f "$1/.harness-version" ]; then
    cat "$1/.harness-version" 2>/dev/null
  fi
  return 0
}

# graphify semantic 모듈을 프로젝트에 symlink (harness-core → 프로젝트)
# scaffold skip 여부와 무관하게 항상 보장 — 기존 graphify 설치 프로젝트도 업데이트 시 받도록.
ensure_graphify_semantic() {
  local proj="$1"
  local core_sem="$HARNESS_CORE_DIR/graphify/semantic"
  [ -d "$core_sem" ] || return 0
  local sem_dir="$proj/.claude/graphify/semantic"
  mkdir -p "$sem_dir"
  for sf in "$core_sem"/*; do
    [ -f "$sf" ] || continue
    local name link
    name="$(basename "$sf")"
    link="$sem_dir/$name"
    # 기존 실파일(로컬 작업본)은 덮어쓰지 않음 — symlink가 아니면 보존
    if [ -L "$link" ] || [ ! -e "$link" ]; then
      ln -sfn "$sf" "$link"
    fi
  done
}

install_graphify_scaffold() {
  local proj="$1"
  local target_dir="$proj/.claude/graphify"
  if [ -d "$target_dir" ]; then
    echo -e "${YELLOW}  Graphify 이미 설치됨 → semantic만 보강${NC}"
    ensure_graphify_semantic "$proj"
    return
  fi
  mkdir -p "$target_dir"
  cat > "$target_dir/baseline.json" <<EOF
{
  "recorded_at": "$(date -u +%Y-%m-%d)",
  "project": "$(basename "$proj")",
  "baseline": {
    "avg_tokens_per_issue": null,
    "avg_files_read_per_issue": null,
    "blindspot_incidents_30d": null,
    "qa_pass_rate": null
  }
}
EOF
  : > "$target_dir/metrics.jsonl"
  mkdir -p "$target_dir/graphify-out"
  # graph.json 등 산출물은 프로젝트 git에 커밋하지 않음(용량/노이즈)
  cat > "$target_dir/.gitignore" <<'EOF'
graphify-out/
.rebuild-needed
.last-autobuild
autobuild.log
semantic/__pycache__/
semantic/fixtures/
EOF
  cat > "$target_dir/README.md" <<'EOF'
# graphify (자동 운영)

이 프로젝트는 graphify 그래프를 **코드 변경 시 자동 증분 갱신**한다.

- **초기 빌드**: 세션 시작 시 graph.json이 없으면 session-resume이 빌드 신호를 띄움
  → Claude가 `/graphify . --update --no-viz` 실행 → `graphify-out/graph.json` 생성
- **증분 갱신**: 코드/문서 편집(Write/Edit) 시 post-code-change → graphify-autobuild가
  `.rebuild-needed` 신호를 남김(디바운스 90초) → 다음 세션 시작 시 증분 반영
- **활용**: agent-harness가 GENERATE_CODE/REFACTOR/FIX_BUG claim 직후 graph를 조회해
  의존성 맹점 제거 + 토큰 절감 (graphify-integration 스킬)

## 시맨틱 검색 (semantic/, 로컬 Ollama 임베딩)
`semantic/`는 harness-core symlink — 의미 기반 검색 모듈. Ollama 미설치 시 자동 skip($0).
- 사전조건: `ollama pull nomic-embed-text`
- 임베딩 빌드: `python3 .claude/graphify/semantic/vector_cache.py graphify-out/graph.json graphify-out/.vector_cache.json`
- 시맨틱 질의: `python3 .claude/graphify/semantic/semantic_query.py graphify-out/.vector_cache.json "<질문>" --top-k 5`
- BFS query로 도달 못 하는 의미상 유사 노드를 코사인 유사도로 발견. autobuild가 graph 갱신 시 증분 임베딩.

수동 전체 재빌드: `/graphify . --wiki`
EOF
  ensure_graphify_semantic "$proj"
  echo -e "${GREEN}  Graphify scaffold 설치 (+semantic) → $target_dir${NC}"
}

# ────────────────────────────────────────────────────────
# Wiki 스캐폴드 (v4.5: --with-wiki)
# ────────────────────────────────────────────────────────

check_python_for_wiki() {
  if [ "$WITH_WIKI" != "true" ]; then return 0; fi
  if ! command -v python3 >/dev/null 2>&1; then
    echo "[install.sh --with-wiki] python3 필요. 설치 후 재시도." >&2
    return 1
  fi
  local PY_VER PY_MAJOR PY_MINOR
  PY_VER="$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")"
  PY_MAJOR="$(echo "$PY_VER" | cut -d. -f1)"
  PY_MINOR="$(echo "$PY_VER" | cut -d. -f2)"
  if [ "$PY_MAJOR" -lt 3 ] || ([ "$PY_MAJOR" -eq 3 ] && [ "$PY_MINOR" -lt 8 ]); then
    echo "[install.sh --with-wiki] Python 3.8+ 필요 (현재: $PY_VER). mkdocs-material 9.5 의존." >&2
    return 1
  fi
  return 0
}

extract_wiki_vars() {
  local target_dir="${1:-$(pwd)}"
  WIKI_SITE_NAME="$(basename "$target_dir")"
  WIKI_PROJECT_NAME="$WIKI_SITE_NAME"
  WIKI_SITE_DESC=""
  if [ -f "$target_dir/README.md" ]; then
    WIKI_SITE_DESC="$(grep -m1 '^# ' "$target_dir/README.md" 2>/dev/null | sed 's/^# *//' || true)"
  fi
  WIKI_SITE_DESC="${WIKI_SITE_DESC:-코드 위키 (g3doc 스타일)}"
  WIKI_REPO_URL="$(cd "$target_dir" && git remote get-url origin 2>/dev/null || true)"
}

substitute_wiki_vars() {
  local file="$1"
  sed -e "s|{{site_name}}|${WIKI_SITE_NAME}|g" \
      -e "s|{{project_name}}|${WIKI_PROJECT_NAME}|g" \
      -e "s|{{site_description}}|${WIKI_SITE_DESC}|g" \
      -e "s|{{repo_url}}|${WIKI_REPO_URL}|g" \
      "$file" > "$file.tmp" && mv "$file.tmp" "$file"
}

copy_wiki_file() {
  local src="$1" dst="$2"
  if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
    echo "[wiki] $dst 동일 — skip" >&2
    return 0
  fi
  if [ -f "$dst" ] && [ "$FORCE_WIKI" != "true" ]; then
    echo "[wiki] $dst 이미 존재 — 보존 (강제 갱신: --force-wiki)" >&2
    return 0
  fi
  if [ -f "$dst" ]; then
    cp "$dst" "$dst.bak"
    echo "[wiki] $dst → $dst.bak 백업" >&2
  fi
  cp "$src" "$dst"
  echo "[wiki] $dst 생성" >&2
}

install_wiki_scaffold() {
  local target_dir="${1:-$(pwd)}"
  local templates_dir="$SCRIPT_DIR/templates/wiki"

  if [ ! -d "$templates_dir" ]; then
    echo "[wiki] templates/wiki/ 미발견: $templates_dir" >&2
    return 1
  fi

  echo "[wiki] $target_dir에 위키 스캐폴드 적용 중..." >&2
  extract_wiki_vars "$target_dir"

  mkdir -p "$target_dir/docs"

  # 1. mkdocs.yml
  local tmp_mkdocs
  tmp_mkdocs="$(mktemp)"
  cp "$templates_dir/mkdocs.yml.tmpl" "$tmp_mkdocs"
  substitute_wiki_vars "$tmp_mkdocs"
  copy_wiki_file "$tmp_mkdocs" "$target_dir/mkdocs.yml"
  rm -f "$tmp_mkdocs"

  # 2. requirements-docs.txt (변수 없음)
  copy_wiki_file "$templates_dir/requirements-docs.txt" "$target_dir/requirements-docs.txt"

  # 3. docs/index.md
  if [ ! -f "$target_dir/docs/index.md" ]; then
    local tmp_idx
    tmp_idx="$(mktemp)"
    cp "$templates_dir/docs-index.md.tmpl" "$tmp_idx"
    substitute_wiki_vars "$tmp_idx"
    cp "$tmp_idx" "$target_dir/docs/index.md"
    echo "[wiki] $target_dir/docs/index.md 생성" >&2
    rm -f "$tmp_idx"
  else
    echo "[wiki] docs/index.md 이미 존재 — 보존" >&2
  fi

  # 4. .gitignore append (멱등)
  if ! grep -q '^site/$' "$target_dir/.gitignore" 2>/dev/null; then
    cat "$templates_dir/gitignore-snippet" >> "$target_dir/.gitignore"
    echo "[wiki] .gitignore에 site/ + .venv-docs/ 추가" >&2
  else
    echo "[wiki] .gitignore에 site/ 이미 존재 — skip" >&2
  fi

  # 5. README ## Wiki 섹션 (grep 멱등)
  if [ -f "$target_dir/README.md" ] && ! grep -q '^## Wiki' "$target_dir/README.md"; then
    echo "" >> "$target_dir/README.md"
    local tmp_readme
    tmp_readme="$(mktemp)"
    cp "$templates_dir/readme-section.md.tmpl" "$tmp_readme"
    substitute_wiki_vars "$tmp_readme"
    cat "$tmp_readme" >> "$target_dir/README.md"
    echo "[wiki] README.md에 ## Wiki 섹션 추가" >&2
    rm -f "$tmp_readme"
  elif [ ! -f "$target_dir/README.md" ]; then
    echo "[wiki] README.md 미발견 — ## Wiki 섹션 skip (수동 추가 필요)" >&2
  else
    echo "[wiki] README.md에 ## Wiki 이미 존재 — skip" >&2
  fi

  # 6. bin/wiki-setup.sh (venv+pip+mkdocs serve 분리, here-doc 생성)
  mkdir -p "$target_dir/bin"
  if [ ! -f "$target_dir/bin/wiki-setup.sh" ]; then
    cat > "$target_dir/bin/wiki-setup.sh" <<'WIKIEOF'
#!/usr/bin/env bash
# wiki-setup.sh — venv + pip install + mkdocs serve
set -e
cd "$(dirname "$0")/.."
if [ ! -d .venv-docs ]; then
  python3 -m venv .venv-docs
fi
source .venv-docs/bin/activate
pip install -q -r requirements-docs.txt
echo "[wiki-setup] mkdocs serve 시작 → http://127.0.0.1:8765"
exec mkdocs serve --dev-addr 127.0.0.1:8765 "$@"
WIKIEOF
    chmod +x "$target_dir/bin/wiki-setup.sh"
    echo "[wiki] bin/wiki-setup.sh 생성 (실행권한 부여)" >&2
  else
    echo "[wiki] bin/wiki-setup.sh 이미 존재 — 보존" >&2
  fi

  echo "[wiki] 스캐폴드 완료. 'bash bin/wiki-setup.sh' 또는 'mkdocs serve'로 시작." >&2

  if [ "$AUTO_SERVE" = "true" ]; then
    echo "[wiki] --auto-serve: bin/wiki-setup.sh 백그라운드 실행..." >&2
    (cd "$target_dir" && nohup bash bin/wiki-setup.sh > "/tmp/wiki-serve-${WIKI_PROJECT_NAME}.log" 2>&1 &)
    sleep 2
    echo "[wiki] 백그라운드 시작됨 — http://127.0.0.1:8765 (로그: /tmp/wiki-serve-${WIKI_PROJECT_NAME}.log)" >&2
  fi
}

# ────────────────────────────────────────────────────────
# 일괄 업데이트 모드 (v4.1: harness-core 1회 동기화 → 심볼릭)
# ────────────────────────────────────────────────────────
if [ "$BATCH_MODE" = true ]; then
  BATCH_BASE="${BATCH_BASE:-$(dirname "$(pwd)")}"
  echo ""
  echo -e "${BLUE}GH_Harness v4.1 일괄 업데이트${NC}"
  echo -e "${YELLOW}대상: $BATCH_BASE${NC}"
  echo ""

  # 1. harness-core 동기화 (한 번만)
  echo -e "${YELLOW}[1/3] harness-core 중앙 동기화${NC}"
  sync_harness_core
  ensure_global_symlinks
  ensure_w_cli_symlink
  ensure_datago_cli_symlink

  CURRENT_SHA="$(compute_harness_sha)"
  echo -e "  ${BLUE}버전 SHA: ${CURRENT_SHA:0:12}${NC}"

  # wiki 사전 체크 (배치 모드에서도 --with-wiki 명시 시에만)
  if [ "$WITH_WIKI" = "true" ]; then
    check_python_for_wiki || exit 1
  fi

  # 2. 각 프로젝트에 symlink 배포
  echo -e "${YELLOW}[2/3] 프로젝트 symlink 배포${NC}"
  updated=0
  skipped=0
  unchanged=0

  for proj_dir in "$BATCH_BASE"/*/; do
    if [ ! -d "$proj_dir/.claude/issue-db" ] && [ ! -d "$proj_dir/.claude/hooks" ]; then
      skipped=$((skipped+1))
      continue
    fi

    proj_name="$(basename "$proj_dir")"
    claude_dir="$proj_dir/.claude"
    prev_sha="$(read_version_sha "$claude_dir" || true)"

    if [ "$prev_sha" = "$CURRENT_SHA" ] && [ "$FORCE_MODE" != true ]; then
      echo -e "  ${BLUE}⊘${NC} $proj_name (최신)"
      unchanged=$((unchanged+1))
      continue
    fi

    # hooks symlink + CLAUDE.md/settings.json 실파일 복사
    install_project_hooks_symlink "$claude_dir/hooks"

    if [ ! -f "$claude_dir/CLAUDE.md" ] || ! cmp -s "$SCRIPT_DIR/project/.claude/CLAUDE.md" "$claude_dir/CLAUDE.md"; then
      [ -f "$claude_dir/CLAUDE.md" ] && cp "$claude_dir/CLAUDE.md" "$claude_dir/CLAUDE.md.backup"
      cp "$SCRIPT_DIR/project/.claude/CLAUDE.md" "$claude_dir/CLAUDE.md"
    fi

    if [ ! -f "$claude_dir/settings.json" ] || ! cmp -s "$SCRIPT_DIR/project/.claude/settings.json" "$claude_dir/settings.json"; then
      cp "$SCRIPT_DIR/project/.claude/settings.json" "$claude_dir/settings.json"
    fi

    # brand-dna는 보존
    if [ ! -f "$claude_dir/brand-dna.json" ] && [ -f "$SCRIPT_DIR/project/.claude/brand-dna.json" ]; then
      cp "$SCRIPT_DIR/project/.claude/brand-dna.json" "$claude_dir/brand-dna.json"
    fi

    # registry.json v3 필드 마이그레이션
    if [ -f "$claude_dir/issue-db/registry.json" ]; then
      python3 - "$claude_dir/issue-db/registry.json" <<'PYEOF'
import json, sys
path = sys.argv[1]
# 손상된 registry는 batch 전체를 죽이지 않도록 격리 (v5.3) — 경고 후 skip
try:
    with open(path) as f: data = json.load(f)
except (json.JSONDecodeError, ValueError) as e:
    print(f"  ⚠️ registry.json 손상 — 마이그레이션 skip: {e}", file=sys.stderr)
    sys.exit(0)
changed = False
for k, default in [
    ('hermes_state', {'invocations_by_issue': {}, 'daily_log': [], 'total_invocations': 0}),
    ('opus_budget_state', {'daily': {'date': '', 'cost_usd': 0.0, 'calls': 0}, 'monthly': {'month': '', 'cost_usd': 0.0, 'calls': 0}, 'demotion_active': False}),
    ('issue_budget', {'date': '', 'created_today': 0}),
    ('proactive_scan_state', {'date': '', 'count': 0}),
]:
    if k not in data:
        data[k] = default
        changed = True
if data.get('version') != '3.0.0':
    data['version'] = '3.0.0'
    changed = True
if changed:
    with open(path, 'w') as f: json.dump(data, f, indent=2, ensure_ascii=False)
PYEOF
    fi

    # worktree 지원: .gitignore 패턴 추가
    ensure_project_gitignore_worktree "$proj_dir"

    # graphify 스캐폴드 (v5.1: 전 프로젝트 기본 운영 — 이미 설치 시 내부 skip, --no-graphify로 옵트아웃)
    if [ "$WITH_GRAPHIFY" = true ]; then
      install_graphify_scaffold "$proj_dir"
    fi

    # wiki 스캐폴드 (--batch --with-wiki 명시 시에만)
    if [ "$WITH_WIKI" = "true" ]; then
      install_wiki_scaffold "$proj_dir"
    fi

    # 버전 기록
    write_version_sha "$claude_dir" "$CURRENT_SHA"

    echo -e "  ${GREEN}✓${NC} $proj_name (symlink 배포)"
    updated=$((updated+1))
  done

  echo ""
  echo -e "${YELLOW}[3/3] 완료${NC}"
  echo -e "  ${GREEN}업데이트: $updated${NC} / ${BLUE}최신 유지: $unchanged${NC} / ${YELLOW}스킵: $skipped${NC}"
  echo -e "  ${GREEN}중앙 저장소: $HARNESS_CORE_DIR${NC}"
  echo -e "  ${BLUE}hint: 다음 실행 시 변경 없으면 즉시 skip${NC}"
  exit 0
fi

# ────────────────────────────────────────────────────────
# 단일 프로젝트 설치/업데이트 (v4.1: symlink 기반)
# ────────────────────────────────────────────────────────

if [ "$UPDATE_MODE" = true ]; then
  echo ""
  echo -e "${BLUE}GH_Harness v4.1 업데이트 (symlink)${NC}"
  echo ""
else
  echo ""
  echo -e "${BLUE}GH_Harness v4.1 설치${NC}"
  echo ""
fi

# 1. harness-core 동기화
echo -e "${YELLOW}[1/2] harness-core 중앙 동기화${NC}"
sync_harness_core
ensure_global_symlinks
ensure_w_cli_symlink
ensure_datago_cli_symlink
ensure_rtk

CURRENT_SHA="$(compute_harness_sha)"
PREV_SHA="$(read_version_sha "$PROJECT_DIR")"
if [ "$PREV_SHA" = "$CURRENT_SHA" ] && [ "$FORCE_MODE" != true ] && [ "$UPDATE_MODE" = true ]; then
  echo -e "  ${BLUE}이 프로젝트는 이미 최신 (${CURRENT_SHA:0:12}) — skip${NC}"
  echo -e "  ${YELLOW}강제 재배포: --force${NC}"
  exit 0
fi

# 2. 프로젝트 설치
echo -e "${YELLOW}[2/2] 프로젝트 → $PROJECT_DIR${NC}"

if [ -f "$PROJECT_DIR/CLAUDE.md" ]; then
  if ! cmp -s "$SCRIPT_DIR/project/.claude/CLAUDE.md" "$PROJECT_DIR/CLAUDE.md"; then
    cp "$PROJECT_DIR/CLAUDE.md" "$PROJECT_DIR/CLAUDE.md.backup"
    echo -e "  ${YELLOW}CLAUDE.md 백업 → CLAUDE.md.backup${NC}"
  fi
fi

mkdir -p "$PROJECT_DIR/hooks"
mkdir -p "$PROJECT_DIR/issue-db"

cp "$SCRIPT_DIR/project/.claude/CLAUDE.md" "$PROJECT_DIR/CLAUDE.md"
echo -e "  ${GREEN}✓ CLAUDE.md${NC}"

install_project_hooks_symlink "$PROJECT_DIR/hooks"
echo -e "  ${GREEN}✓ hooks/ (symlink → harness-core)${NC}"

if [ -f "$SCRIPT_DIR/project/.claude/settings.json" ]; then
  cp "$SCRIPT_DIR/project/.claude/settings.json" "$PROJECT_DIR/settings.json"
  echo -e "  ${GREEN}✓ settings.json${NC}"
fi

if [ -f "$SCRIPT_DIR/project/.claude/brand-dna.json" ]; then
  if [ -f "$PROJECT_DIR/brand-dna.json" ]; then
    echo -e "  ${YELLOW}⊘ brand-dna.json (기존 파일 보존)${NC}"
  else
    cp "$SCRIPT_DIR/project/.claude/brand-dna.json" "$PROJECT_DIR/brand-dna.json"
    echo -e "  ${GREEN}✓ brand-dna.json${NC}"
  fi
fi

mkdir -p "$PROJECT_DIR/../docs/audience"
mkdir -p "$PROJECT_DIR/../docs/ui-snapshots"
mkdir -p "$PROJECT_DIR/../docs/brand"
mkdir -p "$PROJECT_DIR/../components"

if [ -f "$SCRIPT_DIR/docs/graphrag-principles.md" ] && [ ! -f "$PROJECT_DIR/../docs/graphrag-principles.md" ]; then
  cp "$SCRIPT_DIR/docs/graphrag-principles.md" "$PROJECT_DIR/../docs/graphrag-principles.md" 2>/dev/null || true
fi

# registry.json
if [ "$UPDATE_MODE" = true ] && [ -f "$PROJECT_DIR/issue-db/registry.json" ]; then
  python3 - "$PROJECT_DIR/issue-db/registry.json" <<'PYEOF'
import json, sys
path = sys.argv[1]
with open(path) as f: data = json.load(f)
changed = False
for k, default in [
    ('hermes_state', {'invocations_by_issue': {}, 'daily_log': [], 'total_invocations': 0}),
    ('opus_budget_state', {'daily': {'date': '', 'cost_usd': 0.0, 'calls': 0}, 'monthly': {'month': '', 'cost_usd': 0.0, 'calls': 0}, 'demotion_active': False}),
    ('issue_budget', {'date': '', 'created_today': 0}),
    ('proactive_scan_state', {'date': '', 'count': 0}),
]:
    if k not in data:
        data[k] = default; changed = True
if data.get('version') != '3.0.0':
    data['version'] = '3.0.0'; changed = True
if changed:
    with open(path, 'w') as f: json.dump(data, f, indent=2, ensure_ascii=False)
PYEOF
  echo -e "  ${YELLOW}⊘ issue-db/registry.json (보존 + v3 마이그레이션)${NC}"
else
  if [ ! -f "$PROJECT_DIR/issue-db/registry.json" ]; then
    cat > "$PROJECT_DIR/issue-db/registry.json" << 'EOF'
{
  "version": "3.0.0",
  "created_at": "",
  "issues": [],
  "hooks": {"on_create": [], "on_start": [], "on_complete": [], "on_fail": [], "on_learn": []},
  "knowledge": {"success_patterns": [], "failure_patterns": [], "meta_observations": []},
  "stats": {"total_issues": 0, "completed": 0, "failed": 0, "evolved": 0}
}
EOF
    python3 -c "
import json, datetime
with open('$PROJECT_DIR/issue-db/registry.json') as f: d = json.load(f)
d['created_at'] = datetime.datetime.now().isoformat()
with open('$PROJECT_DIR/issue-db/registry.json', 'w') as f: json.dump(d, f, indent=2, ensure_ascii=False)
" 2>/dev/null || true
    echo -e "  ${GREEN}✓ issue-db/registry.json${NC}"
  fi
fi

# worktree 지원: .gitignore 패턴 추가
ensure_project_gitignore_worktree "$(pwd)"

# 버전 기록
write_version_sha "$PROJECT_DIR" "$CURRENT_SHA"
echo -e "  ${GREEN}✓ .harness-version (${CURRENT_SHA:0:12})${NC}"

# 토큰 최적화
if [ "$TOKEN_OPTIMIZE" = true ]; then
  GLOBAL_SETTINGS="$HOME/.claude/settings.json"
  if [ -f "$GLOBAL_SETTINGS" ]; then
    python3 - "$GLOBAL_SETTINGS" <<'PYEOF'
import json, sys
path = sys.argv[1]
with open(path) as f: data = json.load(f)
plugins = data.get('enabledPlugins', {})
disabled = []
for key, label in [
    ('bkit@bkit-marketplace', 'bkit'),
    ('linear@claude-plugins-official', 'linear'),
    ('zapier@claude-plugins-official', 'zapier'),
    ('ruby-lsp@claude-plugins-official', 'ruby-lsp'),
]:
    if plugins.get(key) is True:
        plugins[key] = False
        disabled.append(label)
data['enabledPlugins'] = plugins
with open(path, 'w') as f: json.dump(data, f, indent=2, ensure_ascii=False)
if disabled:
    print(f"  토큰 최적화: {', '.join(disabled)} 비활성")
PYEOF
  fi
fi

# Graphify scaffold
if [ "$WITH_GRAPHIFY" = true ]; then
  install_graphify_scaffold "$(pwd)"
fi

# Wiki scaffold (단일 모드: --with-wiki 명시 시에만)
if [ "$WITH_WIKI" = "true" ]; then
  check_python_for_wiki || exit 1
  install_wiki_scaffold "$(pwd)"
fi

echo ""
if [ "$UPDATE_MODE" = true ]; then
  echo -e "${GREEN}업데이트 완료${NC}"
else
  echo -e "${GREEN}설치 완료${NC}"
fi
echo ""
echo -e "${BLUE}v4.2 Symlink 구조:${NC}"
echo -e "  중앙: $HARNESS_CORE_DIR"
echo -e "  전역: $GLOBAL_DIR/agents, $GLOBAL_DIR/skills (symlink)"
echo -e "  프로젝트: $PROJECT_DIR/hooks (symlink)"
echo -e "  CLI: ~/.local/bin/w (worktree helper)"
echo -e "  버전 SHA: ${CURRENT_SHA:0:12}"
echo ""
echo -e "${YELLOW}다음 업데이트 시 변경 없으면 자동 skip (--force로 강제 재배포)${NC}"
