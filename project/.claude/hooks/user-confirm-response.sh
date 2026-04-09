#!/bin/bash
# user-confirm-response.sh — 대표님의 T2 컨펌 응답 처리
#
# 사용법:
#   bash .claude/hooks/user-confirm-response.sh <이슈ID> <decision> "<payload>"
#
# decision:
#   approve  → status: AWAITING_USER → READY, user_decision 기록, 재디스패치
#   reject   → status: AWAITING_USER → CLOSED, 파생 이슈 중단, 학습 기록
#   modify   → status: AWAITING_USER → READY, user_direction 추가, 재디스패치
#
# exit 0 = 정상
# exit 2 = rewake (dispatch-ready 호출)

set -e

REGISTRY=".claude/issue-db/registry.json"
ISSUE_ID="$1"
DECISION="$2"
PAYLOAD_ARG="${3:-}"

if [ -z "$ISSUE_ID" ] || [ -z "$DECISION" ]; then
  echo "[user-confirm-response] 사용법: $0 <이슈ID> <approve|reject|modify> [payload]"
  exit 1
fi

case "$DECISION" in
  approve|reject|modify) ;;
  *)
    echo "[user-confirm-response] 유효하지 않은 decision: $DECISION (approve|reject|modify)"
    exit 1
    ;;
esac

if [ ! -f "$REGISTRY" ]; then
  echo "[user-confirm-response] registry.json 없음: $REGISTRY"
  exit 1
fi

python3 << PYEOF
import json, datetime, sys

REGISTRY_PATH = "$REGISTRY"
ISSUE_ID = "$ISSUE_ID"
DECISION = "$DECISION"
PAYLOAD_ARG = """$PAYLOAD_ARG"""

try:
    with open(REGISTRY_PATH, 'r') as f:
        registry = json.load(f)
except Exception as e:
    print(f"[user-confirm-response] registry 로딩 실패: {e}")
    sys.exit(1)

now = datetime.datetime.now().isoformat()
found = False
for iss in registry.get("issues", []):
    if iss["id"] == ISSUE_ID:
        if iss.get("status") != "AWAITING_USER":
            print(f"[user-confirm-response] {ISSUE_ID} 상태가 AWAITING_USER 아님: {iss.get('status')}")
            sys.exit(1)

        # 마지막 user_confirm 항목에 응답 기록
        if iss.get("user_confirm"):
            iss["user_confirm"][-1]["responded_at"] = now
            iss["user_confirm"][-1]["decision"] = DECISION
            iss["user_confirm"][-1]["response_payload"] = PAYLOAD_ARG

        if DECISION == "approve":
            iss["status"] = "READY"
            iss.setdefault("payload", {})["user_decision"] = PAYLOAD_ARG
            print(f"[user-confirm-response] {ISSUE_ID} 승인 → READY (선택: {PAYLOAD_ARG})")

        elif DECISION == "reject":
            iss["status"] = "CLOSED"
            iss["closed_reason"] = f"user_rejected: {PAYLOAD_ARG}"
            # meta-agent가 학습할 수 있도록 기록
            registry.setdefault("learned_patterns", []).append({
                "type": "user_rejected_t2",
                "issue_id": ISSUE_ID,
                "reason": PAYLOAD_ARG,
                "at": now
            })
            print(f"[user-confirm-response] {ISSUE_ID} 거부 → CLOSED")

        elif DECISION == "modify":
            iss["status"] = "READY"
            iss.setdefault("payload", {})["user_direction"] = PAYLOAD_ARG
            print(f"[user-confirm-response] {ISSUE_ID} 수정 지시 → READY (지시: {PAYLOAD_ARG})")

        # awaiting_since 제거
        iss.pop("awaiting_since", None)
        found = True
        break

if not found:
    print(f"[user-confirm-response] 이슈 {ISSUE_ID} 없음")
    sys.exit(1)

with open(REGISTRY_PATH, 'w') as f:
    json.dump(registry, f, indent=2, ensure_ascii=False)
PYEOF

# 승인/수정 시 재디스패치
if [ "$DECISION" != "reject" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  bash "$SCRIPT_DIR/dispatch-ready.sh" "$REGISTRY"
  exit 2
fi

exit 0
