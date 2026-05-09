#!/bin/bash
# session-resume.sh — 새 세션 시작 시 registry.json 상태 요약
# SessionStart hook에서 호출됨
#
# 역할:
#   1. registry.json 존재 여부 확인
#   2. 전체 이슈 통계 출력
#   3. IN_PROGRESS / READY 이슈 목록 출력
#   4. 다음 실행 지시 제공

REGISTRY=".claude/issue-db/registry.json"
BRAND_DNA="brand-dna.json"

# ── 프로젝트 디자인 아젠다 자동 주입 ──
# brand-dna.json이 있으면 design_tokens + agenda를 컨텍스트에 출력
if [ -f "$BRAND_DNA" ]; then
  python3 << PYEOF
import json
try:
    with open("$BRAND_DNA", 'r') as f:
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
        print("⚠️  brand-dna.json 미초기화 — BRAND_DEFINE 이슈 자동 생성 필요")
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

if [ ! -f "$REGISTRY" ]; then
  echo "[Harness] registry.json 없음 — 'harness 시작'으로 초기화하세요."
  exit 0
fi

python3 << 'PYEOF'
import json, sys

try:
    with open(".claude/issue-db/registry.json", 'r') as f:
        registry = json.load(f)
except Exception as e:
    print(f"[Harness] registry.json 읽기 실패: {e}")
    sys.exit(0)

issues = registry.get("issues", [])
stats = registry.get("stats", {})

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
    }
    model = MODEL_MAP.get(iss.get("assign_to", ""), "sonnet")
    print(f"\n⚠️  중단된 작업 즉시 재개:")
    print(f"  → {iss['id']} ({iss['type']}) — {iss['title']} → {iss['assign_to']}")
    print(f"\n[자동 실행 지시]")
    print(f"중단된 이슈를 즉시 이어서 처리합니다. 질문하지 마라.")
    print(f"  이슈: {iss['id']} ({iss['type']})")
    print(f"  제목: {iss['title']}")
    print(f"  담당: {iss['assign_to']} (model: {model})")
    print(f"  1. {iss['assign_to']} 에이전트를 model={model}로 즉시 스폰")
    print(f"  2. 처리 완료 후 on_complete.sh 호출")
    sys.exit(2)  # asyncRewake

# READY 이슈 → 즉시 실행 (질문하지 않음)
if ready and not in_progress:
    print(f"\n📋 대기 중인 작업 (READY):")
    for iss in ready[:5]:
        print(f"  → {iss['id']} ({iss['type']}) [{iss.get('priority','P1')}] — {iss['title']} → {iss['assign_to']}")
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
    }
    model = MODEL_MAP.get(next_iss.get("assign_to", ""), "sonnet")
    print(f"\n[자동 실행 지시]")
    print(f"질문하지 마라. 즉시 실행하라.")
    print(f"  이슈: {next_iss['id']} ({next_iss['type']})")
    print(f"  제목: {next_iss['title']}")
    print(f"  담당: {next_iss['assign_to']} (model: {model})")
    print(f"  1. registry.json에서 {next_iss['id']}의 status를 IN_PROGRESS로 변경")
    print(f"  2. {next_iss['assign_to']} 에이전트를 model={model}로 즉시 스폰")
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
