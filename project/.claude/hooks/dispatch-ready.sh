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
    "agent-harness":  "sonnet",
    "meta-agent":     "sonnet",
    "test-harness":   "sonnet",
    "eval-harness":   "sonnet",
    "cicd-harness":   "sonnet",
    "ux-harness":     "sonnet",
    "qa-reviewer":    "sonnet",
    "biz-validator":  "sonnet",
    "scenario-player": "sonnet",
    "domain-analyst": "opus",
    "design-critic":  "opus",
    "product-manager": "opus",
    "plan-ceo-reviewer": "opus",
    "plan-eng-reviewer": "sonnet",
    "opportunity-scout": "sonnet",
    "brand-guardian":  "sonnet",
    "code-quality":   "sonnet",
    "hook-router":    "haiku",
    "hermes":         "sonnet",
    "advisor":        "opus",
    "audience-researcher": "sonnet",
    "journey-validator": "sonnet",
}

# 에이전트 → 이슈 타입 매핑 (유효성 검증용)
AGENT_TYPES = {
    "agent-harness":  ["GENERATE_CODE", "REFACTOR", "FIX_BUG", "QUALITY_IMPROVEMENT"],
    "test-harness":   ["RUN_TESTS", "RETEST", "COVERAGE_CHECK", "IMPROVE_COVERAGE"],
    "eval-harness":   ["SCORE", "REGRESSION_CHECK", "COMPARE"],
    "cicd-harness":   ["DEPLOY_READY", "ROLLBACK", "PIPELINE_CHECK"],
    "ux-harness":     ["UI_REVIEW", "UX_FIX", "ACCESSIBILITY_CHECK", "RESPONSIVE_CHECK"],
    "meta-agent":     ["SYSTEMIC_ISSUE", "PATTERN_ANALYSIS", "INFRA_REVIEW", "ARCHITECTURE_REVIEW"],
    "code-quality":   ["LINT_CHECK", "TYPE_CHECK", "CODE_SMELL", "DEAD_CODE", "COMPLEXITY_REVIEW", "STYLE_FIX", "VIEW_AUDIT"],
    "journey-validator": ["JOURNEY_VALIDATE", "ROLE_AUDIT", "ONBOARDING_CHECK", "IMPACT_REVIEW"],
    "biz-validator":  ["BIZ_VALIDATE", "SCENARIO_GAP", "EDGE_CASE_REVIEW"],
    "domain-analyst": ["DOMAIN_ANALYZE", "RULE_EXTRACT", "SCENARIO_GENERATE"],
}

# ── 일일 이슈 생성 총량 Cap (이슈 폭발 방지) ─────────────
import datetime as _dt
today_str = _dt.date.today().isoformat()
registry.setdefault("issue_budget", {"date": today_str, "created_today": 0})
if registry["issue_budget"]["date"] != today_str:
    registry["issue_budget"] = {"date": today_str, "created_today": 0}
DAILY_ISSUE_CAP = 30  # 일일 신규 이슈 최대 30개
if registry["issue_budget"]["created_today"] >= DAILY_ISSUE_CAP:
    # 하드 캡 — 신규 스폰 대신 경고
    print(f"⚠️ [Budget] 일일 이슈 생성 cap 초과 ({registry['issue_budget']['created_today']}/{DAILY_ISSUE_CAP}). 기존 READY만 처리.")
    # cap은 생성만 막고 처리는 계속 (아래로 진행)

# READY 이슈 찾기 (FIFO: 가장 오래된 것부터)
ready_issues = [
    iss for iss in registry.get("issues", [])
    if iss.get("status") == "READY"
]

if not ready_issues:
    sys.exit(0)

# ── 백로그 과다 시 P3 이슈 처리 유보 (폭발 방지) ────────
if len(ready_issues) > 20:
    before = len(ready_issues)
    ready_issues = [i for i in ready_issues if i.get("priority", "P3") != "P3"]
    if len(ready_issues) < before:
        print(f"⚠️ [Backlog] {before}개 과다 → P3 이슈 {before - len(ready_issues)}개 유보")
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

# ── Opus 예산 체크 + 자동 강등 ─────────────────────
if model == "opus":
    import subprocess as _sp
    try:
        br = _sp.run(
            ["bash", ".claude/hooks/opus-budget-check.sh", agent],
            capture_output=True, text=True, timeout=5
        )
        budget_model = (br.stdout or "").strip().splitlines()[-1] if br.stdout else "opus"
        if br.returncode == 3 or budget_model == "BLOCKED":
            # Hard Cap + 강등 불가 → BUDGET T2 자동 트리거
            print(f"🛑 [Opus Budget] {agent} Hard Cap 초과 — BUDGET T2 컨펌 필요")
            _sp.run([
                "bash", ".claude/hooks/request-user-confirm.sh",
                issue_id, "BUDGET",
                f"{agent}(opus) 호출이 일일 Opus Hard Cap($20)을 초과합니다. "
                f"A: 오늘은 보류 / B: Hard Cap 임시 상향 / C: sonnet 강등 허용"
            ])
            sys.exit(2)
        if budget_model == "sonnet" and model == "opus":
            print(f"⚠️ [Opus Budget] {agent} opus→sonnet 자동 강등 (예산 근접)")
            model = "sonnet"
    except Exception as _e:
        pass  # 예산 체크 실패 시 기본값 유지
issue_type = issue.get("type", "UNKNOWN")
issue_title = issue.get("title", "")
payload_obj = issue.get("payload", {})
payload = json.dumps(payload_obj, ensure_ascii=False)
remaining = len(ready_issues) - 1

# ── 자동 freeze 설정 ─────────────────────────────────
# 이슈 payload에 scope_dir 있거나 files에서 공통 dir 추출 가능하면 freeze
import os
freeze_dir = payload_obj.get("scope_dir")
if not freeze_dir:
    files = payload_obj.get("files") or payload_obj.get("files_changed") or []
    if files and len(files) > 0:
        # 모든 파일의 공통 부모 디렉터리
        common = os.path.commonpath([os.path.dirname(f) or "." for f in files])
        if common and common != "." and common != "/":
            freeze_dir = common

if freeze_dir:
    try:
        with open("/tmp/harness-freeze.env", "w") as f:
            f.write(f'FREEZE_DIR="{freeze_dir}"\n')
            f.write(f'FREEZE_ISSUE="{issue_id}"\n')
        print(f"🔒 [Freeze] {freeze_dir} (이슈 {issue_id} 한정)")
    except Exception:
        pass
else:
    # freeze 해제 (이슈 범위 알 수 없음)
    try:
        if os.path.exists("/tmp/harness-freeze.env"):
            os.remove("/tmp/harness-freeze.env")
    except Exception:
        pass

# 담당이 hermes/advisor면 내부 자문 — 사용자 대기 아님
internal_note = " (내부 자문 — 사용자 대기 아님)" if agent in ("hermes", "advisor") else ""

# 지시문 출력 — Claude Code가 이것을 읽고 즉시 실행
print(f"""
🔄 [Harness Auto-Dispatch] READY {len(ready_issues)}개 — 즉시 실행

[자동 실행 지시] 질문하지 마라. 즉시 실행하라.
- 이슈: {issue_id} ({issue_type})
- 제목: {issue_title}
- 담당: {agent} (model: {model}){internal_note}
- 페이로드: {payload}
- 대기 중: {remaining}개

실행 순서:
1. registry.json에서 {issue_id}의 status를 "IN_PROGRESS"로 변경
2. {agent} 에이전트를 model={model}로 즉시 스폰
3. 처리 완료 후 on_complete.sh 호출 (result JSON 포함)

⚠️ 경고: 사소한 질문(T0)/내부 자문(T1)은 금지. T2 컨펌 대상만 request-user-confirm.sh 사용.
""".strip())

# exit 2 = rewake signal
sys.exit(2)
PYEOF
