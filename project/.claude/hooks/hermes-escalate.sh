#!/bin/bash
# hermes-escalate.sh — executor 에이전트의 막힘 신호를 Hermes로 에스컬레이션
#
# 사용법:
#   bash .claude/hooks/hermes-escalate.sh <executor_issue_id> <reason_code> [context_hint]
#
# reason_code:
#   REPEAT_FAIL | ARCH_DECISION | AMBIGUOUS_PAYLOAD | UNKNOWN_ERROR |
#   SCOPE_CONFLICT | CROSS_AGENT_PINGPONG
#
# 동작:
#   1. Circuit Breaker 검사 (이슈당 3회 / 일일 20회 / 일일 $5 cap)
#   2. 초과 시 → meta-agent에 SYSTEMIC_ISSUE 생성 후 종료
#   3. 통과 시 → HERMES_CONSULT 이슈 생성, hermes 에이전트로 디스패치
#
# exit 0 = 정상 에스컬레이션
# exit 2 = rewake (dispatch-ready 호출 유도)
# exit 3 = Circuit Breaker 초과 (meta-agent 인계)

set -e

REGISTRY=".claude/issue-db/registry.json"
EXECUTOR_ISSUE_ID="$1"
REASON_CODE="$2"
CONTEXT_HINT="${3:-}"

if [ -z "$EXECUTOR_ISSUE_ID" ] || [ -z "$REASON_CODE" ]; then
  echo "[hermes-escalate] 사용법: $0 <executor_issue_id> <reason_code> [context_hint]"
  exit 1
fi

# 유효한 reason_code 검증
case "$REASON_CODE" in
  REPEAT_FAIL|ARCH_DECISION|AMBIGUOUS_PAYLOAD|UNKNOWN_ERROR|SCOPE_CONFLICT|CROSS_AGENT_PINGPONG) ;;
  *)
    echo "[hermes-escalate] 유효하지 않은 reason_code: $REASON_CODE"
    exit 1
    ;;
esac

if [ ! -f "$REGISTRY" ]; then
  echo "[hermes-escalate] registry.json 없음: $REGISTRY"
  exit 1
fi

echo "[hermes-escalate] 이슈=$EXECUTOR_ISSUE_ID reason=$REASON_CODE"

python3 << PYEOF
import json, datetime, sys, os

REGISTRY_PATH = "$REGISTRY"
EXECUTOR_ID = "$EXECUTOR_ISSUE_ID"
REASON = "$REASON_CODE"
CONTEXT_HINT = "$CONTEXT_HINT"

# Circuit Breaker 임계치
MAX_PER_ISSUE = 3        # 이슈당 Hermes 호출 제한
MAX_PER_DAY = 20         # 일일 전체 호출 제한
MAX_COST_USD_PER_DAY = 5.0  # 일일 비용 cap

try:
    with open(REGISTRY_PATH, 'r') as f:
        registry = json.load(f)
except Exception as e:
    print(f"[hermes-escalate] registry 로딩 실패: {e}")
    sys.exit(1)

# hermes 상태 초기화 (최초 1회)
if "hermes_state" not in registry:
    registry["hermes_state"] = {
        "invocations_by_issue": {},  # { "ISS-042": 2, ... }
        "daily_log": [],              # [{date, count, cost_usd}]
        "total_invocations": 0
    }

hs = registry["hermes_state"]
today = datetime.date.today().isoformat()

# 오늘자 로그 찾거나 생성
today_entry = next((e for e in hs["daily_log"] if e["date"] == today), None)
if not today_entry:
    today_entry = {"date": today, "count": 0, "cost_usd": 0.0}
    hs["daily_log"].append(today_entry)
    # 7일 이전 로그 정리
    cutoff = (datetime.date.today() - datetime.timedelta(days=7)).isoformat()
    hs["daily_log"] = [e for e in hs["daily_log"] if e["date"] >= cutoff]

# ── Circuit Breaker 검사 ────────────────────────────────
this_issue_count = hs["invocations_by_issue"].get(EXECUTOR_ID, 0)
daily_count = today_entry["count"]
daily_cost = today_entry["cost_usd"]

breaker_reason = None
if this_issue_count >= MAX_PER_ISSUE:
    breaker_reason = f"이슈당 제한 초과 ({this_issue_count}/{MAX_PER_ISSUE})"
elif daily_count >= MAX_PER_DAY:
    breaker_reason = f"일일 호출 제한 초과 ({daily_count}/{MAX_PER_DAY})"
elif daily_cost >= MAX_COST_USD_PER_DAY:
    breaker_reason = f"일일 비용 제한 초과 (\${daily_cost:.2f}/\${MAX_COST_USD_PER_DAY})"

# ── SCOPE_CONFLICT 연속 재발 감지 (무한 루프 조기 차단) ──
if REASON == "SCOPE_CONFLICT" and not breaker_reason:
    # 해당 이슈의 기존 HERMES_CONSULT 중 SCOPE_CONFLICT 수 확인
    prior_scope_conflicts = 0
    for existing in registry.get("issues", []):
        if existing.get("parent_id") == EXECUTOR_ID and \
           existing.get("type") == "HERMES_CONSULT" and \
           existing.get("payload", {}).get("reason_code") == "SCOPE_CONFLICT":
            prior_scope_conflicts += 1
    if prior_scope_conflicts >= 1:  # 2회차부터 즉시 승격 (Circuit 기다리지 않음)
        breaker_reason = f"SCOPE_CONFLICT 연속 재발 ({prior_scope_conflicts + 1}회차) — freeze 확장이 효과 없음"

if breaker_reason:
    # Circuit Breaker 발동 → meta-agent로 승격
    next_id = f"ISS-{registry['stats']['total_issues'] + 1:03d}"
    escalation = {
        "id": next_id,
        "title": f"[Hermes Circuit Break] {EXECUTOR_ID} — {breaker_reason}",
        "type": "SYSTEMIC_ISSUE",
        "status": "READY",
        "priority": "P0",
        "assign_to": "meta-agent",
        "depth": 1,
        "retry_count": 0,
        "parent_id": EXECUTOR_ID,
        "depends_on": [],
        "created_at": datetime.datetime.now().isoformat(),
        "payload": {
            "origin": "hermes_circuit_breaker",
            "executor_issue": EXECUTOR_ID,
            "reason_code": REASON,
            "breaker_reason": breaker_reason,
            "this_issue_count": this_issue_count,
            "daily_count": daily_count,
            "daily_cost_usd": daily_cost,
            "context_hint": CONTEXT_HINT
        },
        "result": None,
        "spawn_rules": []
    }
    registry["issues"].append(escalation)
    registry["stats"]["total_issues"] += 1

    with open(REGISTRY_PATH, 'w') as f:
        json.dump(registry, f, indent=2, ensure_ascii=False)

    print(f"[Circuit Breaker] {breaker_reason}")
    print(f"[Circuit Breaker] → {next_id} SYSTEMIC_ISSUE 생성 (meta-agent로 인계)")
    sys.exit(3)

# ── 통과: HERMES_CONSULT 이슈 생성 ──────────────────────
next_id = f"ISS-{registry['stats']['total_issues'] + 1:03d}"
consult_issue = {
    "id": next_id,
    "title": f"[Hermes 자문] {EXECUTOR_ID} — {REASON}",
    "type": "HERMES_CONSULT",
    "status": "READY",
    "priority": "P0",  # 막힘 해소가 최우선
    "assign_to": "hermes",
    "depth": 1,
    "retry_count": 0,
    "parent_id": EXECUTOR_ID,
    "depends_on": [],
    "created_at": datetime.datetime.now().isoformat(),
    "payload": {
        "executor_issue": EXECUTOR_ID,
        "reason_code": REASON,
        "context_hint": CONTEXT_HINT,
        "circuit_state": {
            "this_issue_count": this_issue_count,
            "daily_count": daily_count,
            "daily_cost_usd": daily_cost
        }
    },
    "result": None,
    "spawn_rules": []
}
registry["issues"].append(consult_issue)
registry["stats"]["total_issues"] += 1

# 카운터 증가
hs["invocations_by_issue"][EXECUTOR_ID] = this_issue_count + 1
today_entry["count"] = daily_count + 1
hs["total_invocations"] += 1

# 실제 비용은 Hermes가 완료 후 업데이트. 여기선 예상치로 +0.05 USD 가산
today_entry["cost_usd"] = round(daily_cost + 0.05, 4)

# executor 이슈에 hermes_invocations 필드 추가
for iss in registry["issues"]:
    if iss["id"] == EXECUTOR_ID:
        iss.setdefault("hermes_invocations", 0)
        iss["hermes_invocations"] += 1
        iss.setdefault("hermes_consults", []).append(next_id)
        break

with open(REGISTRY_PATH, 'w') as f:
    json.dump(registry, f, indent=2, ensure_ascii=False)

# ── Mutex Lock 파일 생성 (meta-agent 레이스 방어) ───
lock_path = f"/tmp/harness-hermes-{EXECUTOR_ID}.lock"
try:
    with open(lock_path, 'w') as _lf:
        _lf.write(f"issue={EXECUTOR_ID}\n")
        _lf.write(f"consult={next_id}\n")
        _lf.write(f"reason={REASON}\n")
        _lf.write(f"started_at={datetime.datetime.now().isoformat()}\n")
except Exception:
    pass

print(f"[hermes-escalate] {next_id} HERMES_CONSULT 생성 (이슈당 {this_issue_count+1}/{MAX_PER_ISSUE}, 일일 {daily_count+1}/{MAX_PER_DAY})")
print(f"[hermes-escalate] Lock: {lock_path}")
PYEOF

HERMES_EXIT=$?

if [ $HERMES_EXIT -eq 3 ]; then
  # Circuit Breaker 발동 → dispatch 호출 (meta-agent 스폰)
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  bash "$SCRIPT_DIR/dispatch-ready.sh" "$REGISTRY"
  exit 3
fi

# 정상: dispatch 호출 (hermes 스폰)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$SCRIPT_DIR/dispatch-ready.sh" "$REGISTRY"
exit 2
