#!/bin/bash
# on-agent-complete.sh — 에이전트 완료 시 자동 파이프라인 연결
# Stop hook에서 호출됨: 에이전트가 멈출 때마다 실행
#
# 흐름:
#   에이전트 작업 완료 → on_complete.sh (파생 이슈 생성)
#                     → dispatch-ready.sh (다음 이슈 자동 감지/스폰 지시)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY=".claude/issue-db/registry.json"

if [ ! -f "$REGISTRY" ]; then
  exit 0
fi

# 1. IN_PROGRESS 이슈 중 완료 처리 안 된 것이 있으면 on_complete 실행
python3 << 'PYEOF'
import json, sys

try:
    with open(".claude/issue-db/registry.json", 'r') as f:
        registry = json.load(f)
except Exception:
    sys.exit(0)

# IN_PROGRESS 상태인 이슈 찾기
in_progress = [
    iss for iss in registry.get("issues", [])
    if iss.get("status") == "IN_PROGRESS"
]

if not in_progress:
    sys.exit(0)

# IN_PROGRESS 이슈가 있으면 완료 가능 여부 확인을 위해 ID와 타입 출력
for iss in in_progress:
    print(f"IN_PROGRESS: {iss['id']} ({iss['type']}) → {iss['assign_to']}")
PYEOF

# 2. READY 이슈 디스패치 확인
bash "$SCRIPT_DIR/dispatch-ready.sh" "$REGISTRY"
