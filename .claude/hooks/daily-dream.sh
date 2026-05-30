#!/usr/bin/env bash
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
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
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

# ── 최근 7일 이슈 필터링 ─────────────────────────────────────
recent = []
for iss in issues:
    ts_str = iss.get("completed_at") or iss.get("created_at") or ""
    try:
        ts = datetime.datetime.strptime(ts_str[:19], "%Y-%m-%dT%H:%M:%S")
        if ts >= cutoff:
            recent.append(iss)
    except Exception:
        pass

completed = [i for i in recent if i.get("status") == "COMPLETED"]
failed    = [i for i in recent if i.get("status") == "FAILED"]

print(f"[stats] recent_7d={len(recent)} completed={len(completed)} failed={len(failed)}", flush=True)

# ── 휴리스틱 패턴 도출 함수 ──────────────────────────────────
def find_or_create(patterns_list, pattern_str):
    for p in patterns_list:
        if p.get("pattern") == pattern_str:
            return p
    return None

def merge_success(patterns, pattern_str, evidence_id, now):
    existing = find_or_create(patterns, pattern_str)
    if existing:
        existing["frequency"] = existing.get("frequency", 1) + 1
        existing["last_seen"] = now
        if evidence_id not in existing.get("evidence_issues", []):
            existing.setdefault("evidence_issues", []).append(evidence_id)
    else:
        patterns.append({
            "pattern": pattern_str,
            "evidence_issues": [evidence_id],
            "frequency": 1,
            "first_seen": now,
            "last_seen": now
        })

def merge_failure(patterns, pattern_str, evidence_id, now, hint=""):
    existing = find_or_create(patterns, pattern_str)
    if existing:
        existing["frequency"] = existing.get("frequency", 1) + 1
        if evidence_id not in existing.get("evidence_issues", []):
            existing.setdefault("evidence_issues", []).append(evidence_id)
    else:
        patterns.append({
            "pattern": pattern_str,
            "evidence_issues": [evidence_id],
            "frequency": 1,
            "root_cause_hint": hint,
            "incident_doc_ref": None
        })

# ── 성공 패턴 도출 ────────────────────────────────────────────
# 패턴 1: REFACTOR + scope_dir 명시 → COMPLETED
refactor_completed = [i for i in completed if i.get("type") == "REFACTOR"
                      and i.get("payload", {}).get("scope_dir")]
if refactor_completed:
    pstr = "REFACTOR + scope_dir 명시 → COMPLETED (범위 한정 리팩토링 성공률 높음)"
    for iss in refactor_completed:
        merge_success(success_patterns, pstr, iss["id"], now_iso)

# 패턴 2: rubric 4/4 충족 이슈 (rubric_score == "4/4")
rubric_full = [i for i in completed
               if str(i.get("result", {}).get("rubric_score","")) == "4/4"]
if rubric_full:
    pstr = "rubric 4/4 충족 이슈는 100% COMPLETED (명시적 성공 기준 효과)"
    for iss in rubric_full:
        merge_success(success_patterns, pstr, iss["id"], now_iso)

# 패턴 3: blocked_by 해소 후 즉시 완료 (깊이 0)
depth0_completed = [i for i in completed
                    if i.get("depth", 0) == 0
                    and i.get("payload", {}).get("blocked_by")]
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
                and "injected_count" in i.get("result", {})]
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
for agent, ids in agent_success.items():
    if len(ids) >= 2:
        pstr = f"에이전트 '{agent}' 완료율 높음 ({len(ids)}건 COMPLETED)"
        merge_success(success_patterns, pstr, ids[0], now_iso)

# ── 실패 패턴 도출 ────────────────────────────────────────────
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
    if not agent:
        continue
    agent_fail.setdefault(agent, []).append(iss["id"])
for agent, ids in agent_fail.items():
    if len(ids) >= 2:
        pstr = f"에이전트 '{agent}' 반복 실패 ({len(ids)}건)"
        merge_failure(failure_patterns, pstr, ids[0], now_iso,
                      f"에이전트 프롬프트 또는 이슈 스펙 점검 필요 (에이전트: {agent})")

# 패턴 F3: scope_dir 미명시 실패
no_scope_failed = [i for i in failed
                   if not i.get("payload", {}).get("scope_dir")]
if no_scope_failed:
    pstr = "scope_dir 미명시 이슈 → 실패율 증가"
    for iss in no_scope_failed:
        merge_failure(failure_patterns, pstr, iss["id"], now_iso,
                      "이슈 생성 시 scope_dir 필드 필수 명시 필요")

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
    with open(path, "w") as f:
        json.dump(d, f, ensure_ascii=False, indent=2)
        f.write("\n")

save_patterns(success_path, "success_patterns", success_patterns)
save_patterns(failure_path, "failure_patterns", failure_patterns)

# ── registry.json knowledge 필드 증분 갱신 ───────────────────
knowledge = reg.setdefault("knowledge", {})
knowledge["success_patterns"] = success_patterns
knowledge["failure_patterns"] = failure_patterns

with open(registry_path, "w") as f:
    json.dump(reg, f, ensure_ascii=False, indent=2)
    f.write("\n")

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
