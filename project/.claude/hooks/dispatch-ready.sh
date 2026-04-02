#!/bin/bash
# dispatch-ready.sh — READY 이슈를 감지하여 다음 에이전트 스폰 지시를 출력
# on_complete.sh 또는 on_fail.sh 실행 후 자동 호출됨
#
# 출력: Claude Code가 읽고 실행할 수 있는 에이전트 스폰 지시문
# exit 2 = "모델을 깨워라" (asyncRewake 호환)

REGISTRY="${1:-.claude/issue-db/registry.json}"

if [ ! -f "$REGISTRY" ]; then
  exit 0
fi

python3 << 'PYEOF'
import json, sys

registry_path = sys.argv[1] if len(sys.argv) > 1 else ".claude/issue-db/registry.json"

try:
    with open(registry_path, 'r') as f:
        registry = json.load(f)
except Exception:
    sys.exit(0)

# 에이전트 → 모델 매핑
MODEL_MAP = {
    "agent-harness":  "opus",
    "meta-agent":     "opus",
    "test-harness":   "sonnet",
    "eval-harness":   "sonnet",
    "cicd-harness":   "sonnet",
    "ux-harness":     "sonnet",
    "qa-reviewer":    "sonnet",
    "biz-validator":  "sonnet",
    "design-critic":  "opus",
    "hook-router":    "haiku",
}

# 에이전트 → 이슈 타입 매핑 (유효성 검증용)
AGENT_TYPES = {
    "agent-harness":  ["GENERATE_CODE", "REFACTOR", "FIX_BUG", "QUALITY_IMPROVEMENT"],
    "test-harness":   ["RUN_TESTS", "RETEST", "COVERAGE_CHECK", "IMPROVE_COVERAGE"],
    "eval-harness":   ["SCORE", "REGRESSION_CHECK", "COMPARE"],
    "cicd-harness":   ["DEPLOY_READY", "ROLLBACK", "PIPELINE_CHECK"],
    "ux-harness":     ["UI_REVIEW", "UX_FIX", "ACCESSIBILITY_CHECK", "RESPONSIVE_CHECK"],
    "meta-agent":     ["SYSTEMIC_ISSUE", "PATTERN_ANALYSIS", "INFRA_REVIEW", "ARCHITECTURE_REVIEW"],
}

# READY 이슈 찾기 (FIFO: 가장 오래된 것부터)
ready_issues = [
    iss for iss in registry.get("issues", [])
    if iss.get("status") == "READY"
]

if not ready_issues:
    sys.exit(0)

# 우선순위 정렬: P0 > P1 > P2 > P3
priority_order = {"P0": 0, "P1": 1, "P2": 2, "P3": 3}
ready_issues.sort(key=lambda x: (priority_order.get(x.get("priority", "P3"), 9)))

# 가장 우선순위 높은 이슈 선택
issue = ready_issues[0]
agent = issue.get("assign_to", "agent-harness")
model = MODEL_MAP.get(agent, "sonnet")
issue_id = issue.get("id", "UNKNOWN")
issue_type = issue.get("type", "UNKNOWN")
issue_title = issue.get("title", "")
payload = json.dumps(issue.get("payload", {}), ensure_ascii=False)
remaining = len(ready_issues) - 1

# 지시문 출력 — Claude Code가 이것을 읽고 즉시 실행
print(f"""
🔄 [Harness Auto-Dispatch] READY {len(ready_issues)}개 — 즉시 실행

[자동 실행 지시] 질문하지 마라. 즉시 실행하라.
- 이슈: {issue_id} ({issue_type})
- 제목: {issue_title}
- 담당: {agent} (model: {model})
- 페이로드: {payload}
- 대기 중: {remaining}개

실행 순서:
1. registry.json에서 {issue_id}의 status를 "IN_PROGRESS"로 변경
2. {agent} 에이전트를 model={model}로 즉시 스폰
3. 처리 완료 후 on_complete.sh 호출 (result JSON 포함)
""".strip())

# exit 2 = rewake signal
sys.exit(2)
PYEOF
