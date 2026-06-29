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
# 2축 구조 (2026-04-16~): plan-harness/check-harness가 기본 라우팅.
# 기존 세부 에이전트는 "모드"로 병합되었으나 직접 호출도 호환 유지.
MODEL_MAP = {
    "plan-harness":   "sonnet",
    "check-harness":  "sonnet",
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
    "plan-ceo-reviewer": "fable",
    "plan-eng-reviewer": "opus",
    "opportunity-scout": "opus",
    "brand-guardian":  "opus",
    "code-quality":   "sonnet",
    "hook-router":    "haiku",
    "hermes":         "sonnet",
    "advisor":        "fable",
    "audience-researcher": "sonnet",
    "journey-validator": "sonnet",
}

# 에이전트 → 이슈 타입 매핑 (유효성 검증용)
AGENT_TYPES = {
    "agent-harness":  ["GENERATE_CODE", "REFACTOR", "FIX_BUG", "QUALITY_IMPROVEMENT"],
    "test-harness":   ["RUN_TESTS", "RETEST", "COVERAGE_CHECK", "IMPROVE_COVERAGE"],
    "eval-harness":   ["SCORE", "REGRESSION_CHECK", "COMPARE"],
    "cicd-harness":   ["DEPLOY_READY", "ROLLBACK", "PIPELINE_CHECK", "PIPELINE_OPTIMIZE", "CICD_BOOTSTRAP"],
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

# ── ID 중복 사전 점검 (ISS-201) ──────────────────────
from collections import Counter as _Counter
_id_counts = _Counter(iss.get("id") for iss in registry.get("issues", []))
_dup_ids = [k for k, v in _id_counts.items() if v > 1 and k]
if _dup_ids:
    print(f"⚠️ [Integrity] registry.json 중복 ID {len(_dup_ids)}건 감지 — registry-dedupe.py 실행 권장 (예: {', '.join(_dup_ids[:3])})")

# READY 이슈 찾기 (FIFO: 가장 오래된 것부터)
ready_issues = [
    iss for iss in registry.get("issues", [])
    if iss.get("status") == "READY"
]

if not ready_issues:
    sys.exit(0)

# ── 핑퐁 감지: (type, source_issue) 3건 이상 READY면 초과분 BLOCKED ──
# ISS-201 구조적 결함: 동일 source의 RUN_TESTS/DOMAIN_ANALYZE/SCORE가 반복 생성되어 파이프라인 정체
# ⚠️ 검증 반복 타입에만 적용. GENERATE_CODE/FEATURE_PLAN 등 고유 작업 이슈는
#    한 source(예: opportunity-scout)가 여러 개를 정당하게 만들 수 있으므로 제외.
_PINGPONG_TYPES = {"RUN_TESTS", "DOMAIN_ANALYZE", "SCORE", "LINT_CHECK",
                   "RETEST", "COVERAGE_CHECK", "REGRESSION_CHECK"}
from collections import defaultdict as _dd
_groups = _dd(list)
for _iss in ready_issues:
    if _iss.get("type", "?") not in _PINGPONG_TYPES:
        continue  # 고유 작업 이슈(GENERATE_CODE/FEATURE_PLAN 등)는 핑퐁 대상 아님
    _src = _iss.get("payload", {}).get("source_issue") or _iss.get("parent_id") or "-"
    _key = (_iss.get("type", "?"), _src)
    _groups[_key].append(_iss)

_pingpong_blocked = 0
for (_t, _s), _grp in _groups.items():
    if _s == "-":
        continue  # 원본 이슈(source 없음)는 제외
    if len(_grp) >= 3:
        # 최신 것 1개만 남기고 나머지 BLOCKED
        _grp.sort(key=lambda x: x.get("created_at", ""))
        for _dup in _grp[:-1]:
            _dup["status"] = "BLOCKED"
            _dup.setdefault("tags", []).append("pingpong_blocked")
            _dup["blocked_reason"] = f"pingpong_guard: ({_t}, src={_s}) {len(_grp)}건 중복 감지"
            _pingpong_blocked += 1
        print(f"⚠️ [Pingpong] ({_t}, src={_s}) {len(_grp)}건 → {len(_grp)-1}건 BLOCKED 처리")

if _pingpong_blocked > 0:
    # 변경사항 즉시 저장
    with open(registry_path, 'w') as _rf:
        json.dump(registry, _rf, indent=2, ensure_ascii=False)
    # ready_issues 재필터
    ready_issues = [iss for iss in registry.get("issues", []) if iss.get("status") == "READY"]
    if not ready_issues:
        print(f"[Pingpong] {_pingpong_blocked}건 차단 후 처리할 READY 없음 — 종료")
        sys.exit(0)

# ── 백로그 과다 시 P3 이슈 처리 유보 (폭발 방지) ────────
if len(ready_issues) > 20:
    before = len(ready_issues)
    ready_issues = [i for i in ready_issues if i.get("priority", "P3") != "P3"]
    if len(ready_issues) < before:
        print(f"⚠️ [Backlog] {before}개 과다 → P3 이슈 {before - len(ready_issues)}개 유보")
    if not ready_issues:
        sys.exit(0)

# 우선순위 정렬: P0 > P1 > P2 > P3, 동일 우선순위 내 실패 이슈(retry_count>0) 우선 (ISS-374, BR-014)
priority_order = {"P0": 0, "P1": 1, "P2": 2, "P3": 3}
ready_issues.sort(key=lambda x: (
    priority_order.get(x.get("priority", "P3"), 9),
    0 if x.get("retry_count", 0) > 0 else 1,   # 실패 후 재시도 이슈를 신규보다 앞에
    x.get("depth", 0),                          # 깊이 낮은(근본) 이슈 우선
))

# 가장 우선순위 높은 이슈 선택
issue = ready_issues[0]
agent = issue.get("assign_to", "agent-harness")
model = MODEL_MAP.get(agent, "sonnet")
issue_id = issue.get("id", "UNKNOWN")

# ── 상위 모델(fable/opus) 예산 체크 + 자동 강등 ─────────────────────
if model in ("opus", "fable"):
    import subprocess as _sp
    try:
        br = _sp.run(
            ["bash", ".claude/hooks/opus-budget-check.sh", agent],
            capture_output=True, text=True, timeout=5
        )
        budget_model = (br.stdout or "").strip().splitlines()[-1] if br.stdout else model
        if br.returncode == 3 or budget_model == "BLOCKED":
            # Hard Cap + 강등 불가 → BUDGET T2 자동 트리거
            print(f"🛑 [Opus Budget] {agent} Hard Cap 초과 — BUDGET T2 컨펌 필요")
            _sp.run([
                "bash", ".claude/hooks/request-user-confirm.sh",
                issue_id, "BUDGET",
                f"{agent}({model}) 호출이 일일 상위모델 Hard Cap($20)을 초과합니다. "
                f"A: 오늘은 보류 / B: Hard Cap 임시 상향 / C: 하위 모델 강등 허용"
            ])
            sys.exit(2)
        if budget_model in ("fable", "opus", "sonnet") and budget_model != model:
            print(f"⚠️ [Opus Budget] {agent} {model}→{budget_model} 자동 강등 (예산 근접)")
            model = budget_model
    except Exception as _e:
        pass  # 예산 체크 실패 시 기본값 유지
issue_type = issue.get("type", "UNKNOWN")

# ── Opus 4.8 agentic 힌트 (v5) — 단일 진실 소스 = axis-router.sh ──────────
# effort/background/isolation을 plan-harness/check-harness 모드 테이블과 정합시킨다.
# 자체 매핑 금지: route_axis_hints가 모드 테이블을 반영하므로 그것을 호출한다.
effort = "medium"; bg_hint = 0; iso_hint = 0; allowed_tools = ""
try:
    import subprocess as _spH
    _h = _spH.run(["bash", ".claude/hooks/axis-router.sh", "--hints", issue_type],
                  capture_output=True, text=True, timeout=5)
    for _kv in (_h.stdout or "").split():
        _k, _, _v = _kv.partition("=")
        if _k == "effort": effort = _v or "medium"
        elif _k == "background": bg_hint = 1 if _v == "1" else 0
        elif _k == "isolation": iso_hint = 1 if _v == "1" else 0
        elif _k == "allowed_tools": allowed_tools = _v
except Exception:
    pass
if agent == "hook-router":
    effort = "low"  # 라우팅은 항상 최소
# 예산 강등 활성 시 high→medium (code/brand/meta 모드 + plan-ceo-reviewer 제외)
_EFFORT_KEEP = {"agent-harness", "brand-guardian", "meta-agent", "plan-ceo-reviewer"}
if effort == "high" and agent not in _EFFORT_KEEP:
    try:
        _bs = json.load(open(".claude/issue-db/registry.json")).get("opus_budget_state", {})
        if _bs.get("demotion_active"):
            effort = "medium"
    except Exception:
        pass

issue_title = issue.get("title", "")
payload_obj = issue.get("payload", {})
payload = json.dumps(payload_obj, ensure_ascii=False)
remaining = len(ready_issues) - 1

# ── RACE_MODE 특별 분기 (v4.3) ─────────────────────
# 일반 에이전트 스폰이 아니라 race-dispatch.sh → race-judge.sh 파이프 실행
if issue_type == "RACE_MODE":
    providers = payload_obj.get("providers") or ["claude", "codex"]
    timeout_sec = payload_obj.get("timeout_sec", 900)
    print(f"""
🏁 [RACE_MODE] {issue_id} — provider 병렬 경쟁 시작

[자동 실행 지시] 다음 두 스크립트를 순서대로 실행하라:

1단계 (dispatch):
  bash .claude/hooks/race-dispatch.sh {issue_id}

2단계 (judge — 1단계 완료 후):
  bash .claude/hooks/race-judge.sh {issue_id}

- 제목: {issue_title}
- providers: {providers}
- timeout: {timeout_sec}s
- 판정 결과는 .claude/race-artifacts/{issue_id}/report.json 에 저장됨
- 승자 브랜치: race/{issue_id}/<winner>  — 수동 머지 또는 T2 컨펌 후 처리
""".strip())

    # Decision Trace 기록
    try:
        import subprocess as _sp3, os as _os3
        _trace = ".claude/hooks/decision-trace.sh"
        if _os3.path.exists(_trace):
            _sp3.run([
                "bash", _trace, "dispatched", issue_id,
                "agent=race", f"providers={','.join(providers)}", f"type={issue_type}"
            ], capture_output=True, timeout=3)
    except Exception:
        pass
    sys.exit(2)

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

# ── Opus 4.8 agentic 힌트 → 지시문 (v5) ──────────────
# 능동 작동하되 오버 방지: 힌트는 "권고", 최종 발동 판단은 스폰 측 + CLAUDE.md 가드레일.
agentic_note = ""

# ── background 발동조건 자동 판정 (ISS-349) ──────────
# bash hook이 직접 비동기 스폰은 불가 → "승인/거부 + 동시≤2 카운터 관리"를 담당.
# 실제 run_in_background 스폰은 스폰 측(Claude Code)이 수행.
# 조건: ① 장시간 추정(bg_hint=1) ② 대기 READY 존재(remaining≥1) ③ 동시 background ≤2
BG_MAX = 2
_bg_state = registry.setdefault("background_state", {"active": 0, "issues": []})
# stale 정리: DONE/FAILED 된 이슈는 active에서 제외
_alive = []
for _bid in _bg_state.get("issues", []):
    _bi = next((x for x in registry.get("issues", []) if x.get("id") == _bid), None)
    if _bi and _bi.get("status") in ("IN_PROGRESS", "BACKGROUND_RUNNING"):
        _alive.append(_bid)
_bg_state["issues"] = _alive
_bg_state["active"] = len(_alive)

if bg_hint or iso_hint:
    _parts = []
    if bg_hint:
        _cond2 = remaining >= 1
        _cond3 = _bg_state["active"] < BG_MAX
        if _cond2 and _cond3:
            _parts.append(f"background 승인(②대기 {remaining}개 ③동시 {_bg_state['active']}/{BG_MAX}) — "
                          f"①예상≥60초면: (a) `bash .claude/hooks/background-track.sh claim {issue_id}` 호출 "
                          f"(b) run_in_background:true로 스폰 (c) Monitor로 완료 감지 "
                          f"(d) 완료 시 `background-track.sh release {issue_id}` → on_complete 자동 진입. "
                          f"60초 미만 추정이면 동기 실행(claim 불필요)")
        else:
            _reason = ("대기 READY 없음" if not _cond2 else f"동시 background 한도 도달({_bg_state['active']}/{BG_MAX})")
            _parts.append(f"background 거부({_reason}) → 동기 실행")
    if iso_hint:
        _parts.append("isolation:worktree 권고 — 단, 2개 이상 에이전트가 동일 파일 동시 수정 시에만. 아니면 worktree 없이 실행")
    agentic_note = "\n- agentic 힌트: " + " / ".join(_parts)

# ── 헤드리스 도구잠금 (ISS-350) ──────────────────────
# HARNESS_HEADLESS=1 (비대화 자율 체인)일 때만 dontAsk + allowedTools 적용.
# 대화형 세션에는 미적용 → 대표님 개입 여지 보존. brand/PLAN축은 allowed_tools="" 라 자동 제외.
if os.environ.get("HARNESS_HEADLESS") == "1" and allowed_tools:
    agentic_note += (f"\n- 도구잠금(헤드리스): allowedTools={allowed_tools} + permissionMode=dontAsk "
                     f"→ 화이트리스트 밖 도구는 프롬프트 없이 거부. (CHECK 축 검증 전용, 쓰기 불가)")

# 지시문 출력 — Claude Code가 이것을 읽고 즉시 실행
print(f"""
🔄 [Harness Auto-Dispatch] READY {len(ready_issues)}개 — 즉시 실행

[자동 실행 지시] 질문하지 마라. 즉시 실행하라.
- 이슈: {issue_id} ({issue_type})
- 제목: {issue_title}
- 담당: {agent} (model: {model}, effort: {effort}){internal_note}{agentic_note}
- 페이로드: {payload}
- 대기 중: {remaining}개

실행 순서:
1. registry.json에서 {issue_id}의 status를 "IN_PROGRESS"로 변경
2. {agent} 에이전트를 model={model} effort={effort}로 즉시 스폰
3. 처리 완료 후 on_complete.sh 호출 (result JSON 포함)

⚠️ 경고: 사소한 질문(T0)/내부 자문(T1)은 금지. T2 컨펌 대상만 request-user-confirm.sh 사용.
""".strip())

# background_state stale 정리 결과 저장 (ISS-349)
try:
    with open(registry_path, 'w') as _bf:
        json.dump(registry, _bf, indent=2, ensure_ascii=False)
except Exception:
    pass

# [v4.1 D] Decision Trace
try:
    import subprocess as _sp2, os as _os2
    _trace = ".claude/hooks/decision-trace.sh"
    if _os2.path.exists(_trace):
        _sp2.run([
            "bash", _trace, "dispatched", issue_id,
            f"agent={agent}", f"model={model}", f"effort={effort}", f"type={issue_type}", f"priority={issue.get('priority','?')}"
        ], capture_output=True, timeout=3)
except Exception:
    pass

# exit 2 = rewake signal
sys.exit(2)
PYEOF
