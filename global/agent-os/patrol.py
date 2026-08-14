#!/usr/bin/env python3
"""patrol.py — Hermes 프로젝트 순회 자문 (Agent OS)

상위 폴더의 모든 하네스 설치 프로젝트(registry.json 보유)를 순회하며,
READY 이슈가 있는 프로젝트를 찾아 claude -p로 '자문'을 남긴다.

원칙 (대표님 확정):
  - 자문만 남긴다. 코드 수정·커밋 절대 안 함. (feedback_opinion_no_implement)
  - 프로젝트별로 충분한 의견을 나누고, 실제 진행은 각 프로젝트에서 개별.
  - claude -p = 구독 토큰. API 키 금지.
  - 틱당 자문 대상 1개 프로젝트만 (순환) → 레이트리밋·집중 보호.

사용법:
  patrol.py <projects_root> <daily_cap> <calls_today>
  → stdout에 JSON: {"action","detail","claude_calls","project","advised_issue"}
"""
import json, os, sys, subprocess, datetime, tempfile, shutil

def load(p, d):
    try:
        return json.load(open(p, encoding="utf-8"))
    except Exception:
        return d

def atomic_write(p, data):
    fd, t = tempfile.mkstemp(dir=os.path.dirname(p))
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    shutil.move(t, p)

def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()

def scan(projects_root):
    """모든 프로젝트의 READY 이슈 현황. [{name,dir,registry,ready:[{id,title,priority}]}]"""
    out = []
    for name in sorted(os.listdir(projects_root)):
        d = os.path.join(projects_root, name)
        reg = os.path.join(d, ".claude", "issue-db", "registry.json")
        if not os.path.isfile(reg):
            continue
        data = load(reg, {})
        ready = [{"id": i.get("id"), "title": i.get("title", ""),
                  "priority": i.get("priority", "P2"),
                  "advised": bool(i.get("hermes_advice"))}
                 for i in data.get("issues", []) if i.get("status") == "READY"]
        out.append({"name": name, "dir": d, "registry": reg, "ready": ready})
    return out

def pick_target(projects):
    """자문 안 받은 READY 이슈를 우선순위·프로젝트 대기수로 선정."""
    PRIO = {"P0": 0, "P1": 1, "P2": 2, "P3": 3}
    best = None
    for p in projects:
        for iss in p["ready"]:
            if iss["advised"]:
                continue
            key = (PRIO.get(iss["priority"], 2), -len(p["ready"]))
            if best is None or key < best[0]:
                best = (key, p, iss)
    return (best[1], best[2]) if best else (None, None)

def main():
    projects_root, daily_cap, calls_today = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
    projects = scan(projects_root)
    total_ready = sum(len(p["ready"]) for p in projects)

    result = {"action": "patrol", "claude_calls": 0, "project": "",
              "advised_issue": "", "detail": f"{len(projects)}개 프로젝트 · READY {total_ready}"}

    if calls_today >= daily_cap:
        result["detail"] = f"일일 상한({daily_cap}) 도달 — 스캔만"
        print(json.dumps(result, ensure_ascii=False)); return

    proj, iss = pick_target(projects)
    if not proj:
        result["detail"] = f"자문 대기 이슈 없음 (READY {total_ready}, 모두 자문됨)"
        print(json.dumps(result, ensure_ascii=False)); return

    # claude -p 자문 (구독 토큰). 코드 수정 금지 명시.
    env = dict(os.environ)
    env.pop("ANTHROPIC_API_KEY", None)  # 구독 전용 강제
    prompt = (f"프로젝트 '{proj['name']}'의 하네스 이슈에 대해 충분한 의견을 주세요. "
              f"코드는 수정하지 말고(자문만), 다음 4가지를 한국어로 간결히: "
              f"1)핵심 접근 2)주의점 3)다음 실행 3단계 4)리스크. "
              f"이슈: [{iss['id']}] {iss['title']}")
    try:
        advice = subprocess.run(
            ["claude", "-p", prompt], cwd=proj["dir"], env=env,
            capture_output=True, text=True, timeout=150).stdout.strip()
    except Exception as e:
        advice = ""
        result["detail"] = f"{proj['name']}/{iss['id']} 자문 실패: {e}"

    if advice:
        data = load(proj["registry"], {})
        for i in data.get("issues", []):
            if i.get("id") == iss["id"]:
                i.setdefault("hermes_advice", []).append({"ts": now(), "advice": advice[:1500]})
                break
        atomic_write(proj["registry"], data)
        result.update({"claude_calls": 1, "project": proj["name"],
                       "advised_issue": iss["id"],
                       "detail": f"{proj['name']} · {iss['id']} 자문 완료"})
    print(json.dumps(result, ensure_ascii=False))

if __name__ == "__main__":
    main()
