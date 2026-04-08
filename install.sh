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

# ── 모드 감지 ─���────────────────────────────────────────
UPDATE_MODE=false
BATCH_MODE=false
BATCH_BASE=""

for arg in "$@"; do
  case "$arg" in
    --update) UPDATE_MODE=true ;;
    --batch) BATCH_MODE=true ;;
    --batch-dir=*) BATCH_MODE=true; BATCH_BASE="${arg#*=}" ;;
  esac
done

# ── 일괄 업데이트 모드 ─────────────────────────────────
if [ "$BATCH_MODE" = true ]; then
  BATCH_BASE="${BATCH_BASE:-$(dirname "$(pwd)")}"
  echo ""
  echo -e "${BLUE}╔═══════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║     GH_Harness 일괄 업데이트          ║${NC}"
  echo -e "${BLUE}╚═══════════════════════════════════════╝${NC}"
  echo ""
  echo -e "${YELLOW}대상 디렉토리: $BATCH_BASE${NC}"
  echo ""

  updated=0
  skipped=0
  for proj_dir in "$BATCH_BASE"/*/; do
    if [ -d "$proj_dir/.claude/issue-db" ] || [ -d "$proj_dir/.claude/hooks" ]; then
      proj_name=$(basename "$proj_dir")
      echo -e "${BLUE}━━━ $proj_name ━━━${NC}"
      (cd "$proj_dir" && bash "$SCRIPT_DIR/install.sh" --update)
      updated=$((updated + 1))
    else
      skipped=$((skipped + 1))
    fi
  done

  echo ""
  echo -e "${GREEN}일괄 업데이트 완료: ${updated}개 프로젝트 업데이트, ${skipped}개 스킵${NC}"
  exit 0
fi

# ── 업데이트 모드 헤더 ─────────────────────────────────
if [ "$UPDATE_MODE" = true ]; then
  echo ""
  echo -e "${BLUE}╔═══════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║     GH_Harness 업데이트               ║${NC}"
  echo -e "${BLUE}║     CLAUDE.md + hooks 최신화          ║${NC}"
  echo -e "${BLUE}╚═══════════════════════════════════════╝${NC}"
  echo ""
else
  echo ""
  echo -e "${BLUE}╔═══════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║     GH_Harness 설치 시작              ║${NC}"
  echo -e "${BLUE}║     Self-Evolving Harness System      ║${NC}"
  echo -e "${BLUE}╚═══════════════════════════════════════╝${NC}"
  echo ""
fi

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

# brand-dna.json 복사 (v2: 기존 파일이 있으면 보존)
if [ -f "$SCRIPT_DIR/project/.claude/brand-dna.json" ]; then
  if [ -f "$PROJECT_DIR/brand-dna.json" ]; then
    echo -e "  ${YELLOW}⊘ brand-dna.json (기존 파일 보존)${NC}"
  else
    cp "$SCRIPT_DIR/project/.claude/brand-dna.json" "$PROJECT_DIR/brand-dna.json"
    echo -e "  ${GREEN}✓ brand-dna.json (v2 템플릿)${NC}"
  fi
fi

# issue-db 초기화 (업데이트 모드에서는 기존 DB 보존)
if [ "$UPDATE_MODE" = true ] && [ -f "$PROJECT_DIR/issue-db/registry.json" ]; then
  echo -e "  ${YELLOW}⊘ issue-db/registry.json (기존 DB 보존)${NC}"
else
  mkdir -p "$PROJECT_DIR/issue-db"
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
fi

echo -e "${GREEN}  → 프로젝트 설치 완료${NC}"
echo ""

# ── 완료 메시지 ─────────────────────────────────────────
if [ "$UPDATE_MODE" = true ]; then
  echo -e "${BLUE}╔═══════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║     업데이트 완료!                    ║${NC}"
  echo -e "${BLUE}╚═══════════════════════════════════════╝${NC}"
else
  echo -e "${BLUE}╔═══════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║     설치 완료!                        ║${NC}"
  echo -e "${BLUE}╚═══════════════════════════════════════╝${NC}"
fi
echo ""
echo -e "${GREEN}전역 설치 위치:${NC} ~/.claude/"
echo -e "  agents/  → agent-harness, test-harness, eval-harness,"
echo -e "             cicd-harness, meta-agent, qa-reviewer,"
echo -e "             ux-harness, hook-router, biz-validator,"
echo -e "             design-critic, scenario-player, domain-analyst,"
echo -e "             product-manager, code-quality,"
echo -e "             ${BLUE}plan-ceo-reviewer, plan-eng-reviewer (v2)${NC},"
echo -e "             ${BLUE}opportunity-scout, brand-guardian (v2)${NC}"
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
echo -e "${GREEN}v2 시작 방법:${NC}"
echo -e "  Claude Code 실행 후 아래 문장 중 하나를 입력하세요:"
echo ""
echo -e "  ${BLUE}\"harness 시작하자\"${NC}        ⭐ v2 업그레이드 기능 자동 적용"
echo -e "  ${BLUE}\"harness 업그레이드 해줘\"${NC}  ⭐ 모든 하위 프로젝트에 v2 전파"
echo -e "  ${BLUE}\"brand 정의해줘\"${NC}          ⭐ 프로젝트 brand-dna 자동 초안"
echo ""
echo -e "${GREEN}v2 핵심 기능:${NC}"
echo -e "  1. Plan 2중 검토 (CEO + Eng) — 잘못된 문제 풀기 방지"
echo -e "  2. 브라우저 QA — gstack browse로 실제 콘솔 에러 캡처"
echo -e "  3. 편집 범위 자동 잠금 (freeze-guard)"
echo -e "  4. 발산 엔진 (opportunity-scout) — 통과 시 새 기회 자동 도출"
echo -e "  5. 브랜드 정체성 수호 (brand-guardian) — 획일화 방지"
echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
