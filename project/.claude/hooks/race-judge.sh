#!/usr/bin/env bash
# ============================================================
# race-judge.sh — RACE_MODE 아티팩트를 읽어 자동 점수화 + 승자 선정
#
# 사용법:
#   bash race-judge.sh <ISSUE_ID>
#
# 입력: .claude/race-artifacts/<ISSUE_ID>/<provider>/{exit_code,stdout.log,
#       stderr.log,diff.patch,diff.stat,duration_sec,files.txt}
# 출력:
#   - .claude/race-artifacts/<ISSUE_ID>/report.json
#   - registry.json의 해당 이슈 result 필드 업데이트
#   - 승자 worktree는 브랜치 유지, 패자 worktree는 /tmp/harness-race-losers 로 이동
# ============================================================

set -u

ISSUE_ID="${1:-}"
REGISTRY="${REGISTRY:-.claude/issue-db/registry.json}"
ARTIFACT_ROOT="${ARTIFACT_ROOT:-.claude/race-artifacts}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
die()  { echo -e "${RED}✖ $*${NC}" >&2; exit 1; }
info() { echo -e "${BLUE}ℹ $*${NC}"; }
ok()   { echo -e "${GREEN}✓ $*${NC}"; }
warn() { echo -e "${YELLOW}! $*${NC}"; }

[ -z "$ISSUE_ID" ] && die "usage: race-judge.sh <ISSUE_ID>"
[ -f "$REGISTRY" ] || die "registry.json 없음"

ART_DIR="$ARTIFACT_ROOT/$ISSUE_ID"
[ -d "$ART_DIR" ] || die "artifact 디렉토리 없음: $ART_DIR"

# payload에서 judge_criteria 읽기
PAYLOAD_FILE="$ART_DIR/payload.json"
[ -f "$PAYLOAD_FILE" ] || die "payload.json 없음"

PROJECT_NAME="$(basename "$(pwd)")"

info "판정 시작: $ISSUE_ID"

# 점수화 파이썬 블록
python3 - "$ART_DIR" "$PAYLOAD_FILE" "$REGISTRY" "$ISSUE_ID" "$PROJECT_NAME" <<'PYEOF'
import json, os, sys, subprocess, re, shutil, datetime, pathlib

art_dir, payload_file, reg_path, issue_id, project_name = sys.argv[1:6]

with open(payload_file) as f:
    payload = json.load(f)

criteria = payload.get("judge_criteria") or {
    "lint": 30, "tests": 40, "diff_size": 15, "files_scope": 15
}
total_weight = sum(criteria.values()) or 100
target_files = set(payload.get("target_files") or [])
base_branch = payload.get("base_branch", "main")

# provider 목록 탐색
providers = []
for entry in sorted(os.listdir(art_dir)):
    p = os.path.join(art_dir, entry)
    if os.path.isdir(p) and os.path.isfile(os.path.join(p, "exit_code")):
        providers.append(entry)

if not providers:
    print("ERR: 아티팩트 없음", file=sys.stderr)
    sys.exit(2)

def read_text(path, default=""):
    try:
        with open(path) as f:
            return f.read()
    except Exception:
        return default

def read_int(path, default=0):
    try:
        with open(path) as f:
            return int(f.read().strip())
    except Exception:
        return default

# ── 점수 계산 ─────────────────────────────────────────────
# lint/test는 worktree에 체크아웃된 상태가 아니므로 diff.patch만으로 정적 판단
# 더 정확한 점수는 승자 선정 후 해당 worktree에서 별도 실행 권장
def score_lint_static(diff_patch: str) -> float:
    """diff에서 뻔한 에러 패턴 카운트"""
    if not diff_patch.strip():
        return 0.0  # 아예 안 함
    bad_patterns = [
        r"^\+.*console\.log\(",
        r"^\+.*debugger;",
        r"^\+.*TODO|FIXME|XXX",
        r"^\+.*any\s*[=:)]",     # TS any 남발
        r"^\+.*eval\(",
    ]
    penalties = 0
    for line in diff_patch.splitlines():
        for pat in bad_patterns:
            if re.search(pat, line):
                penalties += 1
    # 10개 넘으면 0점, 0개면 100점 (선형)
    return max(0.0, 100.0 - penalties * 10.0)

def score_diff_size(diff_stat: str) -> float:
    """변경 줄 수. 적을수록 좋음 (Occam)"""
    if not diff_stat.strip():
        return 0.0
    m = re.search(r"(\d+)\s+insertion", diff_stat)
    ins = int(m.group(1)) if m else 0
    m2 = re.search(r"(\d+)\s+deletion", diff_stat)
    dele = int(m2.group(1)) if m2 else 0
    total = ins + dele
    if total == 0:
        return 0.0
    # 0~50줄: 100점, 50~500줄: 선형 감소, 500+: 30점
    if total <= 50:
        return 100.0
    if total >= 500:
        return 30.0
    return 100.0 - (total - 50) * (70.0 / 450.0)

def score_files_scope(diff_patch: str, targets: set) -> float:
    """target_files 외 파일 수정 시 감점"""
    if not targets:
        return 100.0  # 제약 없음
    touched = set()
    for line in diff_patch.splitlines():
        if line.startswith("diff --git "):
            m = re.search(r"b/(.+)$", line)
            if m:
                touched.add(m.group(1))
    if not touched:
        return 0.0
    out_of_scope = touched - targets
    if not out_of_scope:
        return 100.0
    # 범위 밖 파일 하나당 20점 감점
    return max(0.0, 100.0 - 20.0 * len(out_of_scope))

def score_tests_placeholder(exit_code: int, duration: int) -> float:
    """
    동적 테스트 실행은 비싸서 휴리스틱:
    - exit_code == 0 → 기본 70 (정상 종료)
    - timeout(124) → 10
    - 기타 에러 → 30
    """
    if exit_code == 0:
        return 70.0
    if exit_code == 124:
        return 10.0
    return 30.0

scores = {}
for prov in providers:
    pd = os.path.join(art_dir, prov)
    exit_code = read_int(os.path.join(pd, "exit_code"), -1)
    duration = read_int(os.path.join(pd, "duration_sec"), 0)
    diff_patch = read_text(os.path.join(pd, "diff.patch"))
    diff_stat = read_text(os.path.join(pd, "diff.stat"))

    s_lint = score_lint_static(diff_patch)
    s_tests = score_tests_placeholder(exit_code, duration)
    s_diff = score_diff_size(diff_stat)
    s_files = score_files_scope(diff_patch, target_files)

    # 실격 판정
    disqualified = False
    dq_reason = ""
    if not diff_patch.strip():
        disqualified = True
        dq_reason = "변경사항 없음"
    elif exit_code == 124:
        disqualified = True
        dq_reason = "timeout"

    weighted = (
        s_lint * criteria.get("lint", 0)
        + s_tests * criteria.get("tests", 0)
        + s_diff * criteria.get("diff_size", 0)
        + s_files * criteria.get("files_scope", 0)
    ) / total_weight

    if disqualified:
        weighted = 0.0

    scores[prov] = {
        "exit_code": exit_code,
        "duration_sec": duration,
        "disqualified": disqualified,
        "dq_reason": dq_reason,
        "breakdown": {
            "lint": round(s_lint, 1),
            "tests": round(s_tests, 1),
            "diff_size": round(s_diff, 1),
            "files_scope": round(s_files, 1),
        },
        "total": round(weighted, 1),
    }

# 승자 선정
valid = {p: s for p, s in scores.items() if not s["disqualified"]}
winner = None
if valid:
    # 점수 내림차순 + 동점 시 diff_size 작은 쪽
    winner = sorted(
        valid.items(),
        key=lambda x: (-x[1]["total"], -x[1]["breakdown"]["diff_size"])
    )[0][0]

report = {
    "issue_id": issue_id,
    "judged_at": datetime.datetime.now().isoformat(),
    "providers": list(scores.keys()),
    "scores": scores,
    "winner": winner,
    "criteria": criteria,
}

report_path = os.path.join(art_dir, "report.json")
with open(report_path, "w") as f:
    json.dump(report, f, indent=2, ensure_ascii=False)

# 콘솔 출력
print(f"\n━━━ RACE_MODE 판정 ({issue_id}) ━━━")
for prov, s in scores.items():
    flag = "✔" if prov == winner else ("✖" if s["disqualified"] else " ")
    print(f"  {flag} {prov:10} total={s['total']:6.1f}  "
          f"lint={s['breakdown']['lint']:5.1f} "
          f"tests={s['breakdown']['tests']:5.1f} "
          f"diff={s['breakdown']['diff_size']:5.1f} "
          f"files={s['breakdown']['files_scope']:5.1f}  "
          f"exit={s['exit_code']} {s['duration_sec']}s"
          + (f" [DQ: {s['dq_reason']}]" if s['disqualified'] else ""))
if winner:
    print(f"\n🏆 승자: {winner}")
else:
    print("\n⚠️  유효 승자 없음 (전원 실격)")

# ── 패자 worktree 격리 ─────────────────────────────────────
WT_HOME = os.environ.get("WORKTREE_HOME") or os.path.expanduser("~/projects/worktrees")
LOSER_HOME = f"/tmp/harness-race-losers/{issue_id}"
os.makedirs(LOSER_HOME, exist_ok=True)

for prov in scores.keys():
    if prov == winner:
        continue
    wt_name = f"{project_name}__race-{issue_id}-{prov}"
    wt_path = os.path.join(WT_HOME, wt_name)
    if os.path.isdir(wt_path):
        dst = os.path.join(LOSER_HOME, prov)
        if os.path.exists(dst):
            shutil.rmtree(dst, ignore_errors=True)
        try:
            shutil.move(wt_path, dst)
            print(f"  패자 worktree 격리: {prov} → {dst}")
        except Exception as e:
            print(f"  패자 worktree 이동 실패: {prov} ({e})")

# ── registry.json의 해당 이슈 result 업데이트 ──────────────
with open(reg_path) as f:
    reg = json.load(f)

for iss in reg.get("issues", []):
    if iss.get("id") == issue_id:
        iss.setdefault("result", {})
        iss["result"]["winner"] = winner
        iss["result"]["scores"] = scores
        iss["result"]["report_path"] = report_path
        iss["status"] = "COMPLETED"
        iss["completed_at"] = datetime.datetime.now().isoformat()
        break

# learning 기록
if winner:
    reg.setdefault("knowledge", {}).setdefault("success_patterns", []).append({
        "pattern": "race_mode_win",
        "issue_id": issue_id,
        "winner": winner,
        "scores": {p: s["total"] for p, s in scores.items()},
        "at": datetime.datetime.now().isoformat(),
    })

with open(reg_path, "w") as f:
    json.dump(reg, f, indent=2, ensure_ascii=False)

print(f"\n📝 결과: {report_path}")
PYEOF

ok "판정 완료"
