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
TOKEN_OPTIMIZE=false
WITH_GRAPHIFY=false

for arg in "$@"; do
  case "$arg" in
    --update) UPDATE_MODE=true ;;
    --batch) BATCH_MODE=true ;;
    --batch-dir=*) BATCH_MODE=true; BATCH_BASE="${arg#*=}" ;;
    --optimize-tokens) TOKEN_OPTIMIZE=true ;;
    --with-graphify) WITH_GRAPHIFY=true ;;
  esac
done

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
      extra_flags=""
      [ "$WITH_GRAPHIFY" = true ] && extra_flags="--with-graphify"
      (cd "$proj_dir" && bash "$SCRIPT_DIR/install.sh" --update $extra_flags)
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

# v3 필수 디렉터리 생성
mkdir -p "$PROJECT_DIR/../docs/audience"
mkdir -p "$PROJECT_DIR/../docs/ui-snapshots"
mkdir -p "$PROJECT_DIR/../docs/brand"
mkdir -p "$PROJECT_DIR/../components"
echo -e "  ${GREEN}✓ docs/audience, docs/ui-snapshots, docs/brand, components/ (v3 디렉터리)${NC}"

# issue-db 초기화 (업데이트 모드에서는 기존 DB 보존)
if [ "$UPDATE_MODE" = true ] && [ -f "$PROJECT_DIR/issue-db/registry.json" ]; then
  echo -e "  ${YELLOW}⊘ issue-db/registry.json (기존 DB 보존)${NC}"
  # v3 필수 필드 자동 마이그레이션 (기존 DB 구조 보존)
  python3 -c "
import json
with open('$PROJECT_DIR/issue-db/registry.json', 'r') as f:
    data = json.load(f)

migrated = []

# hermes_state 추가
if 'hermes_state' not in data:
    data['hermes_state'] = {
        'invocations_by_issue': {},
        'daily_log': [],
        'total_invocations': 0
    }
    migrated.append('hermes_state')

# opus_budget_state 추가
if 'opus_budget_state' not in data:
    data['opus_budget_state'] = {
        'daily': {'date': '', 'cost_usd': 0.0, 'calls': 0},
        'monthly': {'month': '', 'cost_usd': 0.0, 'calls': 0},
        'demotion_active': False
    }
    migrated.append('opus_budget_state')

# issue_budget 추가
if 'issue_budget' not in data:
    data['issue_budget'] = {'date': '', 'created_today': 0}
    migrated.append('issue_budget')

# proactive_scan_state 추가
if 'proactive_scan_state' not in data:
    data['proactive_scan_state'] = {'date': '', 'count': 0}
    migrated.append('proactive_scan_state')

# version 갱신
data['version'] = '3.0.0'

if migrated:
    with open('$PROJECT_DIR/issue-db/registry.json', 'w') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    print(f'  v3 마이그레이션: {', '.join(migrated)} 추가됨')
else:
    print('  v3 필드 이미 존재')
" 2>/dev/null || true
else
  mkdir -p "$PROJECT_DIR/issue-db"
  cat > "$PROJECT_DIR/issue-db/registry.json" << 'EOF'
{
  "version": "3.0.0",
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

# ── 토큰 최적화 ────────────────────────────────────────
if [ "$TOKEN_OPTIMIZE" = true ]; then
  GLOBAL_SETTINGS="$HOME/.claude/settings.json"
  echo -e "${YELLOW}[TOKEN] 토큰 절감 최적화 적용 중...${NC}"

  if [ -f "$GLOBAL_SETTINGS" ]; then
    python3 -c "
import json

with open('$GLOBAL_SETTINGS', 'r') as f:
    data = json.load(f)

# 토큰 소비가 큰 플러그인 비활성화 (harness에서 불필요)
plugins = data.get('enabledPlugins', {})
disabled = []
# bkit: ~8,000 토큰/턴 (PDCA 보고서 + 에이전트 목록 + 스킬 목록)
if plugins.get('bkit@bkit-marketplace') is True:
    plugins['bkit@bkit-marketplace'] = False
    disabled.append('bkit (~8K tokens)')
# linear: ~1,500 토큰/턴
if plugins.get('linear@claude-plugins-official') is True:
    plugins['linear@claude-plugins-official'] = False
    disabled.append('linear (~1.5K tokens)')
# zapier: ~1,000 토큰/턴
if plugins.get('zapier@claude-plugins-official') is True:
    plugins['zapier@claude-plugins-official'] = False
    disabled.append('zapier (~1K tokens)')
# ruby-lsp: ~500 토큰/턴 (Rails 프로젝트만 필요)
if plugins.get('ruby-lsp@claude-plugins-official') is True:
    plugins['ruby-lsp@claude-plugins-official'] = False
    disabled.append('ruby-lsp (~500 tokens)')

data['enabledPlugins'] = plugins

with open('$GLOBAL_SETTINGS', 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)

if disabled:
    for d in disabled:
        print(f'  비활성화: {d}')
    total = sum(int(d.split('~')[1].split('K')[0].replace('.','').replace(',','')) for d in disabled if 'K' in d)
    print(f'  예상 절감: ~{total}K+ 토큰/턴')
else:
    print('  이미 최적화 상태')
" 2>/dev/null || echo -e "  ${RED}Python 처리 실패 — 수동 확인 필요${NC}"

  echo -e "${GREEN}  → 토큰 최적화 완료${NC}"
  echo -e "  ${YELLOW}유지: superpowers, chrome-devtools (harness 핵심)${NC}"
  echo -e "  ${YELLOW}비활성화된 플러그인은 필요 시 settings.json에서 재활성화${NC}"
  fi
  echo ""
fi

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
echo -e "  agents/  → 21개 에이전트 (v3)"
echo -e "             기존: agent-harness, test-harness, eval-harness,"
echo -e "             cicd-harness, meta-agent, qa-reviewer,"
echo -e "             ux-harness, hook-router, biz-validator,"
echo -e "             design-critic, scenario-player, domain-analyst,"
echo -e "             product-manager, code-quality,"
echo -e "             plan-ceo-reviewer, plan-eng-reviewer,"
echo -e "             opportunity-scout, brand-guardian"
echo -e "             ${BLUE}hermes, advisor, audience-researcher (v3)${NC}"
echo -e "  skills/  → harness-orchestrator, hook-registry,"
echo -e "             issue-registry, progressive-disclosure, meta-evolution"
echo ""
echo -e "${GREEN}프로젝트 설치 위치:${NC} ./.claude/"
echo -e "  CLAUDE.md      → 시스템 진입점 (v3: 3-Tier 컨펌 + Opus 예산)"
echo -e "  settings.json  → Hooks 자동 실행 설정"
echo -e "  hooks/         → Hook 이벤트 핸들러 (v3.1: Gemma 안정화 + 좀비 자동 청소 포함)"
echo -e "  issue-db/      → 이슈 레지스트리 (v3: hermes_state/opus_budget 자동 마이그레이션)"
echo ""
echo -e "${GREEN}프로젝트 디렉터리:${NC}"
echo -e "  docs/audience/       → 오디언스 리서치 결과"
echo -e "  docs/ui-snapshots/   → UI 레벨 승급 전후 스냅샷"
echo -e "  docs/brand/          → 브랜드 스크레이핑 결과"
echo -e "  components/          → 21st.dev 등 컴포넌트 프롬프트"
echo ""
if [ "$WITH_GRAPHIFY" = true ]; then
  echo ""
  echo -e "${BLUE}━━━ Graphify 파일럿 설치 ━━━${NC}"
  install_graphify_scaffold "$(pwd)"
fi

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}v3 시작 방법:${NC}"
echo -e "  Claude Code 실행 후 아래 문장 중 하나를 입력하세요:"
echo ""
echo -e "  ${BLUE}\"harness 시작하자\"${NC}            v3 전체 기능 자동 적용"
echo -e "  ${BLUE}\"harness 업그레이드 해줘\"${NC}      모든 하위 프로젝트에 v3 전파"
echo -e "  ${BLUE}\"brand 정의해줘\"${NC}              brand-dna 자동 초안 (Firecrawl 지원)"
echo ""
echo -e "${GREEN}v3 신규 기능 (v2 위에 추가):${NC}"
echo -e "  ${BLUE}Advisor Strategy${NC}"
echo -e "    6. Hermes 에스컬레이션 중개자 — executor 막힘 시 Opus 자문"
echo -e "    7. Advisor Opus 자문관 — Circuit Breaker 내장"
echo ""
echo -e "  ${BLUE}3-Tier 컨펌 정책${NC}"
echo -e "    8. T0 침묵 자동 / T1 내부 자문 / T2 사용자 컨펌"
echo -e "    9. AWAITING_USER 상태 — 개별 이슈만 멈추고 파이프라인은 계속"
echo -e "   10. Opus 예산 관리 — Soft \$10 / Hard \$20 / 월 \$250 / 자동 강등"
echo ""
echo -e "  ${BLUE}디자인 5 Levels 파이프라인${NC}"
echo -e "   11. Audience Researcher — 타겟 고객 언어/페인포인트 조사"
echo -e "   12. UI Level 1-5 단계적 승급 — basic → brand+testimonial"
echo -e "   13. 21st.dev 컴포넌트 카탈로그 규약"
echo -e "   14. BRAND_SCRAPE — Firecrawl/CLI로 브랜드 자산 자동 추출"
echo -e "   15. AI slop 진단 4항목 (A~D) — 원인 분류 + 자동 해결 라우팅"
echo ""
echo -e "  ${BLUE}부작용 방어 4종${NC}"
echo -e "   16. 이슈 폭발 방지 (일일 cap 30 + opportunity 발화 제외)"
echo -e "   17. Freeze x Hermes 충돌 방어 (scope 확장/해제)"
echo -e "   18. meta x Hermes 레이스 방어 (lock 파일)"
echo -e "   19. CLI 우선 원칙 — MCP보다 CLI 도구 우선"
echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
