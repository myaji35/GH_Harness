#!/bin/bash
export HARNESS_HOOK_LIB="$(dirname "$(realpath "${BASH_SOURCE[0]}")")/lib"
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

python3 - "$REGISTRY" "$ISSUE_ID" "$DECISION" "$PAYLOAD_ARG" << 'PYEOF'
import sys as _sysargv
# 인자는 argv로 받는다 (heredoc 보간 = RCE 경로. 2026-07-15 감사)
_REGISTRY, _ISSUE_ID, _DECISION, _PAYLOAD_ARG = (_sysargv.argv[1:5] + ['']*4)[:4]

import json, datetime, sys
import os as _atomic_os, sys as _atomic_sys
for _atomic_lib in (_atomic_os.environ.get("HARNESS_HOOK_LIB", ""),
                    _atomic_os.path.join(_atomic_os.environ.get("HOME", ""), ".claude/harness-core/hooks/lib"),
                    _atomic_os.path.realpath(".claude/hooks/lib")):
    if _atomic_os.path.isdir(_atomic_lib) and _atomic_lib not in _atomic_sys.path:
        _atomic_sys.path.insert(0, _atomic_lib)
from registry_lock import atomic_write_json

REGISTRY_PATH = _REGISTRY
ISSUE_ID = _ISSUE_ID
DECISION = _DECISION
PAYLOAD_ARG = _PAYLOAD_ARG

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

atomic_write_json(REGISTRY_PATH, registry)
PYEOF

# 승인/수정 시 재디스패치
if [ "$DECISION" != "reject" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  bash "$SCRIPT_DIR/dispatch-ready.sh" "$REGISTRY"
  exit 2
fi

exit 0
