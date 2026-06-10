#!/bin/bash
# opus-budget-check.sh — Opus 예산 상태 체크 및 자동 강등 판정
#
# 사용법:
#   bash .claude/hooks/opus-budget-check.sh <agent_name>
#
# 동작:
#   - registry.json의 opus_budget_state 조회/갱신
#   - Soft Cap 초과 시 경고 출력
#   - Hard Cap 초과 시 자동 강등 또는 T2 BUDGET 트리거
#
# 출력:
#   stdout 1줄: 실제 사용할 모델 (opus | sonnet | BLOCKED)
#   stderr: 경고/상태 메시지
#
# exit 0 = 정상 (strict budget)
# exit 3 = Hard Cap 초과 (BLOCKED — 호출 금지)

set -e

REGISTRY=".claude/issue-db/registry.json"
AGENT="$1"

if [ -z "$AGENT" ]; then
  echo "opus" # 안전 기본값
  exit 0
fi

if [ ! -f "$REGISTRY" ]; then
  echo "opus"
  exit 0
fi

python3 << PYEOF
import json, datetime, sys

REGISTRY_PATH = "$REGISTRY"
AGENT = "$AGENT"

# ── 예산 정책 (v2+ 균형) ────────────────────────────
SOFT_CAP_DAILY = 10.0
HARD_CAP_DAILY = 20.0
MONTHLY_CAP = 250.0

# ── 에이전트별 호출당 예상 비용 (USD) ────────────────
# 2026-06 가격: Opus 4.8 = $5/$25 per 1M, Fable 5 = $10/$50 per 1M
# (구버전 표는 Opus 4.6 $15/$75 기준 → 3배 과대 추정이라 교정)
AGENT_COST = {
    "product-manager":    0.23,  # opus
    "plan-ceo-reviewer":  0.30,  # fable (opus 환산 0.15 × 2)
    "domain-analyst":     0.33,  # opus
    "design-critic":      0.25,  # opus
    "brand-guardian":     0.15,  # opus
    "advisor":            0.18,  # fable (opus 환산 0.09 × 2)
    # sonnet 에이전트는 예산 대상 아님
}

# ── 에이전트별 기본 모델 티어 (미지정 시 opus) ─────────
AGENT_MODEL = {
    "plan-ceo-reviewer": "fable",
    "advisor":           "fable",
}

# ── 강등 가능 여부 ─────────────────────────────────
# fable 에이전트는 Hard Cap 시 1차로 opus 강등(비용 절반).
# plan-ceo-reviewer는 opus 밑(sonnet)으로는 강등 불가.
DEMOTABLE = {"design-critic", "domain-analyst", "brand-guardian", "advisor"}

if AGENT not in AGENT_COST:
    print("sonnet")  # opus 대상 아님
    sys.exit(0)

try:
    with open(REGISTRY_PATH, 'r') as f:
        registry = json.load(f)
except Exception:
    print(AGENT_MODEL.get(AGENT, "opus"))
    sys.exit(0)

today = datetime.date.today().isoformat()
month = today[:7]
budget = registry.setdefault("opus_budget_state", {
    "daily": {"date": today, "cost_usd": 0.0, "calls": 0},
    "monthly": {"month": month, "cost_usd": 0.0, "calls": 0},
    "demotion_active": False
})

# 일자/월 롤오버
if budget["daily"].get("date") != today:
    budget["daily"] = {"date": today, "cost_usd": 0.0, "calls": 0}
    budget["demotion_active"] = False  # 새 날 리셋
if budget["monthly"].get("month") != month:
    budget["monthly"] = {"month": month, "cost_usd": 0.0, "calls": 0}

base_model = AGENT_MODEL.get(AGENT, "opus")
expected_cost = AGENT_COST[AGENT]
projected_daily = budget["daily"]["cost_usd"] + expected_cost
projected_monthly = budget["monthly"]["cost_usd"] + expected_cost

# ── Hard Cap 검사 ────────────────────────────────
if projected_daily >= HARD_CAP_DAILY or projected_monthly >= MONTHLY_CAP:
    # 1차 강등: fable → opus (비용 절반)
    if base_model == "fable":
        half_cost = expected_cost / 2
        if budget["daily"]["cost_usd"] + half_cost < HARD_CAP_DAILY and \
           budget["monthly"]["cost_usd"] + half_cost < MONTHLY_CAP:
            budget["daily"]["cost_usd"] = round(budget["daily"]["cost_usd"] + half_cost, 4)
            budget["daily"]["calls"] += 1
            budget["monthly"]["cost_usd"] = round(budget["monthly"]["cost_usd"] + half_cost, 4)
            budget["monthly"]["calls"] += 1
            with open(REGISTRY_PATH, 'w') as f:
                json.dump(registry, f, indent=2, ensure_ascii=False)
            print("opus", flush=True)
            print(f"[opus-budget] {AGENT} fable→opus 자동 강등 (예상 일일 \${projected_daily:.2f} ≥ \${HARD_CAP_DAILY})", file=sys.stderr)
            sys.exit(0)
    # 2차 강등: 가능 에이전트면 sonnet으로
    if AGENT in DEMOTABLE:
        budget["demotion_active"] = True
        with open(REGISTRY_PATH, 'w') as f:
            json.dump(registry, f, indent=2, ensure_ascii=False)
        print("sonnet", flush=True)
        print(f"[opus-budget] {AGENT} 자동 강등 (예상 일일 \${projected_daily:.2f} ≥ \${HARD_CAP_DAILY})", file=sys.stderr)
        sys.exit(0)
    else:
        # 강등 불가 (plan-ceo-reviewer 등) → BLOCKED + BUDGET T2
        print("BLOCKED", flush=True)
        print(f"[opus-budget] {AGENT} 강등 불가 — Hard Cap 초과. BUDGET T2 트리거 필요", file=sys.stderr)
        sys.exit(3)

# ── Soft Cap 경고 ────────────────────────────────
if projected_daily >= SOFT_CAP_DAILY:
    print(f"[opus-budget] ⚠️ Soft Cap 근접/초과 — 예상 일일 \${projected_daily:.2f} ≥ \${SOFT_CAP_DAILY}", file=sys.stderr)

# ── 정상: 기본 티어(fable/opus) 사용 승인 + 비용 가산 ─────────────
budget["daily"]["cost_usd"] = round(projected_daily, 4)
budget["daily"]["calls"] += 1
budget["monthly"]["cost_usd"] = round(projected_monthly, 4)
budget["monthly"]["calls"] += 1

with open(REGISTRY_PATH, 'w') as f:
    json.dump(registry, f, indent=2, ensure_ascii=False)

print(base_model)
PYEOF
