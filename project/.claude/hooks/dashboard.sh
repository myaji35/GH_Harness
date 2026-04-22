#!/bin/bash
# dashboard.sh — GH_Harness 상태 대시보드 (v4.1 A)
#
# 사용:
#   bash .claude/hooks/dashboard.sh          # 터미널 컬러 출력
#   bash .claude/hooks/dashboard.sh --json   # 기계 읽기 JSON
#   bash .claude/hooks/dashboard.sh --brief  # 한 줄 요약 (CI용)
#
# 데이터 소스:
#   - .claude/issue-db/registry.json
#   - .claude/trace/YYYY-MM-DD.jsonl (decision-trace.sh 산출물)

set -eo pipefail

MODE="${1:-pretty}"
REGISTRY=".claude/issue-db/registry.json"
TRACE_DIR=".claude/trace"

if [ ! -f "$REGISTRY" ]; then
  echo "[dashboard] registry.json 없음 — 빈 프로젝트"
  exit 0
fi

python3 - "$MODE" "$REGISTRY" "$TRACE_DIR" << 'PYEOF'
import json
import os
import sys
import datetime
from collections import Counter
from pathlib import Path

MODE = sys.argv[1] if len(sys.argv) > 1 else "pretty"
REGISTRY = sys.argv[2] if len(sys.argv) > 2 else ".claude/issue-db/registry.json"
TRACE_DIR = Path(sys.argv[3] if len(sys.argv) > 3 else ".claude/trace")

# ANSI
def c(code, s):
    if MODE == "--json":
        return s
    return f"\033[{code}m{s}\033[0m"

BOLD = "1"
DIM = "2"
RED = "31"
GREEN = "32"
YELLOW = "33"
BLUE = "34"
MAGENTA = "35"
CYAN = "36"

with open(REGISTRY) as f:
    reg = json.load(f)

issues = reg.get("issues", [])
status_counts = Counter(i.get("status", "?") for i in issues)
type_counts = Counter(i.get("type", "?") for i in issues)
agent_counts = Counter(i.get("assign_to", "?") for i in issues)

# 최근 24h/7d 완료·실패
now = datetime.datetime.now(datetime.timezone.utc)
def ts(iss, key):
    v = iss.get(key)
    if not v: return None
    try:
        dt = datetime.datetime.fromisoformat(v.replace("Z", "+00:00"))
        # naive → UTC로 간주
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=datetime.timezone.utc)
        return dt
    except Exception:
        return None

last_24h = []
last_7d = []
for i in issues:
    t = ts(i, "completed_at") or ts(i, "created_at")
    if t:
        delta = (now - t).total_seconds()
        if delta <= 86400: last_24h.append(i)
        if delta <= 604800: last_7d.append(i)

def count_status(lst, statuses):
    return sum(1 for i in lst if i.get("status") in statuses)

# Agent 성공률
agent_stats = {}
for i in last_7d:
    a = i.get("assign_to", "?")
    s = agent_stats.setdefault(a, {"total": 0, "done": 0, "failed": 0})
    s["total"] += 1
    if i.get("status") in ("COMPLETED", "DONE"): s["done"] += 1
    if i.get("status") in ("FAILED", "BLOCKED"): s["failed"] += 1

# Opus 예산
budget = reg.get("opus_budget_state", {})
today = datetime.date.today().isoformat()
today_cost = budget.get(today, {}).get("cost_usd", 0) if isinstance(budget, dict) else 0

# 핑퐁 의심 (ISS-201 가드와 동일 룰)
ready_issues = [i for i in issues if i.get("status") == "READY"]
from collections import defaultdict as _dd
pingpong = _dd(list)
for i in ready_issues:
    src = i.get("payload", {}).get("source_issue") or i.get("parent_id")
    if src:
        pingpong[(i.get("type"), src)].append(i)
pingpong_suspects = [(k, len(v)) for k, v in pingpong.items() if len(v) >= 2]

# 최근 실패 5개
failed_recent = sorted(
    [i for i in issues if i.get("status") in ("FAILED", "BLOCKED")],
    key=lambda x: x.get("completed_at") or x.get("created_at") or "",
    reverse=True
)[:5]

# Trace 집계 — 오늘 dispatched/completed 카운트
today_events = Counter()
today_file = TRACE_DIR / f"{today}.jsonl"
if today_file.exists():
    for line in today_file.read_text().splitlines():
        try:
            d = json.loads(line)
            today_events[d.get("event", "?")] += 1
        except Exception:
            continue

# Gate 통계 (v4.1)
gate_pending = sum(1 for i in issues if i.get("status") == "GATE_PENDING")
gate_active = sum(1 for i in issues if i.get("type") == "LINT_CHECK" and i.get("status") in ("READY", "IN_PROGRESS") and i.get("payload", {}).get("gate"))

# ── 출력 분기 ──
if MODE == "--json":
    import json as _j
    out = {
        "ts": now.isoformat(),
        "total_issues": len(issues),
        "status": dict(status_counts),
        "type_top10": type_counts.most_common(10),
        "agent_top10": agent_counts.most_common(10),
        "last_24h_total": len(last_24h),
        "last_24h_done": count_status(last_24h, ("COMPLETED", "DONE")),
        "last_7d_total": len(last_7d),
        "agent_stats_7d": agent_stats,
        "today_cost_usd": today_cost,
        "pingpong_suspects": [[list(k), v] for k, v in pingpong_suspects],
        "failed_recent": [{"id": i.get("id"), "title": i.get("title", "")[:80], "status": i.get("status")} for i in failed_recent],
        "today_events": dict(today_events),
        "gate_pending": gate_pending,
        "gate_active": gate_active,
    }
    print(_j.dumps(out, indent=2, ensure_ascii=False))
    sys.exit(0)

if MODE == "--brief":
    parts = [
        f"issues={len(issues)}",
        f"ready={status_counts.get('READY',0)}",
        f"wip={status_counts.get('IN_PROGRESS',0)}",
        f"gate_pending={gate_pending}",
        f"pingpong={len(pingpong_suspects)}",
        f"cost_today=${today_cost:.2f}",
    ]
    print(" ".join(parts))
    sys.exit(0)

# Pretty
print(c(BOLD, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"))
print(c(BOLD, f"  GH_Harness v4.1 Dashboard — {now.strftime('%Y-%m-%d %H:%M:%S UTC')}"))
print(c(BOLD, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"))
print()

# 이슈 현황
print(c(CYAN, "▸ 이슈 현황 (총 {}건)".format(len(issues))))
for st, n in status_counts.most_common():
    color = GREEN if st in ("COMPLETED", "DONE") else (YELLOW if st in ("READY", "IN_PROGRESS") else (RED if st in ("FAILED", "BLOCKED", "GATE_PENDING") else DIM))
    bar = "█" * min(30, n)
    print(f"  {c(color, st.ljust(14))} {str(n).rjust(4)}  {c(DIM, bar)}")
print()

# 최근 활동
print(c(CYAN, "▸ 최근 24h"))
d24 = count_status(last_24h, ("COMPLETED", "DONE"))
f24 = count_status(last_24h, ("FAILED", "BLOCKED"))
print(f"  전체 {len(last_24h)}건 · 완료 {c(GREEN, str(d24))} · 실패 {c(RED, str(f24))}")
print()

# 오늘 이벤트 (trace)
if today_events:
    print(c(CYAN, f"▸ 오늘 이벤트 (trace)"))
    for ev, n in today_events.most_common(8):
        print(f"  {ev.ljust(14)} {n}")
    print()

# Gate 현황
if gate_pending or gate_active:
    print(c(CYAN, "▸ v4.1 Gate"))
    print(f"  활성 LINT gate: {c(YELLOW, str(gate_active))}")
    print(f"  Gate 대기중: {c(YELLOW if gate_pending else DIM, str(gate_pending))}")
    print()

# 핑퐁 의심
if pingpong_suspects:
    print(c(RED, f"⚠ 핑퐁 의심: {len(pingpong_suspects)}건"))
    for (typ, src), n in sorted(pingpong_suspects, key=lambda x: -x[1])[:5]:
        print(f"  {typ} × {n} (src={src})")
    print()

# Opus 예산
cost_color = RED if today_cost >= 15 else (YELLOW if today_cost >= 10 else GREEN)
print(c(CYAN, "▸ Opus 예산 (오늘)"))
print(f"  사용: {c(cost_color, f'${today_cost:.2f}')} / Soft Cap $10 / Hard Cap $20")
print()

# Agent 7d 성공률
if agent_stats:
    print(c(CYAN, "▸ 에이전트 7d 성공률"))
    rows = []
    for a, s in agent_stats.items():
        if s["total"] == 0: continue
        rate = (s["done"] / s["total"]) * 100
        rows.append((a, s["total"], rate, s["failed"]))
    rows.sort(key=lambda x: -x[1])
    for a, total, rate, failed in rows[:8]:
        rate_color = GREEN if rate >= 80 else (YELLOW if rate >= 50 else RED)
        print(f"  {a.ljust(22)} {total:>3}건  {c(rate_color, f'{rate:5.1f}%')}  실패 {failed}")
    print()

# 최근 실패
if failed_recent:
    print(c(RED, "▸ 최근 실패/차단 5건"))
    for i in failed_recent:
        print(f"  {c(RED, i.get('id','?'))} [{i.get('status','?')}] {i.get('title','')[:70]}")
    print()

print(c(DIM, f"힌트: --json (기계) / --brief (한줄) / registry: {REGISTRY}"))
PYEOF
