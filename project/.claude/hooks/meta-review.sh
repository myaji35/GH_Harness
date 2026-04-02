#!/bin/bash
# meta-review.sh — Meta Agent 관찰 주기 실행
# 30분마다 또는 수동으로 호출됨
#
# 역할:
#   1. registry.json 전체 분석
#   2. 5가지 패턴 탐지 (반복실패, 성능저하, 이슈폭발, 병목, 장기미해결)
#   3. 리뷰 코멘트 출력 (사용자에게 현황 보고)
#   4. 개선 이슈 자동 생성 (주기당 최대 5개)
#   5. knowledge DB 업데이트

REGISTRY=".claude/issue-db/registry.json"

if [ ! -f "$REGISTRY" ]; then
  echo "[Meta] registry.json 없음"
  exit 0
fi

python3 << 'PYEOF'
import json, datetime, sys

try:
    with open(".claude/issue-db/registry.json", 'r') as f:
        registry = json.load(f)
except Exception as e:
    print(f"[Meta] registry 읽기 실패: {e}")
    sys.exit(0)

issues = registry.get("issues", [])
stats = registry.get("stats", {})
knowledge = registry.get("knowledge", {})
hooks_log = registry.get("hooks", {})

if not issues:
    print("[Meta] 이슈 없음 — 분석 스킵")
    sys.exit(0)

# ── 상태별 분류 ──
by_status = {}
by_type = {}
by_agent = {}
for iss in issues:
    s = iss.get("status", "UNKNOWN")
    t = iss.get("type", "UNKNOWN")
    a = iss.get("assign_to", "UNKNOWN")
    by_status.setdefault(s, []).append(iss)
    by_type.setdefault(t, []).append(iss)
    by_agent.setdefault(a, []).append(iss)

done = by_status.get("DONE", [])
failed = by_status.get("FAILED", [])
in_progress = by_status.get("IN_PROGRESS", [])
ready = by_status.get("READY", [])
escalated = by_status.get("ESCALATED", [])

# ── 패턴 탐지 ──
findings = []
new_issues = []
next_id_num = stats.get("total_issues", len(issues)) + 1

def make_issue(title, issue_type, priority, assign_to, payload=None):
    global next_id_num
    if len(new_issues) >= 5:
        return  # 주기당 최대 5개
    # 유사 이슈 중복 체크
    for iss in issues:
        if iss.get("title") == title and iss.get("status") in ("READY", "IN_PROGRESS"):
            return
    iss = {
        "id": f"ISS-{next_id_num:03d}",
        "title": title,
        "type": issue_type,
        "status": "READY",
        "priority": priority,
        "assign_to": assign_to,
        "depth": 1,
        "retry_count": 0,
        "parent_id": None,
        "depends_on": [],
        "created_at": datetime.datetime.now().isoformat(),
        "payload": payload or {},
        "result": None,
        "spawn_rules": []
    }
    new_issues.append(iss)
    next_id_num += 1

# 패턴 1: 반복 실패 — 같은 파일에서 FIX_BUG 3회+
file_failures = {}
for iss in issues:
    if iss.get("type") == "FIX_BUG":
        files = iss.get("payload", {}).get("files", [])
        for f in files:
            file_failures[f] = file_failures.get(f, 0) + 1
for f, count in file_failures.items():
    if count >= 3:
        findings.append(f"🔴 반복 실패: {f} ({count}회 FIX_BUG)")
        make_issue(
            f"[Meta] {f} 모듈 근본 원인 분석 및 리팩토링",
            "REFACTOR", "P0", "agent-harness",
            {"target_file": f, "failure_count": count}
        )

# 패턴 2: 이슈 폭발 — 백로그 30개 초과
backlog_count = len(ready) + len(in_progress)
if backlog_count > 30:
    findings.append(f"🟠 이슈 폭발: 백로그 {backlog_count}개")
    make_issue(
        "[Meta] 이슈 우선순위 재조정",
        "PATTERN_ANALYSIS", "P1", "meta-agent",
        {"backlog_count": backlog_count}
    )

# 패턴 3: 에스컬레이션 누적
if len(escalated) >= 3:
    findings.append(f"🔴 에스컬레이션 누적: {len(escalated)}개")
    make_issue(
        "[Meta] 에스컬레이션 근본 원인 분석",
        "SYSTEMIC_ISSUE", "P0", "meta-agent",
        {"escalated_ids": [e["id"] for e in escalated]}
    )

# 패턴 4: 에이전트 간 핑퐁 — 같은 parent에서 3회+ 왕복
parent_chains = {}
for iss in issues:
    pid = iss.get("parent_id")
    if pid:
        parent_chains.setdefault(pid, []).append(iss)
for pid, children in parent_chains.items():
    if len(children) >= 3:
        agents = set(c.get("assign_to") for c in children)
        if len(agents) >= 2:
            findings.append(f"🟠 핑퐁 감지: {pid} → {len(children)}회 파생 ({', '.join(agents)})")
            make_issue(
                f"[Meta] {pid} 이슈 체인 근본 원인 분석",
                "PATTERN_ANALYSIS", "P1", "meta-agent",
                {"parent_id": pid, "chain_length": len(children)}
            )

# 패턴 5: 장기 미해결 — READY 상태 오래된 이슈
now = datetime.datetime.now()
for iss in ready:
    created = iss.get("created_at", "")
    try:
        created_dt = datetime.datetime.fromisoformat(created)
        hours = (now - created_dt).total_seconds() / 3600
        if hours > 2:  # 세션 기준 2시간 이상
            findings.append(f"🟡 장기 대기: {iss['id']} ({iss['type']}) — {hours:.0f}시간")
    except Exception:
        pass

# 패턴 없으면 긍정적 피드백
if not findings:
    # 성공률 분석
    total = len(issues)
    done_count = len(done)
    if total > 0:
        rate = done_count / total * 100
        findings.append(f"✅ 정상 운영 — 완료율 {rate:.0f}% ({done_count}/{total})")

# ── 리뷰 코멘트 출력 ──
cycle = len(knowledge.get("meta_observations", [])) + 1

print(f"""
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🧠 Meta Agent 관찰 완료 [{cycle}번째 주기]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 전체: {len(issues)}개 | ✅ {len(done)} | 🔄 {len(in_progress)} | 📋 {len(ready)} | ❌ {len(failed)} | ⚠️ {len(escalated)}""")

print(f"\n📋 발견된 패턴:")
for f in findings:
    print(f"  {f}")

if new_issues:
    print(f"\n🆕 생성된 이슈 ({len(new_issues)}개):")
    for ni in new_issues:
        print(f"  → {ni['id']} [{ni['priority']}] {ni['type']} — {ni['title']} → {ni['assign_to']}")

# 에이전트별 현황
print(f"\n👥 에이전트별 현황:")
for agent, agent_issues in sorted(by_agent.items()):
    agent_done = sum(1 for i in agent_issues if i.get("status") == "DONE")
    agent_fail = sum(1 for i in agent_issues if i.get("status") in ("FAILED", "ESCALATED"))
    agent_ready = sum(1 for i in agent_issues if i.get("status") == "READY")
    print(f"  {agent}: 완료 {agent_done} | 대기 {agent_ready} | 실패 {agent_fail}")

# 전략 제안
print(f"\n💡 전략 제안:")
if len(ready) > 10:
    print(f"  → 백로그 {len(ready)}개 — 우선순위 재정렬 필요")
elif len(ready) == 0 and len(in_progress) == 0:
    print(f"  → 모든 이슈 처리 완료 — 새로운 기능/개선 작업을 기획하세요")
    print(f"  → 'harness 시작'으로 새 사이클 시작 가능")
elif new_issues:
    print(f"  → {len(new_issues)}개 개선 이슈 생성됨 — 자동 실행 대기")
else:
    print(f"  → 현재 파이프라인 정상 운영 중")

print(f"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

# ── registry 업데이트 ──
# 새 이슈 추가
for ni in new_issues:
    registry["issues"].append(ni)
    registry["stats"]["total_issues"] = registry["stats"].get("total_issues", 0) + 1

# meta_observations 기록
knowledge.setdefault("meta_observations", []).append({
    "cycle": cycle,
    "timestamp": datetime.datetime.now().isoformat(),
    "findings": [f for f in findings],
    "issues_created": [ni["id"] for ni in new_issues],
    "stats_snapshot": {
        "total": len(issues),
        "done": len(done),
        "in_progress": len(in_progress),
        "ready": len(ready),
        "failed": len(failed),
        "escalated": len(escalated)
    }
})

registry["knowledge"] = knowledge
registry["stats"]["evolved"] = registry["stats"].get("evolved", 0) + 1

with open(".claude/issue-db/registry.json", 'w') as f:
    json.dump(registry, f, indent=2, ensure_ascii=False)

# 새 이슈가 생성되었으면 exit 2 (asyncRewake)
if new_issues:
    sys.exit(2)
PYEOF
