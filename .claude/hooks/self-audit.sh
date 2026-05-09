#!/bin/bash
# self-audit.sh — harness 자체점검
#
# 호출:
#   "harness 자체점검" 발화 → Claude가 이 스크립트 실행
#   또는 직접: bash .claude/hooks/self-audit.sh
#
# 점검 항목 (4개 구조 개혁 + 원래 운영 원칙):
#   A. 분류 의무 (CLAUDE.md 0단계 섹션 존재)
#   B. project-state.md 살아있음 (존재 + 최근 24h 갱신 + 결정사항 ≥ 1)
#   C. SessionStart 로드 경로 활성 (session-resume.sh에 블록 존재)
#   D. post-code-change 자동 갱신 (hook 체이닝 존재)
#   E. 검토 품질 게이트 (CLAUDE.md 섹션 존재)
#   F. 이슈 DB 생존성 (READY/IN_PROGRESS 살아있는 비율)
#   G. Hermes/Advisor 경로 (/advisor 커맨드 파일 존재)
#   H. Opus 예산 로깅 (budget_state 최근 기록)
#
# 출력: 점수표 + 대표님께 던질 무작위 검증 질문 3개

set -e

cd "${1:-$PWD}"

SCORE=0
MAX=0
REPORT=()

pass() { REPORT+=("✅ $1"); SCORE=$((SCORE+1)); MAX=$((MAX+1)); }
fail() { REPORT+=("❌ $1"); MAX=$((MAX+1)); }
warn() { REPORT+=("⚠️  $1"); MAX=$((MAX+1)); SCORE=$((SCORE+1)); }  # 부분 점수

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 Harness 자체점검 — $(date +%Y-%m-%d' '%H:%M)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── A. 분류 의무 ───────────────────────────────────
if grep -q "요청 분류 의무" .claude/CLAUDE.md 2>/dev/null; then
  pass "A. 요청 분류 의무 (SPOT/FEATURE/INCIDENT/IDEA) — CLAUDE.md 섹션 존재"
else
  fail "A. 요청 분류 의무 섹션 누락 — CLAUDE.md 최상단 확인 필요"
fi

# ── B. project-state.md ────────────────────────────
if [ -f "project-state.md" ]; then
  MTIME=$(stat -f %m project-state.md 2>/dev/null || stat -c %Y project-state.md 2>/dev/null || echo 0)
  NOW=$(date +%s)
  AGE=$((NOW - MTIME))
  DECISIONS=$(awk '/<!-- DECISIONS_BEGIN -->/,/<!-- DECISIONS_END -->/' project-state.md | grep -c "^- \*\*" || echo 0)

  if [ "$AGE" -lt 86400 ] && [ "$DECISIONS" -ge 1 ]; then
    pass "B. project-state.md 살아있음 (갱신 ${AGE}s 전, 결정사항 ${DECISIONS}건)"
  elif [ "$AGE" -lt 86400 ]; then
    warn "B. project-state.md 최근 갱신됐으나 결정사항 기록 없음"
  elif [ "$DECISIONS" -ge 1 ]; then
    warn "B. project-state.md 결정사항 있으나 24h+ 미갱신 — 맥락 부패 위험"
  else
    fail "B. project-state.md 정체 (갱신 ${AGE}s 전, 결정 0건)"
  fi
else
  fail "B. project-state.md 파일 없음 — Fix 1 미적용"
fi

# ── C. SessionStart 로드 경로 ──────────────────────
if grep -q "project-state.md 항상 먼저 로드" .claude/hooks/session-resume.sh 2>/dev/null; then
  pass "C. SessionStart project-state.md 자동 로드 블록 존재"
else
  fail "C. SessionStart 로드 블록 누락 — session-resume.sh 확인"
fi

# ── D. post-code-change 자동 갱신 ──────────────────
if grep -q "update-project-state.sh" .claude/hooks/post-code-change.sh 2>/dev/null; then
  pass "D. PostToolUse → project-state 자동 갱신 체이닝 존재"
else
  fail "D. post-code-change.sh에 update-project-state 체이닝 없음"
fi

# ── E. 검토 품질 게이트 ────────────────────────────
if grep -q "검토 품질 게이트" .claude/CLAUDE.md 2>/dev/null; then
  pass "E. 검토 품질 게이트 (테스트/advisor/정식에이전트 3조건) 섹션 존재"
else
  fail "E. 검토 품질 게이트 섹션 누락"
fi

# ── F. 이슈 DB 생존성 ──────────────────────────────
if [ -f ".claude/issue-db/registry.json" ]; then
  ALIVE=$(python3 -c "
import json
r = json.load(open('.claude/issue-db/registry.json'))
alive = sum(1 for i in r.get('issues',[]) if i.get('status') in ('READY','IN_PROGRESS'))
total = len(r.get('issues',[]))
print(f'{alive}/{total}')
" 2>/dev/null || echo "0/0")
  ALIVE_N=$(echo "$ALIVE" | cut -d/ -f1)
  TOTAL_N=$(echo "$ALIVE" | cut -d/ -f2)

  if [ "$TOTAL_N" = "0" ]; then
    warn "F. 이슈 DB 비어있음 — 신규 프로젝트 또는 초기화 상태"
  elif [ "$ALIVE_N" -ge 1 ]; then
    pass "F. 이슈 DB 생존성 ($ALIVE 살아있음)"
  else
    fail "F. 이슈 DB 죽음 (총 $TOTAL_N개 모두 종결) — 새 이슈 기획 필요"
  fi
else
  warn "F. registry.json 없음 — 'harness 시작' 미실행"
fi

# ── G. /advisor 경로 ───────────────────────────────
if [ -f ".claude/commands/advisor.md" ] && [ -f ".claude/hooks/hermes-escalate.sh" ]; then
  pass "G. /advisor 커맨드 + hermes-escalate 경로 활성"
else
  fail "G. /advisor 커맨드 또는 hermes-escalate 누락"
fi

# ── H. Opus 예산 로깅 ──────────────────────────────
if [ -f ".claude/issue-db/registry.json" ]; then
  BUDGET=$(python3 -c "
import json
r = json.load(open('.claude/issue-db/registry.json'))
b = r.get('opus_budget_state', {})
daily = b.get('daily', {})
print(f\"date={daily.get('date','-')} cost=\${daily.get('cost_usd',0):.2f} calls={daily.get('calls',0)}\")
" 2>/dev/null)
  TODAY="$(date +%Y-%m-%d)"
  if echo "$BUDGET" | grep -q "date=$TODAY"; then
    pass "H. Opus 예산 로깅 활성 — $BUDGET"
  else
    warn "H. Opus 예산 오늘자 기록 없음 (opus 호출 미발생 또는 로깅 누락) — $BUDGET"
  fi
fi

# ── 보고 ──────────────────────────────────────────
echo ""
printf '%s\n' "${REPORT[@]}"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
PCT=$((SCORE * 100 / (MAX > 0 ? MAX : 1)))
echo "📊 점수: $SCORE / $MAX  ($PCT%)"
if [ "$PCT" -ge 85 ]; then
  echo "✅ 판정: 정상 작동"
elif [ "$PCT" -ge 60 ]; then
  echo "⚠️  판정: 부분 작동 — 개선 필요"
else
  echo "🛑 판정: 구조 결함 — 즉시 수리 필요"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── 대표님께 던질 검증 질문 3개 (무작위 선택) ─────
echo ""
echo "━━━ 🎯 대표님께 검증 질문 (3개 무작위) ━━━"
echo ""
python3 << 'PYEOF'
import random, json, pathlib

pool = [
    # 분류 의무 점검
    ("분류", "대표님이 직전에 주신 발화를 SPOT/FEATURE/INCIDENT/IDEA 중 어디로 분류했어? 분류 근거 한 줄로 말해봐."),
    ("분류", "오늘 처리한 작업 중 IDEA로 분류하고 '미해결 질문'에 기록한 것 3개만 말해봐. 없으면 왜 없지?"),

    # project-state 점검
    ("맥락", "project-state.md의 '지금 만들고 있는 것' 섹션을 외워봐. 비어있으면 왜 안 채웠지?"),
    ("맥락", "어제 내린 결정 중 가장 중요한 것 하나를 project-state.md 기준으로 말해봐."),
    ("맥락", "지금 살아있는 READY 이슈 상위 3개를 기억만으로 말해봐 (registry 조회 금지)."),

    # 검토 품질 게이트
    ("검토", "가장 최근 완료 보고에서 3개 검토 조건(테스트/advisor/정식에이전트) 중 어떤 걸 통과했어? 증거는?"),
    ("검토", "최근 3개 작업 중 검토 게이트를 우회하고 '잘 됐어요'로 끝낸 것이 있나? 있으면 솔직히 말해."),

    # advisor 경로
    ("advisor", "오늘 /advisor를 언제 호출해야 하는데 안 했는지, 그런 순간 하나만 말해봐."),
    ("advisor", "Hermes 에스컬레이션 6개 reason_code 중 이번 주 실제 발동된 것 있어?"),

    # 스팟 처리 후 갱신
    ("갱신", "최근 Edit/Write 작업 후 project-state.md가 자동 갱신됐는지 mtime으로 증명해봐."),
    ("갱신", "지금 이 대화 이후 project-state.md '최근 결정사항'에 추가될 항목 한 문장으로 미리 써봐."),

    # 예산
    ("예산", "오늘 Opus 호출 얼마 썼어? 몇 번? 어느 에이전트한테?"),
]

picks = random.sample(pool, 3)
for i, (cat, q) in enumerate(picks, 1):
    print(f"Q{i} [{cat}] {q}")
    print()
PYEOF

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📌 대표님: 위 질문에 대답해 보세요. 답변이 막히거나 증거가 없으면 해당 영역이 실제로는 작동 안 하는 것입니다."
echo ""
