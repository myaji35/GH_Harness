#!/usr/bin/env python3
"""전 프로젝트 registry.json → 업무 현황판(Claude Dashboard) 데이터 파일 2종 생성.

사용: python3 tools/work_dashboard/export.py [출력디렉터리]
  open_issues.json  — 열린 이슈 전체 (프로젝트·구분·우선순위·경과일)
  recent_done.json  — 최근 30일 개발완료(DONE/COMPLETED) 이슈
  routines.json     — Hermes 정기 업무(cron) 상태
행정·사업 업무는 Paperclip(localhost:3100) 이슈를 함께 모은다. 서버가 꺼져 있으면 건너뛴다.
"""
import glob, json, os, re, sys, urllib.request
from datetime import datetime, timezone

ROOT = "/Volumes/E_SSD/02_GitHub.nosync"
SKIP_PREFIX = ("__ARCHIVE__", "_backups", "restore-project")
SKIP_DUP = {"0053_JIEUN(MUSINSA)/musinsa_clone"}  # 상위 폴더와 동일 레지스트리

BUCKET = {
    "AWAITING_USER": "대표님 결정", "BLOCKED_USER": "대표님 결정", "DECISION_PENDING": "대표님 결정",
    "BLOCKED_NEEDS_APPROVAL": "대표님 결정", "AWAITING_DIRECTIVE": "대표님 결정", "READY_FOR_USER": "대표님 결정",
    "IN_PROGRESS": "진행 중",
    "READY": "착수 대기", "PENDING": "착수 대기", "SCHEDULED": "착수 대기", "NEEDS_TRIAGE": "착수 대기", "open": "착수 대기",
    "BLOCKED": "막힘", "ESCALATED": "막힘", "PARTIAL": "막힘", "PARTIAL_DONE": "막힘", "DONE_PARTIAL": "막힘", "needs-info": "막힘",
    "BACKLOG": "아이디어", "PARKED": "아이디어", "DEFERRED": "아이디어",
}
# 시스템이 스스로 만든 점검·검증 이슈 — 대표님이 챙길 일과 분리
AUTO_TYPES = {"SYSTEMIC_ISSUE", "PATTERN_ANALYSIS", "SCREEN_GAP", "CODE_SMELL", "RUN_TESTS", "LINT_CHECK",
    "IMPROVE_COVERAGE", "SCORE", "DEAD_CODE", "STYLE_FIX", "PLAN_ENG_REVIEW", "PLAN_CEO_REVIEW",
    "OPPORTUNITY_SCOUT", "E2E_VERIFY", "JOURNEY_VALIDATE", "BIZ_VALIDATE", "UI_REVIEW", "DOMAIN_ANALYZE",
    "EVAL", "TEST", "DATA_QUALITY", "BRAND_GUARD", "REGRESSION_CHECK"}
# 나머지는 area_cache.json(키 → "개발"|"행정·사업")으로 분류. 없는 키는 classify_todo.json 에 남긴다.
CACHE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "area_cache.json")
DONE = {"DONE", "COMPLETED", "CLOSED_DONE", "RESOLVED", "VERIFIED", "CLOSED_SUCCESS"}
SECRET = re.compile(r"(AIza[0-9A-Za-z_-]{20,}|sk-[A-Za-z0-9_-]{16,}|ghp_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16})")

def parse(ts):
    if not ts: return None
    try:
        dt = datetime.fromisoformat(str(ts).replace("Z", "+00:00"))
        return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)
    except Exception:
        return None

# "pw:xxx", "비번=xxx", "password xxxx"(영숫자 값) 꼴만 가린다 — "비밀번호 변경" 같은 문구는 두기
PASSWORD = re.compile(r"((?:pw|pwd|password|passwd|비번|비밀번호|암호)\s*[:=：]\s*|(?:pw|pwd|password|passwd)\s+)[!-~]{4,}", re.I)

def clean(t):
    t = SECRET.sub("[키 가림]", str(t or "")).replace("\n", " ").strip()
    t = PASSWORD.sub(lambda m: m.group(1) + "[가림]", t)
    return t[:140]

PAPERCLIP = os.environ.get("PAPERCLIP_URL", "http://localhost:3100")
PC_BUCKET = {"backlog": "착수 대기", "todo": "착수 대기", "in_progress": "진행 중",
             "in_review": "대표님 결정", "blocked": "막힘"}
PC_PRI = {"urgent": "P0", "high": "P1", "medium": "P2", "low": "P3"}
HERMES_JOBS = os.path.expanduser("~/.hermes/cron/jobs.json")

def api(path):
    with urllib.request.urlopen(PAPERCLIP + path, timeout=10) as r:
        d = json.load(r)
    return d if isinstance(d, list) else d.get("items", [])

def paperclip(now):
    """Paperclip 회사별 이슈 → (열린 행, 완료 행). 담당은 에이전트 이름."""
    open_rows, done_rows = [], []
    try:
        companies = api("/api/companies")
    except Exception as e:
        print(f"paperclip 건너뜀: {e}")
        return open_rows, done_rows
    for c in companies:
        agents = {a["id"]: a.get("name") for a in api(f"/api/companies/{c['id']}/agents")}
        for i in api(f"/api/companies/{c['id']}/issues"):
            st, title = i.get("status"), clean(i.get("title"))
            created, updated = parse(i.get("createdAt")), parse(i.get("updatedAt"))
            base = {"project": c["name"], "id": i.get("identifier"), "title": title,
                    "priority": PC_PRI.get(i.get("priority"), "-"), "status": st, "type": "paperclip",
                    "source": "Paperclip", "owner": agents.get(i.get("assigneeAgentId")) or ""}
            if st in PC_BUCKET:
                open_rows.append({**base, "bucket": PC_BUCKET[st],
                    "area": "개발" if title.startswith("[공장 요청]") else "행정·사업",
                    "age_days": (now - created).days if created else None,
                    "idle_days": (now - (updated or created)).days if (updated or created) else None})
            elif st == "done":
                fin = parse(i.get("completedAt")) or updated
                if fin and (now - fin).days <= 30:
                    done_rows.append({**base, "done_day": fin.astimezone().date().isoformat()})
    return open_rows, done_rows

def routines():
    try:
        jobs = json.load(open(HERMES_JOBS)).get("jobs", [])
    except Exception:
        return []
    return [{"name": j.get("name"), "schedule": j.get("schedule_display"),
             "state": "켜짐" if j.get("enabled") else "꺼짐",
             "last_status": j.get("last_status") or "아직 안 돎",
             "last_run": (j.get("last_run_at") or "")[:16].replace("T", " "),
             "next_run": (j.get("next_run_at") or "")[:16].replace("T", " "),
             "failure_streak": j.get("failure_streak") or 0} for j in jobs]

def main(out):
    now = datetime.now(timezone.utc)
    open_rows, done_rows = [], []
    paths = glob.glob(f"{ROOT}/*/.claude/issue-db/registry.json") + glob.glob(f"{ROOT}/*/*/.claude/issue-db/registry.json")
    for p in sorted(paths):
        proj = os.path.relpath(p, ROOT).split("/.claude")[0]
        if proj.startswith(SKIP_PREFIX) or proj in SKIP_DUP: continue
        try:
            d = json.load(open(p))
        except Exception:
            continue
        for i in (d.get("issues", []) if isinstance(d, dict) else d):
            st = i.get("status")
            created, updated = parse(i.get("created_at")), parse(i.get("updated_at"))
            base = {"project": proj, "id": i.get("id"), "title": clean(i.get("title")),
                    "priority": i.get("priority") or "-", "status": st, "type": i.get("type") or "-",
                    "source": "하네스", "owner": ""}
            if st in BUCKET:
                open_rows.append({**base, "bucket": BUCKET[st],
                    "age_days": (now - created).days if created else None,
                    "idle_days": (now - (updated or created)).days if (updated or created) else None})
            elif st in DONE and updated and (now - updated).days <= 30:
                done_rows.append({**base, "done_day": updated.date().isoformat()})
    for r in open_rows:
        r["area"] = "자동 점검" if r["type"] in AUTO_TYPES else None
    pc_open, pc_done = paperclip(now)
    open_rows += pc_open
    done_rows += pc_done
    seen = {}
    for r in open_rows:  # 같은 레지스트리 안 중복 ID 대비 고유 키
        k = f"{r['project']} {r['id']}"
        seen[k] = seen.get(k, 0) + 1
        r["key"] = k if seen[k] == 1 else f"{k} ({seen[k]})"
    cache = json.load(open(CACHE)) if os.path.exists(CACHE) else {}
    todo = []
    for r in open_rows:
        if r["area"] is None:
            r["area"] = cache.get(r["key"], "미분류")
            if r["key"] not in cache: todo.append({"key": r["key"], "type": r["type"], "title": r["title"]})
    os.makedirs(out, exist_ok=True)
    json.dump(todo, open(f"{out}/classify_todo.json", "w"), ensure_ascii=False, indent=0)
    json.dump(open_rows, open(f"{out}/open_issues.json", "w"), ensure_ascii=False)
    json.dump(done_rows, open(f"{out}/recent_done.json", "w"), ensure_ascii=False)
    json.dump(routines(), open(f"{out}/routines.json", "w"), ensure_ascii=False)
    print(f"open={len(open_rows)} done30={len(done_rows)} 미분류={len(todo)} → {out}")

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "out"))
