#!/bin/bash
# request-user-confirm.sh — T2 컨펌 요청 표준 출력
#
# 사용법:
#   bash .claude/hooks/request-user-confirm.sh <이슈ID> <카테고리> "<결정 질문 + 선택지>"
#
# 카테고리: EXTERNAL | DIRECTION | BUDGET | SECURITY | EXPLICIT
#
# 동작:
#   1. 이슈 status → AWAITING_USER
#   2. user_confirm 이력 기록
#   3. 표준 출력 포맷으로 대표님께 알림
#   4. 해당 이슈만 멈춤. 다른 READY 이슈는 계속 처리 가능
#
# exit 0 = 정상 요청
# exit 1 = 입력 오류

set -e

REGISTRY=".claude/issue-db/registry.json"
ISSUE_ID="$1"
CATEGORY="$2"
QUESTION="$3"

if [ -z "$ISSUE_ID" ] || [ -z "$CATEGORY" ] || [ -z "$QUESTION" ]; then
  echo "[request-user-confirm] 사용법: $0 <이슈ID> <카테고리> <결정 질문>"
  echo "  카테고리: EXTERNAL | DIRECTION | BUDGET | SECURITY | EXPLICIT"
  exit 1
fi

# 카테고리 검증
case "$CATEGORY" in
  EXTERNAL|DIRECTION|BUDGET|SECURITY|EXPLICIT) ;;
  *)
    echo "[request-user-confirm] 유효하지 않은 카테고리: $CATEGORY"
    echo "  허용: EXTERNAL | DIRECTION | BUDGET | SECURITY | EXPLICIT"
    exit 1
    ;;
esac

if [ ! -f "$REGISTRY" ]; then
  echo "[request-user-confirm] registry.json 없음: $REGISTRY"
  exit 1
fi

python3 << PYEOF
import json, datetime, sys

REGISTRY_PATH = "$REGISTRY"
ISSUE_ID = "$ISSUE_ID"
CATEGORY = "$CATEGORY"
QUESTION = """$QUESTION"""

try:
    with open(REGISTRY_PATH, 'r') as f:
        registry = json.load(f)
except Exception as e:
    print(f"[request-user-confirm] registry 로딩 실패: {e}")
    sys.exit(1)

now = datetime.datetime.now().isoformat()
found = False
for iss in registry.get("issues", []):
    if iss["id"] == ISSUE_ID:
        iss["status"] = "AWAITING_USER"
        iss["awaiting_since"] = now
        iss.setdefault("user_confirm", []).append({
            "category": CATEGORY,
            "question": QUESTION,
            "asked_at": now
        })
        found = True
        break

if not found:
    print(f"[request-user-confirm] 이슈 {ISSUE_ID} 없음")
    sys.exit(1)

with open(REGISTRY_PATH, 'w') as f:
    json.dump(registry, f, indent=2, ensure_ascii=False)

print(f"[request-user-confirm] {ISSUE_ID} → AWAITING_USER")
PYEOF

# 표준 컨펌 출력 (대표님 눈에 띄게)
cat <<EOF

🛑 [T2 컨펌 요청] $ISSUE_ID
카테고리: $CATEGORY
결정 필요:
$QUESTION

상태 → AWAITING_USER. 대표님 답변 전까지 이 이슈 진행 중단.
다른 READY 이슈는 계속 처리됩니다.

답변 방법:
  - 승인: bash .claude/hooks/user-confirm-response.sh $ISSUE_ID approve "선택값"
  - 거부: bash .claude/hooks/user-confirm-response.sh $ISSUE_ID reject "이유"
  - 수정: bash .claude/hooks/user-confirm-response.sh $ISSUE_ID modify "새 지시"
EOF

exit 0
