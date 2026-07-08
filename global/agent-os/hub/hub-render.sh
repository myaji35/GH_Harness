#!/bin/bash
# hub-render.sh — Agent OS 통합 허브 대시보드 (Agent OS ④, 기본언어 한국어)
#
# registry.json(이슈/에이전트), memory/MEMORY.md, 20개 프로젝트 git 상태,
# journey 그래프 링크를 읽어 단일 HTML(의존성 0)로 렌더한다. 영상3의 Agent OS 허브.
#
# 사용법:
#   hub-render.sh [--open]
#     --open: 렌더 후 브라우저로 연다.
#
# 산출물: global/agent-os/hub/hub.html
# exit 0 = 성공, 3 = python3 없음

set -euo pipefail

HARNESS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
PROJECTS_ROOT="$(dirname "$HARNESS_ROOT")"    # /Volumes/E_SSD/02_GitHub.nosync
REGISTRY="$HARNESS_ROOT/.claude/issue-db/registry.json"
MEMORY_INDEX="$HOME/.claude/projects/-Volumes-E-SSD-02-GitHub-nosync/memory/MEMORY.md"
JOURNEY_HTML="$HARNESS_ROOT/global/agent-os/journey/journey.html"
OUT="$(dirname "${BASH_SOURCE[0]}")/hub.html"
SNAP="$(mktemp)"
trap 'rm -f "$SNAP"' EXIT

if ! command -v python3 >/dev/null 2>&1; then
  echo "[hub] python3 가 필요합니다." >&2
  exit 3
fi

# --- 프로젝트 스냅샷: 하네스 관리 대상 = registry 보유 프로젝트 기준 --
# (.git 유무와 무관 — ShortsAffiliate처럼 git 없이 registry만 있는 곳도 포함)
for d in "$PROJECTS_ROOT"/*/; do
  [ -f "$d/.claude/issue-db/registry.json" ] || continue
  name="$(basename "$d")"
  if [ -d "$d/.git" ]; then
    branch="$(git -C "$d" branch --show-current 2>/dev/null || echo '?')"
    dirty="$(git -C "$d" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  else
    branch="(no-git)"; dirty="0"
  fi
  echo "$name|$branch|$dirty|$d"
done > "$SNAP.raw"

python3 - "$SNAP.raw" "$SNAP" <<'PY'
import json, sys, os
raw, out = sys.argv[1:3]
rows = []
for line in open(raw, encoding="utf-8"):
    parts = line.rstrip("\n").split("|", 3)
    if len(parts) < 4: continue
    name, branch, dirty, d = parts
    ready = advised = 0
    reg = os.path.join(d, ".claude", "issue-db", "registry.json")
    if os.path.isfile(reg):
        try:
            data = json.load(open(reg, encoding="utf-8"))
            for i in data.get("issues", []):
                if i.get("status") == "READY":
                    ready += 1
                    if i.get("hermes_advice"): advised += 1
        except Exception:
            pass
    rows.append({"name": name, "branch": branch, "dirty": int(dirty or 0),
                 "ready": ready, "advised": advised})
json.dump(rows, open(out, "w", encoding="utf-8"), ensure_ascii=False)
PY
rm -f "$SNAP.raw"

# --- 렌더 -------------------------------------------------------------
python3 - "$REGISTRY" "$MEMORY_INDEX" "$SNAP" "$JOURNEY_HTML" "$OUT" <<'PY'
import json, os, re, sys, html, datetime

registry, mem_index, snap_path, journey, out = sys.argv[1:6]

def load_json(p, default):
    try:
        return json.load(open(p, encoding="utf-8"))
    except Exception:
        return default

reg = load_json(registry, {})
issues = reg.get("issues", [])
projects = load_json(snap_path, [])
learned = reg.get("learned_skills", [])
moa = reg.get("moa_runs", [])
hermes_runs = reg.get("hermes_runs", [])

# --- Hermes 운영 상태 판정 ---
def parse_ts(s):
    try:
        return datetime.datetime.fromisoformat(str(s).replace("Z","+00:00"))
    except Exception:
        return None

now_dt = datetime.datetime.now(datetime.timezone.utc)
last_run = hermes_runs[-1] if hermes_runs else None
last_ago_min = None
if last_run and parse_ts(last_run.get("ts")):
    last_ago_min = int((now_dt - parse_ts(last_run["ts"])).total_seconds() // 60)
interval_min = reg.get("hermes_state", {}).get("interval_min", 30)
# 운영 중 판정: 마지막 실행이 interval의 2배 이내면 '운영 중'
hermes_live = last_ago_min is not None and last_ago_min <= interval_min * 2
kill = os.path.isfile(os.path.join(os.path.dirname(registry), "..", "..", "global", "agent-os", "hermes.stop"))

# 이슈 상태 집계
from collections import Counter
status_ct = Counter(i.get("status","?") for i in issues)
prio_ct = Counter(i.get("priority","?") for i in issues)
recent = [i for i in issues if i.get("status") not in ("COMPLETED","CLOSED")][:12]

# 메모리 인덱스 라인 수
mem_lines = 0
if os.path.isfile(mem_index):
    mem_lines = sum(1 for l in open(mem_index, encoding="utf-8") if l.strip().startswith("- ["))

dirty_total = sum(p.get("dirty",0) for p in projects)
now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
journey_exists = os.path.isfile(journey)

def esc(s): return html.escape(str(s))

def ready_cell(p):
    r, a = p.get("ready",0), p.get("advised",0)
    if r == 0: return '<span class="sub">0</span>'
    badge = f'<span class="hbadge live" style="padding:1px 7px;font-size:11px">🤖 {a}/{r} 자문</span>' if a else f'<span class="warn">{r}</span>'
    return badge
proj_rows = "".join(
    f'<tr><td>{esc(p["name"])}</td><td><code>{esc(p["branch"])}</code></td>'
    f'<td class="{"warn" if p["dirty"] else "ok"}">{p["dirty"]}</td>'
    f'<td>{ready_cell(p)}</td></tr>'
    for p in sorted(projects, key=lambda x:(-x.get("ready",0), -x.get("dirty",0))))

total_ready = sum(p.get("ready",0) for p in projects)
total_advised = sum(p.get("advised",0) for p in projects)

issue_rows = "".join(
    f'<tr><td><code>{esc(i.get("id","?"))}</code></td><td>{esc(i.get("type","?"))}</td>'
    f'<td>{esc(i.get("priority","?"))}</td><td><span class="badge s-{esc(i.get("status","?"))}">{esc(i.get("status","?"))}</span></td>'
    f'<td>{esc(i.get("title","")[:50])}</td></tr>'
    for i in recent) or '<tr><td colspan="5" class="sub">진행 중 이슈 없음</td></tr>'

learned_rows = "".join(
    f'<li><code>{esc(l.get("slug",""))}</code> <span class="sub">← {esc(l.get("url","")[:50])}</span></li>'
    for l in learned[-8:]) or '<li class="sub">아직 /learn 으로 학습한 스킬 없음</li>'

status_chips = "".join(f'<span class="chip">{esc(k)}: <b>{v}</b></span>' for k,v in status_ct.most_common())
prio_chips = "".join(f'<span class="chip p-{esc(k)}">{esc(k)}: <b>{v}</b></span>' for k,v in sorted(prio_ct.items()))

journey_card = (
    f'<a class="jbtn" href="file://{esc(os.path.abspath(journey))}" target="_blank">🧭 Journey 그래프 열기</a>'
    if journey_exists else
    '<span class="sub">아직 생성 안 됨 — <code>agent-os journey</code> 실행</span>')

# --- Hermes 운영 배지 ---
if kill:
    hermes_badge = '<span class="hbadge stop">🛑 Hermes 정지됨 (킬스위치 ON)</span>'
elif hermes_live:
    nxt = f"약 {max(0, interval_min - (last_ago_min or 0))}분 후" if last_ago_min is not None else "예정"
    hermes_badge = (f'<span class="hbadge live">🤖 Hermes 운영 중</span>'
                    f'<span class="hsub">마지막 갱신 {last_ago_min}분 전 · 다음 갱신 {esc(nxt)} · 총 {len(hermes_runs)}회</span>')
elif hermes_runs:
    hermes_badge = f'<span class="hbadge idle">😴 Hermes 유휴</span><span class="hsub">마지막 {last_ago_min}분 전 · cron 미가동 의심</span>'
else:
    hermes_badge = '<span class="hbadge off">⚪ Hermes 미운영</span><span class="hsub">agent-os hermes start 로 시작</span>'

# --- Hermes 활동 카드 rows ---
hermes_rows = "".join(
    f'<tr><td class="sub">{esc(str(r.get("ts",""))[:16].replace("T"," "))}</td>'
    f'<td>{esc(r.get("action","render"))}</td>'
    f'<td>{esc(str(r.get("detail",""))[:40])}</td>'
    f'<td class="sub">{r.get("claude_calls",0)}회</td></tr>'
    for r in reversed(hermes_runs[-10:])) or '<tr><td colspan="4" class="sub">아직 Hermes 실행 기록 없음</td></tr>'

# 오늘 claude 호출 횟수 (구독 토큰 — API 비용 없음)
today = now_dt.strftime("%Y-%m-%d")
calls_today = sum(r.get("claude_calls",0) for r in hermes_runs if str(r.get("ts","")).startswith(today))

TPL = r"""<!doctype html><html lang="ko"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Agent OS 허브</title>
<style>
:root{--bg:#0d0f14;--card:#161923;--line:#262b37;--txt:#e8ebf1;--sub:#8b95a5;--accent:#6ea8ff;--ok:#22c55e;--warn:#f59e0b;--p0:#ef4444}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--txt);font-family:-apple-system,'Apple SD Gothic Neo',Segoe UI,sans-serif;font-size:14px;line-height:1.5}
header{padding:20px 28px;border-bottom:1px solid var(--line);display:flex;align-items:baseline;justify-content:space-between;flex-wrap:wrap;gap:8px}
h1{margin:0;font-size:20px}.ts{color:var(--sub);font-size:12px}
main{padding:24px 28px;display:grid;grid-template-columns:repeat(auto-fit,minmax(320px,1fr));gap:18px;max-width:1400px}
.card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:18px}
.card h2{margin:0 0 12px;font-size:15px;display:flex;align-items:center;gap:8px}
.kpis{display:flex;gap:14px;flex-wrap:wrap;margin-bottom:8px}
.kpi{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:14px 18px;min-width:120px}
.kpi .n{font-size:26px;font-weight:700}.kpi .l{color:var(--sub);font-size:12px;margin-top:2px}
table{width:100%;border-collapse:collapse;font-size:13px}th,td{text-align:left;padding:6px 8px;border-bottom:1px solid var(--line)}
th{color:var(--sub);font-weight:500}code{background:#0d0f14;padding:1px 5px;border-radius:4px;font-size:12px}
.chip{display:inline-block;background:#0d0f14;border:1px solid var(--line);border-radius:20px;padding:3px 10px;margin:2px;font-size:12px}
.chip.p-P0{border-color:var(--p0)}.badge{padding:2px 8px;border-radius:6px;font-size:11px;background:#0d0f14;border:1px solid var(--line)}
.s-COMPLETED{color:var(--ok)}.s-READY{color:var(--accent)}.s-IN_PROGRESS{color:var(--warn)}
.ok{color:var(--ok)}.warn{color:var(--warn)}.sub{color:var(--sub)}
.jbtn{display:inline-block;background:var(--accent);color:#0d0f14;font-weight:600;padding:8px 16px;border-radius:8px;text-decoration:none}
.cmds code{display:block;margin:4px 0;padding:6px 10px;background:#0d0f14;border-radius:6px}
.scroll{max-height:280px;overflow:auto}
header{align-items:flex-start}
.hermesbar{margin-top:8px;display:flex;align-items:center;gap:10px;flex-wrap:wrap}
.hbadge{font-size:13px;font-weight:600;padding:4px 12px;border-radius:20px}
.hbadge.live{background:rgba(34,197,94,.15);color:#22c55e;border:1px solid #22c55e;animation:pulse 2s infinite}
.hbadge.idle{background:rgba(245,158,11,.15);color:#f59e0b;border:1px solid #f59e0b}
.hbadge.stop{background:rgba(239,68,68,.15);color:#ef4444;border:1px solid #ef4444}
.hbadge.off{background:#0d0f14;color:#8b95a5;border:1px solid #262b37}
.hsub{font-size:12px;color:#8b95a5}
@keyframes pulse{0%,100%{opacity:1}50%{opacity:.55}}
</style></head><body>
<header><div><h1>🛰️ Agent OS 허브 <span class="sub" style="font-size:13px">· GH_Harness</span></h1>
<div class="hermesbar">__HERMES_BADGE__</div></div>
<span class="ts">생성: __NOW__</span></header>
<div class="kpis" style="padding:20px 28px 0">
  <div class="kpi"><div class="n">__NPROJ__</div><div class="l">연결 프로젝트</div></div>
  <div class="kpi"><div class="n">__NISSUE__</div><div class="l">전체 이슈</div></div>
  <div class="kpi"><div class="n">__DIRTY__</div><div class="l">미커밋 변경 합계</div></div>
  <div class="kpi"><div class="n">__NMEM__</div><div class="l">메모리 항목</div></div>
  <div class="kpi"><div class="n">__NLEARN__</div><div class="l">학습한 스킬</div></div>
  <div class="kpi"><div class="n">__NMOA__</div><div class="l">MoA 실행</div></div>
  <div class="kpi"><div class="n">__NHERMES__</div><div class="l">Hermes 실행</div></div>
  <div class="kpi"><div class="n">__CALLS_TODAY__</div><div class="l">오늘 claude 호출 (구독)</div></div>
</div>
<main>
  <div class="card"><h2>📋 이슈 파이프라인</h2>
    <div style="margin-bottom:10px">__STATUS_CHIPS__</div>
    <div style="margin-bottom:12px">__PRIO_CHIPS__</div>
    <div class="scroll"><table><thead><tr><th>ID</th><th>타입</th><th>우선</th><th>상태</th><th>제목</th></tr></thead>
    <tbody>__ISSUE_ROWS__</tbody></table></div>
  </div>
  <div class="card"><h2>🗼 프로젝트 관제탑 (Hermes 순회)</h2>
    <p class="sub">READY __TOTAL_READY__건 중 __TOTAL_ADVISED__건 Hermes 자문 완료 — 실행은 각 프로젝트에서 개별 진행</p>
    <div class="scroll"><table><thead><tr><th>프로젝트</th><th>브랜치</th><th>미커밋</th><th>READY/자문</th></tr></thead>
    <tbody>__PROJ_ROWS__</tbody></table></div>
  </div>
  <div class="card"><h2>🧭 Journey 그래프</h2>
    <p class="sub">스킬 ↔ 메모리 연결 시각화</p>__JOURNEY__
  </div>
  <div class="card"><h2>🎓 학습한 스킬 (/learn)</h2>
    <ul style="margin:0;padding-left:18px">__LEARNED__</ul>
  </div>
  <div class="card"><h2>🤖 Hermes 운영 활동</h2>
    <p class="sub">cron 무인 운영 기록 — Claude Code(claude -p, 구독 토큰 · API 비용 없음)</p>
    <div class="scroll"><table><thead><tr><th>시각</th><th>동작</th><th>내용</th><th>claude 호출</th></tr></thead>
    <tbody>__HERMES_ROWS__</tbody></table></div>
  </div>
  <div class="card cmds"><h2>⌨️ Agent OS 명령</h2>
    <code>agent-os moa "&lt;프롬프트&gt;"  # 멀티모델 합의</code>
    <code>agent-os learn &lt;URL&gt;        # URL → 스킬</code>
    <code>agent-os journey            # 그래프 재생성</code>
    <code>agent-os hub --open         # 이 허브 열기</code>
    <code>agent-os hermes start       # 무인 운영 시작(cron)</code>
    <code>agent-os hermes stop        # 킬스위치 · 즉시 정지</code>
    <code>agent-os hermes status      # 운영 상태 조회</code>
  </div>
</main></body></html>"""

out_html = (TPL
  .replace("__NOW__", esc(now))
  .replace("__NPROJ__", str(len(projects)))
  .replace("__NISSUE__", str(len(issues)))
  .replace("__DIRTY__", str(dirty_total))
  .replace("__NMEM__", str(mem_lines))
  .replace("__NLEARN__", str(len(learned)))
  .replace("__NMOA__", str(len(moa)))
  .replace("__NHERMES__", str(len(hermes_runs)))
  .replace("__CALLS_TODAY__", str(calls_today))
  .replace("__HERMES_BADGE__", hermes_badge)
  .replace("__HERMES_ROWS__", hermes_rows)
  .replace("__STATUS_CHIPS__", status_chips or '<span class="sub">이슈 없음</span>')
  .replace("__PRIO_CHIPS__", prio_chips)
  .replace("__ISSUE_ROWS__", issue_rows)
  .replace("__PROJ_ROWS__", proj_rows)
  .replace("__TOTAL_READY__", str(total_ready))
  .replace("__TOTAL_ADVISED__", str(total_advised))
  .replace("__JOURNEY__", journey_card)
  .replace("__LEARNED__", learned_rows))

open(out, "w", encoding="utf-8").write(out_html)
print(f"[hub] ✅ 허브 렌더: {out}")
print(f"[hub]    프로젝트 {len(projects)} · 이슈 {len(issues)} · 미커밋 {dirty_total} · 메모리 {mem_lines}")
PY

if [ "${1:-}" = "--open" ]; then
  command -v open >/dev/null 2>&1 && open "$OUT" || echo "[hub] 파일: $OUT"
fi
