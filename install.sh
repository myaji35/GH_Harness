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
WITH_GRAPHIFY=false
FORCE_MODE=false

for arg in "$@"; do
  case "$arg" in
    --update) UPDATE_MODE=true ;;
    --batch) BATCH_MODE=true ;;
    --batch-dir=*) BATCH_MODE=true; BATCH_BASE="${arg#*=}" ;;
    --optimize-tokens) TOKEN_OPTIMIZE=true ;;
    --with-graphify) WITH_GRAPHIFY=true ;;
    --force) FORCE_MODE=true ;;
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
    find "$SCRIPT_DIR/bin" -type f -name '*.sh' ! -name '._*' 2>/dev/null | sort | while read -r f; do shasum "$f" 2>/dev/null; done
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

install_graphify_scaffold() {
  local proj="$1"
  local target_dir="$proj/.claude/graphify"
  if [ -d "$target_dir" ]; then
    echo -e "${YELLOW}  Graphify 이미 설치됨 → skip${NC}"
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
  echo -e "${GREEN}  Graphify scaffold 설치 → $target_dir${NC}"
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

  CURRENT_SHA="$(compute_harness_sha)"
  echo -e "  ${BLUE}버전 SHA: ${CURRENT_SHA:0:12}${NC}"

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
with open(path) as f: data = json.load(f)
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
