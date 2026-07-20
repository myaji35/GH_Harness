#!/bin/bash
# session-resume.sh — 새 세션 시작 시 registry.json 상태 요약
# SessionStart hook에서 호출됨
#
# 역할:
#   1. registry.json 존재 여부 확인
#   2. 전체 이슈 통계 출력
#   3. IN_PROGRESS / READY 이슈 목록 출력
#   4. 다음 실행 지시 제공

# 심볼릭 링크 설치(프로젝트 .claude/hooks/ → harness-core/hooks/) 대응:
# BASH_SOURCE는 링크 경로라 lib/ 를 프로젝트 쪽에서 찾다 ModuleNotFoundError로 죽는다.
# UserPromptSubmit/SessionStart hook이 죽으면 claude 실행 자체가 실패한다.
_src="${BASH_SOURCE[0]}"
while [ -L "$_src" ]; do
  _dir="$(cd -P "$(dirname "$_src")" && pwd)"
  _src="$(readlink "$_src")"
  [[ "$_src" != /* ]] && _src="$_dir/$_src"
done
SCRIPT_DIR="$(cd -P "$(dirname "$_src")" && pwd)"
REGISTRY=".claude/issue-db/registry.json"
BRAND_DNA="brand-dna.json"

# ── 프로젝트 디자인 아젠다 자동 주입 ──
# brand-dna.json이 있으면 design_tokens + agenda를 컨텍스트에 출력
if [ -f "$BRAND_DNA" ]; then
  python3 - "$SCRIPT_DIR" "$BRAND_DNA" << 'PYEOF'
import sys
# heredoc 보간 금지 — argv로 수신 (RCE 차단, 2026-07-15)
_ARGV = (sys.argv[1:3] + ['']*2)[:2]

import json, os
__file__ = os.path.join(_ARGV[0], "session-resume.sh")
sys.path.insert(0, os.path.join(os.path.dirname(__file__),'lib'))
from issue_id import next_id

try:
    with open(_ARGV[1], 'r') as f:
        dna = json.load(f)
    status = dna.get("_status", "unknown")
    agenda = dna.get("agenda", "")
    tokens = dna.get("design_tokens", {})
    colors = tokens.get("colors", {})
    hero = colors.get("hero", "")
    typo = tokens.get("typography", {})
    shape = tokens.get("shape", {})
    motion = tokens.get("motion", {})
    anti = dna.get("anti_patterns", [])
    tone = dna.get("emotional_tone", [])

    print("━━━ 🎨 프로젝트 디자인 아젠다 (brand-dna.json) ━━━")
    print(f"상태: {status}")
    if status == "uninitialized":
        # 실제 BRAND_DEFINE 이슈를 registry에 생성 (ISS-373) — 경고만 출력하던 결함 수정
        import datetime as _dt
        _REG = ".claude/issue-db/registry.json"
        try:
            _reg = json.load(open(_REG))
            _title = "[BRAND] brand-dna.json 미초기화 — 디자인 토큰 정의"
            _exists = any(i.get("type") == "BRAND_DEFINE"
                          and i.get("status") in ("READY", "IN_PROGRESS")
                          for i in _reg.get("issues", []))
            if not _exists:
                _new_id = next_id(_reg)
                _now = _dt.datetime.now().isoformat()
                _reg["issues"].append({
                    "id": _new_id, "title": _title, "type": "BRAND_DEFINE",
                    "status": "READY", "priority": "P1", "assign_to": "brand-guardian",
                    "depth": 0, "created_at": _now, "updated_at": _now,
                    "payload": {"origin": "session-resume", "action": "draft_brand_dna"},
                })
                _reg.setdefault("stats", {})["total_issues"] = _reg["stats"].get("total_issues", 0)+1
                json.dump(_reg, open(_REG, "w"), ensure_ascii=False, indent=2)
                print(f"⚠️  brand-dna.json 미초기화 → BRAND_DEFINE 이슈 {_new_id} 자동 생성 (brand-guardian)")
            else:
                print("⚠️  brand-dna.json 미초기화 — BRAND_DEFINE 이슈 이미 존재")
        except Exception as _e:
            print(f"⚠️  brand-dna.json 미초기화 — BRAND_DEFINE 생성 실패: {_e}")
    else:
        if agenda:
            print(f"아젠다: {agenda}")
        if tone:
            print(f"감성 톤: {', '.join(tone)}")
        if hero:
            print(f"Hero Color: {hero}")
        if colors.get("text_primary"):
            print(f"Text Primary: {colors.get('text_primary')}")
        if colors.get("surface"):
            print(f"Surface: {colors.get('surface')}")
        if typo.get("font_heading"):
            print(f"Typography: heading={typo.get('font_heading')} body={typo.get('font_body','')}")
        if shape.get("radius"):
            print(f"Shape: radius={shape.get('radius')}")
        if motion.get("hover_effect"):
            print(f"Motion: hover={motion.get('hover_effect')}")
        if anti:
            print(f"Anti-patterns ({len(anti)}): {', '.join(anti[:3])}{'...' if len(anti)>3 else ''}")
    print("→ UI 작업 시 이 토큰을 harness-ui-trends-2026.md의 기본값보다 우선 적용하라.")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
except Exception as e:
    print(f"[brand-dna.json 파싱 실패: {e}]")
PYEOF
fi

# ── graphify 그래프 자동 빌드/증분 신호 (v5.1) ─────────────
# 이슈 상태와 독립적으로 항상 평가 (아래 REGISTRY exit 분기 이전 위치).
# scaffold만 있고 graph.json 본체 없으면 초기 빌드, 변경 신호 누적 시 증분.
# 실제 빌드는 Claude Code가 graphify 스킬을 호출해 수행(셸→LLM 직접 호출 불가).
if [ -d ".claude/graphify" ]; then
  GSIG=$(bash .claude/hooks/graphify-autobuild.sh session 2>/dev/null | grep "GRAPHIFY_SIGNAL=" | cut -d= -f2)
  if [ "$GSIG" = "build" ]; then
    echo ""
    echo "🕸️  [graphify] 그래프 미생성 — 코드 수정 정확도/토큰 절감을 위해 초기 빌드 권장."
    echo "   [자동 실행 지시] /graphify . --update --no-viz 를 실행해 graph.json을 생성한 뒤 .claude/graphify/.rebuild-needed 를 삭제하라."
  elif [ "$GSIG" = "update" ]; then
    echo ""
    echo "🕸️  [graphify] 코드 변경 감지 — 그래프 증분 갱신 필요."
    echo "   [자동 실행 지시] /graphify . --update --no-viz 를 실행한 뒤 .claude/graphify/.rebuild-needed 를 삭제하라."
  fi
fi

# ── CI/CD 부재 감지 (v5.1) ─────────────────────────────────
# GitHub remote는 있으나 .github/workflows가 0개면 CI/CD gap.
# verdict를 env로 넘겨 아래 Python 블록에서 CICD_BOOTSTRAP 이슈 주입(일일 한도/중복 방지 포함).
export CICD_GAP_VERDICT="OK"
if [ -f "$SCRIPT_DIR/detect-cicd-gap.sh" ]; then
  CICD_GAP_VERDICT=$(bash "$SCRIPT_DIR/detect-cicd-gap.sh" 2>/dev/null || echo "OK")
fi
export CICD_GAP_VERDICT

if [ ! -f "$REGISTRY" ]; then
  echo "[Harness] registry.json 없음 — 'harness 시작'으로 초기화하세요."
  exit 0
fi

python3 - "$SCRIPT_DIR" << 'PYEOF'
# 구버전 이슈(assign_to 필드 없음)용 타입→담당 폴백. CLAUDE.md 에이전트 표 기준.
# 직접 인덱싱하면 KeyError로 SessionStart hook 전체가 죽는다.
TYPE_DEFAULT_AGENT = {
    "FEATURE": "product-manager", "FEATURE_PLAN": "product-manager",
    "USER_STORY": "product-manager", "EVAL": "eval-harness",
    "FIX_BUG": "agent-harness", "REFACTOR": "agent-harness",
    "GENERATE_CODE": "agent-harness", "UX_FIX": "ux-harness",
    "UI_REVIEW": "ux-harness", "RUN_TESTS": "test-harness",
    "LINT_CHECK": "code-quality",
}
import json, sys, os

__file__ = os.path.join(sys.argv[1], "session-resume.sh")
sys.path.insert(0, os.path.join(os.path.dirname(__file__),'lib'))
from issue_id import next_id

try:
    with open(".claude/issue-db/registry.json", 'r') as f:
        registry = json.load(f)
except Exception as e:
    print(f"[Harness] registry.json 읽기 실패: {e}")
    sys.exit(0)

issues = registry.get("issues", [])
stats = registry.get("stats", {})

# ── CI/CD 부재 → CICD_BOOTSTRAP 이슈 자동 주입 (v5.1) ──
# session-resume.sh 셸 영역에서 detect-cicd-gap.sh 결과를 env로 전달.
# 중복 방지: 활성(READY/IN_PROGRESS/AWAITING_USER) CICD_BOOTSTRAP 있으면 skip.
# 일일 한도: registry.cicd_bootstrap_state.last_date 로 1일 1회.
import datetime
if os.environ.get("CICD_GAP_VERDICT", "OK") == "GAP":
    active = [i for i in issues if i.get("type") == "CICD_BOOTSTRAP"
              and i.get("status") in ("READY", "IN_PROGRESS", "AWAITING_USER")]
    # 이미 워크플로를 깔았던 이력(DONE)이 있으면 재주입 안 함 (사용자가 지운 게 아닌 한)
    done_before = any(i.get("type") == "CICD_BOOTSTRAP" and i.get("status") == "DONE" for i in issues)
    cb_state = registry.setdefault("cicd_bootstrap_state", {"last_date": ""})
    today = datetime.date.today().isoformat()
    if not active and not done_before and cb_state.get("last_date") != today:
        new_id = next_id(registry)
        new_issue = {
            "id": new_id,
            "type": "CICD_BOOTSTRAP",
            "title": "CI/CD 기본 골격 부재 — GitHub Actions 워크플로 자동 생성",
            "status": "READY",
            "priority": "P1",
            "assign_to": "cicd-harness",
            "depth": 0,
            "payload": {
                "reason": "no_workflows",
                "platform": "github-actions",
                "scope": "최소 CI(lint·test·build) 워크플로 + 배포 게이트 골격 생성. 프로젝트 타입은 detect-project-type.sh로 자동 감지.",
                "created_by": "session-resume:cicd-gap"
            }
        }
        issues.append(new_issue)
        registry.setdefault("stats", {})["total_issues"] = registry["stats"].get("total_issues", 0) + 1
        cb_state["last_date"] = today
        try:
            with open(".claude/issue-db/registry.json", "w") as wf:
                json.dump(registry, wf, ensure_ascii=False, indent=2)
            print(f"\n🔧 [CI/CD] 워크플로 부재 감지 — {new_id} (CICD_BOOTSTRAP) 자동 생성. cicd-harness가 GitHub Actions 골격을 깐다.")
        except Exception as e:
            print(f"[CICD_BOOTSTRAP 주입 실패: {e}]")

if not issues:
    print("[Harness] 이슈 없음 — 'harness 시작'으로 초기화하세요.")
    sys.exit(0)

# 상태별 분류
by_status = {}
for iss in issues:
    s = iss.get("status", "UNKNOWN")
    by_status.setdefault(s, []).append(iss)

in_progress = by_status.get("IN_PROGRESS", [])
ready = by_status.get("READY", [])
done = by_status.get("DONE", [])
failed = by_status.get("FAILED", [])
escalated = by_status.get("ESCALATED", [])

# 우선순위 정렬
priority_order = {"P0": 0, "P1": 1, "P2": 2, "P3": 3}
ready.sort(key=lambda x: priority_order.get(x.get("priority", "P3"), 9))

print(f"""
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔄 Harness 세션 복원
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 전체: {len(issues)}개 | ✅ 완료: {len(done)} | 🔄 진행중: {len(in_progress)} | 📋 대기: {len(ready)} | ❌ 실패: {len(failed)} | ⚠️ 에스컬레이션: {len(escalated)}""".strip())

# IN_PROGRESS 이슈 → 즉시 재개 (질문하지 않음)
if in_progress:
    iss = in_progress[0]
    MODEL_MAP = {
        "product-manager": "opus",
        "agent-harness": "sonnet", "meta-agent": "sonnet",
        "code-quality": "sonnet",
        "test-harness": "sonnet", "eval-harness": "sonnet",
        "cicd-harness": "sonnet", "ux-harness": "sonnet",
        "qa-reviewer": "sonnet", "biz-validator": "sonnet", "scenario-player": "sonnet", "domain-analyst": "opus", "design-critic": "opus", "hook-router": "haiku",
        # v3+ 에이전트 (ISS-375) — dispatch-ready.sh MODEL_MAP과 일치
        "plan-ceo-reviewer": "fable", "plan-eng-reviewer": "opus",
        "opportunity-scout": "opus", "brand-guardian": "opus",
        "hermes": "sonnet", "advisor": "fable",
        "audience-researcher": "sonnet", "journey-validator": "sonnet",
    }
    assignee = iss.get("assign_to") or TYPE_DEFAULT_AGENT.get(iss.get("type", ""), "agent-harness")
    model = MODEL_MAP.get(assignee, "sonnet")
    print(f"\n⚠️  중단된 작업 즉시 재개:")
    print(f"  → {iss['id']} ({iss['type']}) — {iss['title']} → {assignee}")
    print(f"\n[자동 실행 지시]")
    print(f"중단된 이슈를 즉시 이어서 처리합니다. 질문하지 마라.")
    print(f"  이슈: {iss['id']} ({iss['type']})")
    print(f"  제목: {iss['title']}")
    print(f"  담당: {assignee} (model: {model})")
    print(f"  1. {assignee} 에이전트를 model={model}로 즉시 스폰")
    print(f"  2. 처리 완료 후 on_complete.sh 호출")
    sys.exit(2)  # asyncRewake

# READY 이슈 → 즉시 실행 (질문하지 않음)
if ready and not in_progress:
    print(f"\n📋 대기 중인 작업 (READY):")
    for iss in ready[:5]:
        print(f"  → {iss['id']} ({iss['type']}) [{iss.get('priority','P1')}] — {iss['title']} → {assignee}")
    if len(ready) > 5:
        print(f"  ... 외 {len(ready) - 5}개")

    # 다음 실행 대상
    next_iss = ready[0]
    MODEL_MAP = {
        "product-manager": "opus",
        "agent-harness": "sonnet", "meta-agent": "sonnet",
        "code-quality": "sonnet",
        "test-harness": "sonnet", "eval-harness": "sonnet",
        "cicd-harness": "sonnet", "ux-harness": "sonnet",
        "qa-reviewer": "sonnet", "biz-validator": "sonnet", "scenario-player": "sonnet", "domain-analyst": "opus", "design-critic": "opus", "hook-router": "haiku",
        # v3+ 에이전트 (ISS-375) — dispatch-ready.sh MODEL_MAP과 일치
        "plan-ceo-reviewer": "fable", "plan-eng-reviewer": "opus",
        "opportunity-scout": "opus", "brand-guardian": "opus",
        "hermes": "sonnet", "advisor": "fable",
        "audience-researcher": "sonnet", "journey-validator": "sonnet",
    }
    next_assignee = next_iss.get("assign_to") or TYPE_DEFAULT_AGENT.get(next_iss.get("type", ""), "agent-harness")
    model = MODEL_MAP.get(next_assignee, "sonnet")
    print(f"\n[자동 실행 지시]")
    print(f"질문하지 마라. 즉시 실행하라.")
    print(f"  이슈: {next_iss['id']} ({next_iss['type']})")
    print(f"  제목: {next_iss['title']}")
    print(f"  담당: {next_assignee} (model: {model})")
    print(f"  1. registry.json에서 {next_iss['id']}의 status를 IN_PROGRESS로 변경")
    print(f"  2. {next_assignee} 에이전트를 model={model}로 즉시 스폰")
    sys.exit(2)  # asyncRewake

if not in_progress and not ready:
    print(f"\n✅ 모든 이슈 처리 완료 — 능동 스캔 모드 진입")
    print(f"[자동 실행 지시] bash .claude/hooks/proactive-scan.sh 실행하라.")

# Knowledge 요약
knowledge = registry.get("knowledge", {})
sp = len(knowledge.get("success_patterns", []))
fp = len(knowledge.get("failure_patterns", []))
mo = len(knowledge.get("meta_observations", []))
if sp + fp + mo > 0:
    print(f"\n🧠 지식 DB: 성공패턴 {sp}개 | 실패패턴 {fp}개 | Meta관찰 {mo}개")

print(f"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
PYEOF
