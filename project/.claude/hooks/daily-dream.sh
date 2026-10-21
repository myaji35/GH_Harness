#!/usr/bin/env bash
export HARNESS_HOOK_LIB="$(dirname "$(realpath "${BASH_SOURCE[0]}")")/lib"
# ============================================================
# daily-dream.sh — Anthropic Dreaming 컨셉 기반 학습 증류 스크립트
# 유휴 시간에 최근 7일 이슈를 복기하며 성공/실패 패턴을 증류한다.
#
# 사용법:
#   bash daily-dream.sh [--dry-run]
#
# 출력:
#   .claude/knowledge-db/success_patterns.json  (증분 갱신)
#   .claude/knowledge-db/failure_patterns.json  (증분 갱신)
#   registry.json knowledge.success_patterns / failure_patterns (증분 갱신)
#   .claude/knowledge-db/.dream.log
#
# 요구 사항:
#   - python3  (필수 — 통계 fallback 경로)
#   - jq       (선택적 — 없으면 python3 대체)
#   - claude   (선택적 — OPUS_BUDGET_OK=1 일 때만 enrichment 호출)
# ============================================================

set -euo pipefail

# ── 경로 설정 ────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -n "${CLAUDE_PROJECT_DIR:-}" && -d "${CLAUDE_PROJECT_DIR:-}/.claude" ]]; then
  PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-}"
elif [[ -d "$PWD/.claude" ]]; then
  PROJECT_ROOT="$PWD"
else
  PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi
CLAUDE_DIR="$PROJECT_ROOT/.claude"
REGISTRY="$CLAUDE_DIR/issue-db/registry.json"
KNOWLEDGE_DIR="$CLAUDE_DIR/knowledge-db"
SUCCESS_FILE="$KNOWLEDGE_DIR/success_patterns.json"
FAILURE_FILE="$KNOWLEDGE_DIR/failure_patterns.json"
LOG_FILE="$KNOWLEDGE_DIR/.dream.log"

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=1
fi

# ── 로그 헬퍼 ────────────────────────────────────────────────
log() {
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  echo "[$ts] $*" | tee -a "$LOG_FILE"
}

# ── 디렉터리 보장 ─────────────────────────────────────────────
mkdir -p "$KNOWLEDGE_DIR"

log "====== daily-dream START (dry_run=$DRY_RUN) ======"

# ── 필수 파일 존재 확인 ───────────────────────────────────────
if [[ ! -f "$REGISTRY" ]]; then
  log "ERROR: registry.json not found at $REGISTRY"
  exit 1
fi

# ── knowledge DB 초기화 (없으면 생성) ───────────────────────
init_json_if_missing() {
  local file="$1"
  local key="$2"    # success_patterns | failure_patterns
  if [[ ! -f "$file" ]]; then
    cat > "$file" <<EOF
{
  "_schema_version": "1.0",
  "_description": "Daily Dream 학습 증류",
  "_last_updated": null,
  "$key": []
}
EOF
    log "Initialized $file"
  fi
}
init_json_if_missing "$SUCCESS_FILE" "success_patterns"
init_json_if_missing "$FAILURE_FILE" "failure_patterns"

# ── 통계 기반 패턴 추출 (Python3 — LLM 없는 fallback 경로) ──
PYTHON_SCRIPT=$(cat <<'PYEOF'
import json, sys, datetime, os, re
import os as _atomic_os, sys as _atomic_sys
for _atomic_lib in (_atomic_os.environ.get("HARNESS_HOOK_LIB", ""),
                    _atomic_os.path.join(_atomic_os.environ.get("HOME", ""), ".claude/harness-core/hooks/lib"),
                    _atomic_os.path.realpath(".claude/hooks/lib")):
    if _atomic_os.path.isdir(_atomic_lib) and _atomic_lib not in _atomic_sys.path:
        _atomic_sys.path.insert(0, _atomic_lib)
from registry_lock import atomic_write_json

registry_path = sys.argv[1]
success_path  = sys.argv[2]
failure_path  = sys.argv[3]
dry_run       = sys.argv[4] == "1"
now_iso       = datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")

# 7일 컷오프
cutoff = datetime.datetime.utcnow() - datetime.timedelta(days=7)

# ── 데이터 로드 ──────────────────────────────────────────────
with open(registry_path) as f:
    reg = json.load(f)

def load_patterns(path, key):
    try:
        with open(path) as f:
            d = json.load(f)
        return d.get(key, [])
    except Exception:
        return []

success_patterns = load_patterns(success_path, "success_patterns")
failure_patterns = load_patterns(failure_path, "failure_patterns")

issues = reg.get("issues", [])

# ── 최근 이슈 필터링 ─────────────────────────────────────────
# 상태 이름은 프로젝트·시기마다 다르다(COMPLETED → DONE 전환 등). 이름 하나만 세면
# 완료·실패가 0건으로 집계돼 학습이 멈춘다(ISS-714).
DONE_STATUSES = {"DONE", "COMPLETED", "CLOSED_DONE", "RESOLVED", "VERIFIED",
                 "CLOSED_FIXED", "CLOSED_SUCCESS", "CLOSED_RESOLVED"}
FAILED_STATUSES = {"FAILED", "ESCALATED", "CLOSED_BLOCKED", "BLOCKED",
                   "DONE_PARTIAL", "PARTIAL", "PARTIAL_DONE"}
# 다른 이슈의 결과물을 고치려고 파생된 이슈 — 원 이슈가 한 번에 끝나지 않았다는 신호
FIX_TYPES = {"FIX_BUG", "STYLE_FIX", "BIZ_FIX", "UX_FIX", "DESIGN_FIX",
             "SCENARIO_FIX", "QUALITY_IMPROVEMENT"}
# 실패 신호는 드물어서 7일로는 반복이 안 보인다
fail_cutoff = datetime.datetime.utcnow() - datetime.timedelta(days=30)

def ts_of(iss):
    ts_str = (iss.get("completed_at") or iss.get("closed_at")
              or iss.get("updated_at") or iss.get("created_at") or "")
    try:
        return datetime.datetime.strptime(str(ts_str)[:19], "%Y-%m-%dT%H:%M:%S")
    except Exception:
        return None

def as_dict(v):
    return v if isinstance(v, dict) else {}

recent, recent_fail = [], []
for iss in issues:
    ts = ts_of(iss)
    if ts is None:
        continue
    if ts >= cutoff:
        recent.append(iss)
    if ts >= fail_cutoff:
        recent_fail.append(iss)

completed = [i for i in recent if i.get("status") in DONE_STATUSES]
failed    = [i for i in recent_fail if i.get("status") in FAILED_STATUSES]

print(f"[stats] recent_7d={len(recent)} completed={len(completed)} "
      f"recent_30d={len(recent_fail)} failed={len(failed)}", flush=True)

# ── 휴리스틱 패턴 도출 함수 ──────────────────────────────────
def find_or_create(patterns_list, pattern_str):
    for p in patterns_list:
        if p.get("pattern") == pattern_str:
            return p
    return None

# frequency 는 근거 이슈 수다. 같은 근거로 매일 다시 돌려도 늘지 않는다.
def merge_success(patterns, pattern_str, evidence_id, now):
    existing = find_or_create(patterns, pattern_str)
    if existing:
        existing["last_seen"] = now
        if evidence_id not in existing.get("evidence_issues", []):
            existing.setdefault("evidence_issues", []).append(evidence_id)
        existing["frequency"] = len(existing["evidence_issues"])
    else:
        patterns.append({
            "pattern": pattern_str,
            "evidence_issues": [evidence_id],
            "frequency": 1,
            "first_seen": now,
            "last_seen": now
        })

def merge_failure(patterns, pattern_str, evidence_id, now, hint="", issue_type=None):
    existing = find_or_create(patterns, pattern_str)
    if existing:
        existing["last_seen"] = now
        if evidence_id not in existing.get("evidence_issues", []):
            existing.setdefault("evidence_issues", []).append(evidence_id)
        existing["frequency"] = len(existing["evidence_issues"])
    else:
        existing = {
            "pattern": pattern_str,
            "evidence_issues": [evidence_id],
            "frequency": 1,
            "root_cause_hint": hint,
            "incident_doc_ref": None,
            "first_seen": now,
            "last_seen": now
        }
        patterns.append(existing)
    if issue_type:
        existing["issue_type"] = issue_type

# ── 성공 패턴 도출 ────────────────────────────────────────────
# 패턴 1: REFACTOR + scope_dir 명시 → 완료
refactor_completed = [i for i in completed if i.get("type") == "REFACTOR"
                      and as_dict(i.get("payload")).get("scope_dir")]
if refactor_completed:
    pstr = "REFACTOR + scope_dir 명시 → COMPLETED (범위 한정 리팩토링 성공률 높음)"
    for iss in refactor_completed:
        merge_success(success_patterns, pstr, iss["id"], now_iso)

# 패턴 2: rubric 4/4 충족 이슈 (rubric_score == "4/4")
rubric_full = [i for i in completed
               if str(as_dict(i.get("result")).get("rubric_score","")) == "4/4"]
if rubric_full:
    pstr = "rubric 4/4 충족 이슈는 100% COMPLETED (명시적 성공 기준 효과)"
    for iss in rubric_full:
        merge_success(success_patterns, pstr, iss["id"], now_iso)

# 패턴 3: blocked_by 해소 후 즉시 완료 (깊이 0)
depth0_completed = [i for i in completed
                    if i.get("depth", 0) == 0
                    and as_dict(i.get("payload")).get("blocked_by")]
if depth0_completed:
    pstr = "blocked_by 의존성 해소 후 depth-0 이슈 즉시 COMPLETED"
    for iss in depth0_completed:
        merge_success(success_patterns, pstr, iss["id"], now_iso)

# 패턴 4: P0 이슈 완료 (긴급도 대응 성공)
p0_completed = [i for i in completed if i.get("priority") == "P0"]
if p0_completed:
    pstr = "P0 우선순위 이슈 신속 완료 (긴급 대응 체계 작동)"
    for iss in p0_completed:
        merge_success(success_patterns, pstr, iss["id"], now_iso)

# 패턴 5: 배치 일괄 주입 패턴 (REFACTOR + injected_count 존재)
batch_inject = [i for i in completed
                if i.get("type") == "REFACTOR"
                and "injected_count" in as_dict(i.get("result"))]
if batch_inject:
    pstr = "배치 일괄 주입(injected_count 필드) 패턴 — 반복 수정보다 일괄 처리가 효율적"
    for iss in batch_inject:
        merge_success(success_patterns, pstr, iss["id"], now_iso)

# 패턴 6: 에이전트별 성공 집계 (agent/assign_to 명시된 경우만)
agent_success = {}
for iss in completed:
    agent = iss.get("agent") or iss.get("assign_to")
    if not agent:
        continue
    agent_success.setdefault(agent, []).append(iss["id"])
# 예전에는 건수를 문구에 넣어 건수가 바뀔 때마다 같은 패턴이 새로 쌓였다 — 하나로 합친다
_agent_pat = re.compile(r"^에이전트 '(.+)' 완료율 높음 \(\d+건 COMPLETED\)$")
_merged = []
for p in success_patterns:
    m = _agent_pat.match(p.get("pattern", ""))
    if m:
        p = dict(p, pattern=f"에이전트 '{m.group(1)}' 완료율 높음")
    same = find_or_create(_merged, p["pattern"])
    if same:
        for e in p.get("evidence_issues", []):
            if e not in same.setdefault("evidence_issues", []):
                same["evidence_issues"].append(e)
        same["frequency"] = len(same["evidence_issues"])
        same["last_seen"] = max(str(same.get("last_seen") or ""), str(p.get("last_seen") or "")) or None
    else:
        _merged.append(p)
success_patterns[:] = _merged
for agent, ids in agent_success.items():
    if len(ids) >= 2:
        pstr = f"에이전트 '{agent}' 완료율 높음"
        for iid in ids:
            merge_success(success_patterns, pstr, iid, now_iso)

# ── 실패 패턴 도출 ────────────────────────────────────────────
# 패턴 문자열·힌트는 여기 정한 문구만 쓴다. 이슈 제목·사유 같은 자유 텍스트는
# 공장 프롬프트에 그대로 주입되므로 넣지 않는다(사용자 피드백 원문 유입 차단).
def by_type(items):
    groups = {}
    for iss in items:
        groups.setdefault(iss.get("type") or "UNKNOWN", []).append(iss)
    return groups

# 패턴 F1: depth 3 이슈 실패 경향
depth3_failed = [i for i in failed if i.get("depth", 0) >= 3]
if depth3_failed:
    pstr = "depth 3 이상 이슈 실패율 증가 — 의존성 깊이 초과"
    for iss in depth3_failed:
        merge_failure(failure_patterns, pstr, iss["id"], now_iso,
                      "이슈 분해 깊이 초과. 루트 이슈로 재설계 필요")

# 패턴 F2: 특정 에이전트 반복 실패 (agent/assign_to 명시된 경우만)
agent_fail = {}
for iss in failed:
    agent = iss.get("agent") or iss.get("assign_to")
    if not agent or agent == "none":
        continue
    agent_fail.setdefault(agent, []).append(iss["id"])
for agent, ids in agent_fail.items():
    if len(ids) >= 2:
        pstr = f"에이전트 '{agent}' 반복 실패"
        for iid in ids:
            merge_failure(failure_patterns, pstr, iid, now_iso,
                          f"에이전트 프롬프트 또는 이슈 스펙 점검 필요 (에이전트: {agent})")

# 패턴 F3: scope_dir 미명시 실패
no_scope_failed = [i for i in failed
                   if not as_dict(i.get("payload")).get("scope_dir")]
if len(no_scope_failed) >= 2:
    pstr = "scope_dir 미명시 이슈 → 실패율 증가"
    for iss in no_scope_failed:
        merge_failure(failure_patterns, pstr, iss["id"], now_iso,
                      "이슈 생성 시 scope_dir 필드 필수 명시 필요")

# 패턴 F4: 유형별 막힘·중단 반복
for itype, items in by_type(failed).items():
    if len(items) >= 2:
        pstr = f"{itype} 이슈가 막힘·중단으로 끝남"
        for iss in items:
            merge_failure(failure_patterns, pstr, iss["id"], now_iso,
                          "착수 전 선행 조건(권한·외부 상태·의존 카드)을 먼저 확인하고, 막히면 이유를 남겨라",
                          itype)

# 패턴 F5: 유형별 재시도 반복 (on_fail 이 retry_count 를 올린다)
retried = [i for i in recent_fail if (i.get("retry_count") or 0) > 0]
for itype, items in by_type(retried).items():
    if len(items) >= 2:
        pstr = f"{itype} 이슈가 첫 시도에 실패해 재시도됨"
        for iss in items:
            merge_failure(failure_patterns, pstr, iss["id"], now_iso,
                          "첫 시도 전에 실패 원인이 됐던 검증(테스트·빌드)을 직접 돌려 보고 마감하라",
                          itype)

# 패턴 F6: 완료 후 후속 수정 파생 (재작업) — 근거는 원 이슈
by_id = {i.get("id"): i for i in issues}
rework = {}
for fix in recent_fail:
    if fix.get("type") not in FIX_TYPES:
        continue
    src = by_id.get(as_dict(fix.get("payload")).get("source_issue"))
    if not src or src.get("type") in FIX_TYPES:
        continue
    rework.setdefault((src.get("type") or "UNKNOWN", fix.get("type")), []).append(src)
for (stype, ftype), srcs in rework.items():
    ids = sorted({s["id"] for s in srcs})
    if len(ids) >= 2:
        pstr = f"{stype} 완료 뒤 {ftype} 후속 수정이 파생됨 (한 번에 안 끝남)"
        for iid in ids:
            merge_failure(failure_patterns, pstr, iid, now_iso,
                          f"마감 전에 {ftype} 검사가 잡던 문제(테스트·린트·화면)를 먼저 확인하라",
                          stype)

# 패턴 F7: 실행 증거 없이 완료 시도 (prove-it-works 거부 기록)
proof_log = os.path.join(os.path.dirname(failure_path), "proof-metrics.jsonl")
proof_rejects = {}
try:
    with open(proof_log) as f:
        for line in f:
            try:
                rec = json.loads(line)
            except Exception:
                continue
            # rejected = 증거 없음, criteria-rejected = 완료 조건 없음·미충족 (ok/warn 류는 실패 아님)
            if rec.get("outcome") not in ("rejected", "criteria-rejected") or not rec.get("issue"):
                continue
            try:
                rts = datetime.datetime.strptime(str(rec.get("ts", ""))[:19], "%Y-%m-%dT%H:%M:%S")
            except Exception:
                continue
            if rts >= fail_cutoff:
                proof_rejects.setdefault((rec.get("type") or "UNKNOWN", rec["outcome"]), set()).add(rec["issue"])
except FileNotFoundError:
    pass
for (itype, outcome), ids in proof_rejects.items():
    if outcome == "criteria-rejected":
        pstr = f"{itype} 이슈를 완료 조건 없이 또는 미충족 상태로 마감하려다 거부됨"
        hint = "착수 전에 payload.acceptance_criteria 를 적고, 마감 때 기준마다 criteria_check 로 확인하라"
    else:
        pstr = f"{itype} 이슈를 실행 증거(proof) 없이 마감하려다 거부됨"
        hint = "on_complete 전에 실제로 실행한 명령·exit code·출력 발췌를 result.proof 에 넣어라"
    for iid in sorted(ids):
        merge_failure(failure_patterns, pstr, iid, now_iso, hint, itype)

# 패턴 F8: 지시 분류 게이트가 만든 이슈가 무효 처리됨 (오분류)
gate_invalid = [i for i in recent_fail if i.get("status") == "CLOSED_INVALID"
                and str(as_dict(i.get("payload")).get("origin", "")).startswith("intent-gate")]
if len(gate_invalid) >= 3:
    pstr = "지시 분류 게이트가 작업이 아닌 발화로 이슈를 만들어 무효 처리됨"
    for iss in gate_invalid:
        merge_failure(failure_patterns, pstr, iss["id"], now_iso,
                      "intent-gate 분류 규칙(의견·질문형 판정) 점검 필요")

# ── dry-run: 출력만, 파일 미변경 ─────────────────────────────
if dry_run:
    print("=== [DRY-RUN] success_patterns ===")
    print(json.dumps(success_patterns, ensure_ascii=False, indent=2))
    print("=== [DRY-RUN] failure_patterns ===")
    print(json.dumps(failure_patterns, ensure_ascii=False, indent=2))
    sys.exit(0)

# ── 파일 갱신 ────────────────────────────────────────────────
def save_patterns(path, key, patterns):
    try:
        with open(path) as f:
            d = json.load(f)
    except Exception:
        d = {}
    d["_last_updated"] = now_iso
    d[key] = patterns
    atomic_write_json(path, d)

save_patterns(success_path, "success_patterns", success_patterns)
save_patterns(failure_path, "failure_patterns", failure_patterns)

# ── registry.json knowledge 필드 증분 갱신 ───────────────────
knowledge = reg.setdefault("knowledge", {})
knowledge["success_patterns"] = success_patterns
knowledge["failure_patterns"] = failure_patterns

atomic_write_json(registry_path, reg)

print(f"[dream] success={len(success_patterns)} failure={len(failure_patterns)}", flush=True)
PYEOF
)

# ── Python3 실행 ─────────────────────────────────────────────
log "Running statistical extraction (python3)..."
if ! command -v python3 &>/dev/null; then
  log "ERROR: python3 not found. Cannot run dream distillation."
  exit 1
fi

STATS_OUTPUT=$(python3 - "$REGISTRY" "$SUCCESS_FILE" "$FAILURE_FILE" "$DRY_RUN" <<< "$PYTHON_SCRIPT" 2>&1)
EXIT_CODE=$?
echo "$STATS_OUTPUT" | while IFS= read -r line; do log "$line"; done

if [[ $EXIT_CODE -ne 0 ]]; then
  log "ERROR: python3 script exited with code $EXIT_CODE"
  exit 1
fi

if [[ $DRY_RUN -eq 1 ]]; then
  echo "$STATS_OUTPUT"
  log "====== daily-dream END (dry-run — no files written) ======"
  exit 0
fi

# ── (선택적) Opus enrichment ─────────────────────────────────
# OPUS_BUDGET_OK=1 이 아니면 건너뜀. claude CLI 없어도 graceful.
if [[ "${OPUS_BUDGET_OK:-0}" == "1" ]] && command -v claude &>/dev/null; then
  log "Opus enrichment enabled — calling claude CLI..."

  SUCCESS_COUNT=$(python3 -c "
import json, sys
with open('$SUCCESS_FILE') as f:
    d = json.load(f)
print(len(d.get('success_patterns', [])))
" 2>/dev/null || echo "0")

  FAILURE_COUNT=$(python3 -c "
import json, sys
with open('$FAILURE_FILE') as f:
    d = json.load(f)
print(len(d.get('failure_patterns', [])))
" 2>/dev/null || echo "0")

  SUMMARY=$(python3 - "$REGISTRY" <<'SUMEOF'
import json, sys, datetime
with open(sys.argv[1]) as f:
    reg = json.load(f)
cutoff = datetime.datetime.utcnow() - datetime.timedelta(days=7)
issues = reg.get("issues", [])
recent = []
for iss in issues:
    ts_str = iss.get("completed_at") or iss.get("created_at") or ""
    try:
        ts = datetime.datetime.strptime(ts_str[:19], "%Y-%m-%dT%H:%M:%S")
        if ts >= cutoff:
            recent.append(iss)
    except Exception:
        pass
lines = []
for iss in recent:
    lines.append(f"{iss['id']} [{iss.get('type','')}] {iss.get('title','')} -> {iss.get('status','')}")
print("\n".join(lines[:30]))
SUMEOF
  )

  ENRICHMENT_PROMPT="다음은 최근 7일 harness 이슈 요약입니다. 통계 기반으로 추출한 패턴(success: $SUCCESS_COUNT, failure: $FAILURE_COUNT)을 검토하고, 놓친 중요한 학습 포인트가 있다면 1~3줄로 제안해 주세요. 없으면 'OK'라고만 응답하세요.

$SUMMARY"

  OPUS_RESULT=$(echo "$ENRICHMENT_PROMPT" | timeout 60 claude --model claude-opus-4-8 2>/dev/null || true)
  if [[ -n "$OPUS_RESULT" ]]; then
    log "Opus enrichment: $OPUS_RESULT"
  else
    log "Opus enrichment: skipped or empty (graceful degradation)"
  fi
else
  log "Opus enrichment: skipped (OPUS_BUDGET_OK=${OPUS_BUDGET_OK:-0} or claude CLI absent)"
fi

# ── 최종 요약 출력 ────────────────────────────────────────────
SUCCESS_COUNT=$(python3 -c "
import json
with open('$SUCCESS_FILE') as f:
    d = json.load(f)
print(len(d.get('success_patterns', [])))
" 2>/dev/null || echo "?")

FAILURE_COUNT=$(python3 -c "
import json
with open('$FAILURE_FILE') as f:
    d = json.load(f)
print(len(d.get('failure_patterns', [])))
" 2>/dev/null || echo "?")

log "====== daily-dream END: success=$SUCCESS_COUNT failure=$FAILURE_COUNT ======"
echo "[dream] success_patterns=$SUCCESS_COUNT failure_patterns=$FAILURE_COUNT"
