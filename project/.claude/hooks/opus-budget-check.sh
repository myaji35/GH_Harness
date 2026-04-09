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
# Claude Opus 4.6 기준 (Input $15/1M, Output $75/1M)
AGENT_COST = {
    "product-manager":    0.68,
    "plan-ceo-reviewer":  0.45,
    "domain-analyst":     0.98,
    "design-critic":      0.75,
    "brand-guardian":     0.45,
    "advisor":            0.27,
    # sonnet 에이전트는 예산 대상 아님
}

# ── 강등 가능 여부 (plan-ceo-reviewer는 불가) ─────────
DEMOTABLE = {"design-critic", "domain-analyst", "brand-guardian", "advisor"}

if AGENT not in AGENT_COST:
    print("sonnet")  # opus 대상 아님
    sys.exit(0)

try:
    with open(REGISTRY_PATH, 'r') as f:
        registry = json.load(f)
except Exception:
    print("opus")
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

expected_cost = AGENT_COST[AGENT]
projected_daily = budget["daily"]["cost_usd"] + expected_cost
projected_monthly = budget["monthly"]["cost_usd"] + expected_cost

# ── Hard Cap 검사 ────────────────────────────────
if projected_daily >= HARD_CAP_DAILY or projected_monthly >= MONTHLY_CAP:
    # 강등 가능 에이전트면 sonnet으로
    if AGENT in DEMOTABLE:
        budget["demotion_active"] = True
        with open(REGISTRY_PATH, 'w') as f:
            json.dump(registry, f, indent=2, ensure_ascii=False)
        print("sonnet", flush=True)
        print(f"[opus-budget] {AGENT} 자동 강등 (예상 일일 ${projected_daily:.2f} ≥ ${HARD_CAP_DAILY})", file=sys.stderr)
        sys.exit(0)
    else:
        # 강등 불가 (plan-ceo-reviewer 등) → BLOCKED + BUDGET T2
        print("BLOCKED", flush=True)
        print(f"[opus-budget] {AGENT} 강등 불가 — Hard Cap 초과. BUDGET T2 트리거 필요", file=sys.stderr)
        sys.exit(3)

# ── Soft Cap 경고 ────────────────────────────────
if projected_daily >= SOFT_CAP_DAILY:
    print(f"[opus-budget] ⚠️ Soft Cap 근접/초과 — 예상 일일 ${projected_daily:.2f} ≥ ${SOFT_CAP_DAILY}", file=sys.stderr)

# ── 정상: opus 사용 승인 + 비용 가산 ─────────────
budget["daily"]["cost_usd"] = round(projected_daily, 4)
budget["daily"]["calls"] += 1
budget["monthly"]["cost_usd"] = round(projected_monthly, 4)
budget["monthly"]["calls"] += 1

with open(REGISTRY_PATH, 'w') as f:
    json.dump(registry, f, indent=2, ensure_ascii=False)

print("opus")
PYEOF
