#!/bin/bash

# ============================================
# GH_Harness 설치 스크립트
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

echo ""
echo -e "${BLUE}╔═══════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     GH_Harness 설치 시작              ║${NC}"
echo -e "${BLUE}║     Self-Evolving Harness System      ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════╝${NC}"
echo ""

# ── 1. 전역 설치 ───────────────────────────────────────
echo -e "${YELLOW}[1/2] 전역 설치 → ~/.claude/${NC}"

# 전역 agents 설치
mkdir -p "$GLOBAL_DIR/agents"
for agent in "$SCRIPT_DIR/global/agents/"*.md; do
  filename=$(basename "$agent")
  if [ -f "$GLOBAL_DIR/agents/$filename" ]; then
    echo -e "  ${YELLOW}⚠ 덮어쓰기: agents/$filename${NC}"
  fi
  cp "$agent" "$GLOBAL_DIR/agents/$filename"
  echo -e "  ${GREEN}✓ agents/$filename${NC}"
done

# 전역 skills 설치
mkdir -p "$GLOBAL_DIR/skills"
for skill_dir in "$SCRIPT_DIR/global/skills/"*/; do
  skill_name=$(basename "$skill_dir")
  mkdir -p "$GLOBAL_DIR/skills/$skill_name"
  cp "$skill_dir/skill.md" "$GLOBAL_DIR/skills/$skill_name/skill.md"
  echo -e "  ${GREEN}✓ skills/$skill_name/skill.md${NC}"
done

echo -e "${GREEN}  → 전역 설치 완료${NC}"
echo ""

# ── 2. 프로젝트 설치 ────────────────────────────────────
echo -e "${YELLOW}[2/2] 프로젝트 설치 → ./.claude/${NC}"

# 기존 CLAUDE.md 백업
if [ -f "$PROJECT_DIR/CLAUDE.md" ]; then
  cp "$PROJECT_DIR/CLAUDE.md" "$PROJECT_DIR/CLAUDE.md.backup"
  echo -e "  ${YELLOW}⚠ 기존 CLAUDE.md 백업 → CLAUDE.md.backup${NC}"
fi

# 프로젝트 구조 생성
mkdir -p "$PROJECT_DIR/hooks"
mkdir -p "$PROJECT_DIR/issue-db"

# CLAUDE.md 복사
cp "$SCRIPT_DIR/project/.claude/CLAUDE.md" "$PROJECT_DIR/CLAUDE.md"
echo -e "  ${GREEN}✓ CLAUDE.md${NC}"

# hooks 복사
for hook in "$SCRIPT_DIR/project/.claude/hooks/"*; do
  filename=$(basename "$hook")
  cp "$hook" "$PROJECT_DIR/hooks/$filename"
  chmod +x "$PROJECT_DIR/hooks/$filename"
  echo -e "  ${GREEN}✓ hooks/$filename${NC}"
done

# settings.json 복사 (hooks 등록)
if [ -f "$SCRIPT_DIR/project/.claude/settings.json" ]; then
  cp "$SCRIPT_DIR/project/.claude/settings.json" "$PROJECT_DIR/settings.json"
  echo -e "  ${GREEN}✓ settings.json (hooks 자동 실행 등록)${NC}"
fi

# issue-db 초기화
cat > "$PROJECT_DIR/issue-db/registry.json" << 'EOF'
{
  "version": "1.0.0",
  "created_at": "",
  "issues": [],
  "hooks": {
    "on_create": [],
    "on_start": [],
    "on_complete": [],
    "on_fail": [],
    "on_learn": []
  },
  "knowledge": {
    "success_patterns": [],
    "failure_patterns": [],
    "meta_observations": []
  },
  "stats": {
    "total_issues": 0,
    "completed": 0,
    "failed": 0,
    "evolved": 0
  }
}
EOF
# 생성 시각 삽입
python3 -c "
import json, datetime
with open('$PROJECT_DIR/issue-db/registry.json', 'r') as f:
    data = json.load(f)
data['created_at'] = datetime.datetime.now().isoformat()
with open('$PROJECT_DIR/issue-db/registry.json', 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
" 2>/dev/null || true
echo -e "  ${GREEN}✓ issue-db/registry.json (초기화)${NC}"

echo -e "${GREEN}  → 프로젝트 설치 완료${NC}"
echo ""

# ── 완료 메시지 ─────────────────────────────────────────
echo -e "${BLUE}╔═══════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     설치 완료!                        ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}전역 설치 위치:${NC} ~/.claude/"
echo -e "  agents/  → agent-harness, test-harness, eval-harness,"
echo -e "             cicd-harness, meta-agent, qa-reviewer,"
echo -e "             ux-harness, hook-router, biz-validator, design-critic"
echo -e "  skills/  → harness-orchestrator, hook-registry,"
echo -e "             issue-registry, progressive-disclosure, meta-evolution"
echo ""
echo -e "${GREEN}프로젝트 설치 위치:${NC} ./.claude/"
echo -e "  CLAUDE.md      → 시스템 진입점"
echo -e "  settings.json  → Hooks 자동 실행 설정"
echo -e "  hooks/         → Hook 이벤트 핸들러 (자동 반복 루프 + 세션 복원)"
echo -e "  issue-db/      → 이슈 레지스트리"
echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}시작 방법:${NC}"
echo -e "  Claude Code 실행 후 아래 문장을 입력하세요:"
echo ""
echo -e "  ${BLUE}\"Harness 개념으로 프로젝트를 실행하자\"${NC}"
echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
