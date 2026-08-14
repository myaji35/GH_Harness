#!/bin/bash
# journey-build.sh — 스킬↔메모리 연결 그래프 (Agent OS ③)
#
# memory/*.md 와 global/skills/*/SKILL.md 를 읽어 노드-엣지 그래프를 만들고
# 의존성 0의 단일 HTML(한국어)로 렌더한다. 영상2의 /journey 재현.
#
# 엣지 추론 규칙:
#   - 메모리 본문의 [[링크]] → 해당 메모리 노드로 연결
#   - 스킬 description 키워드가 메모리 제목/본문에 등장 → skill↔memory 연결
#
# 사용법:
#   journey-build.sh [--deep]
#     --deep: graphify 스킬로 심층 그래프도 생성하도록 안내(선택)
#
# 산출물: global/agent-os/journey/journey.html
# exit 0 = 성공, 3 = python3 없음

set -euo pipefail

HARNESS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SKILLS_DIR="$HARNESS_ROOT/global/skills"
MEMORY_DIR="$HOME/.claude/projects/-Volumes-E-SSD-02-GitHub-nosync/memory"
OUT="$(dirname "${BASH_SOURCE[0]}")/journey.html"

if ! command -v python3 >/dev/null 2>&1; then
  echo "[journey] python3 가 필요합니다." >&2
  exit 3
fi

if [ "${1:-}" = "--deep" ]; then
  echo "[journey] --deep: 심층 그래프는 Claude에서 아래를 실행하세요:" >&2
  echo "  /graphify \"$MEMORY_DIR\" --mode deep" >&2
fi

python3 - "$SKILLS_DIR" "$MEMORY_DIR" "$OUT" <<'PY'
import os, re, sys, json, html

skills_dir, memory_dir, out = sys.argv[1:4]

def read(p):
    try:
        return open(p, encoding="utf-8", errors="ignore").read()
    except Exception:
        return ""

# --- 메모리 노드 수집 ---
memories = {}   # slug -> {title, links:set, text}
if os.path.isdir(memory_dir):
    for fn in os.listdir(memory_dir):
        if not fn.endswith(".md") or fn == "MEMORY.md":
            continue
        slug = fn[:-3]
        txt = read(os.path.join(memory_dir, fn))
        m = re.search(r'^#\s+(.+)$', txt, flags=re.M)
        title = m.group(1).strip() if m else slug
        links = set(re.findall(r'\[\[([^\]]+)\]\]', txt))
        memories[slug] = {"title": title, "links": links, "text": txt}

# --- 스킬 노드 수집 ---
skills = {}     # slug -> {desc}
if os.path.isdir(skills_dir):
    for slug in os.listdir(skills_dir):
        sp = os.path.join(skills_dir, slug, "SKILL.md")
        if not os.path.isfile(sp):
            # skill.md 소문자 폴백
            alt = os.path.join(skills_dir, slug, "skill.md")
            sp = alt if os.path.isfile(alt) else None
        if not sp:
            continue
        txt = read(sp)
        m = re.search(r'^description:\s*(.+)$', txt, flags=re.M)
        desc = m.group(1).strip() if m else ""
        skills[slug] = {"desc": desc}

# --- 노드 / 엣지 구성 ---
nodes = []
for s, d in memories.items():
    nodes.append({"id": "mem:"+s, "label": d["title"][:30], "group": "memory"})
for s, d in skills.items():
    nodes.append({"id": "skill:"+s, "label": s[:30], "group": "skill"})

edges = []
# 메모리 [[링크]] → 메모리
for s, d in memories.items():
    for lnk in d["links"]:
        if lnk in memories:
            edges.append({"from": "mem:"+s, "to": "mem:"+lnk, "kind": "link"})
# 스킬 description 키워드 → 메모리 (제목/본문 매칭)
def keywords(text):
    return set(re.findall(r'[가-힣A-Za-z]{3,}', text.lower()))
for sk, sd in skills.items():
    kws = keywords(sd["desc"])
    kws.add(sk.lower())
    for ms, md in memories.items():
        hay = (md["title"] + " " + md["text"][:500]).lower()
        if any(k in hay for k in kws if len(k) >= 4):
            edges.append({"from": "skill:"+sk, "to": "mem:"+ms, "kind": "topic"})

# 엣지 과다 방지: 스킬당 topic 엣지 상위 3개만
from collections import defaultdict
topic_by_skill = defaultdict(list)
other = []
for e in edges:
    if e["kind"] == "topic":
        topic_by_skill[e["from"]].append(e)
    else:
        other.append(e)
trimmed = other[:]
for sk, lst in topic_by_skill.items():
    trimmed.extend(lst[:3])
edges = trimmed

data = {"nodes": nodes, "edges": edges,
        "stats": {"memories": len(memories), "skills": len(skills), "edges": len(edges)}}

tpl = """<!doctype html><html lang="ko"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Agent OS · Journey 그래프</title>
<style>
:root{--bg:#0f1116;--card:#181b23;--line:#2a2f3a;--txt:#e6e9ef;--sub:#9aa4b2;--mem:#4f8cff;--skill:#22c55e}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--txt);font-family:-apple-system,'Apple SD Gothic Neo',sans-serif}
header{padding:16px 20px;border-bottom:1px solid var(--line)}
h1{margin:0;font-size:18px}.sub{color:var(--sub);font-size:13px;margin-top:4px}
.legend{display:flex;gap:16px;margin-top:8px;font-size:12px}
.dot{display:inline-block;width:10px;height:10px;border-radius:50%;margin-right:5px;vertical-align:middle}
#cv{display:block;width:100%;height:calc(100vh - 90px)}
</style></head><body>
<header><h1>🧭 Agent OS · Journey 그래프</h1>
<div class="sub">스킬과 메모리의 연결 — 메모리 __M__개 · 스킬 __S__개 · 연결 __E__개</div>
<div class="legend"><span><span class="dot" style="background:var(--mem)"></span>메모리</span>
<span><span class="dot" style="background:var(--skill)"></span>스킬</span></div>
</header>
<canvas id="cv"></canvas>
<script>
const DATA = __DATA__;
const cv=document.getElementById('cv'),ctx=cv.getContext('2d');
function fit(){cv.width=cv.clientWidth;cv.height=cv.clientHeight;}
fit();addEventListener('resize',()=>{fit();});
const N=DATA.nodes.map((n,i)=>({...n,x:cv.width/2+Math.cos(i)*200*Math.random()+((i%7)-3)*90,y:cv.height/2+Math.sin(i)*200*Math.random()+((i%5)-2)*90,vx:0,vy:0}));
const idx=Object.fromEntries(N.map((n,i)=>[n.id,i]));
const E=DATA.edges.filter(e=>idx[e.from]!=null&&idx[e.to]!=null);
function step(){
 for(let a=0;a<N.length;a++)for(let b=a+1;b<N.length;b++){
  let dx=N[b].x-N[a].x,dy=N[b].y-N[a].y,d=Math.hypot(dx,dy)||1,f=1400/(d*d);
  N[a].vx-=dx/d*f;N[a].vy-=dy/d*f;N[b].vx+=dx/d*f;N[b].vy+=dy/d*f;}
 for(const e of E){let a=N[idx[e.from]],b=N[idx[e.to]],dx=b.x-a.x,dy=b.y-a.y,d=Math.hypot(dx,dy)||1,f=(d-110)*0.01;
  a.vx+=dx/d*f;a.vy+=dy/d*f;b.vx-=dx/d*f;b.vy-=dy/d*f;}
 for(const n of N){n.vx*=0.85;n.vy*=0.85;n.x+=n.vx;n.y+=n.vy;
  n.x=Math.max(40,Math.min(cv.width-40,n.x));n.y=Math.max(40,Math.min(cv.height-40,n.y));}}
function draw(){
 ctx.clearRect(0,0,cv.width,cv.height);
 ctx.strokeStyle='rgba(150,160,180,.25)';ctx.lineWidth=1;
 for(const e of E){let a=N[idx[e.from]],b=N[idx[e.to]];ctx.beginPath();ctx.moveTo(a.x,a.y);ctx.lineTo(b.x,b.y);ctx.stroke();}
 for(const n of N){ctx.beginPath();ctx.fillStyle=n.group==='memory'?'#4f8cff':'#22c55e';
  ctx.arc(n.x,n.y,6,0,7);ctx.fill();
  ctx.fillStyle='#c8cfda';ctx.font='11px sans-serif';ctx.fillText(n.label,n.x+9,n.y+4);}}
let t=0;(function loop(){if(t++<300)step();draw();requestAnimationFrame(loop);})();
</script></body></html>"""

htmlout = (tpl
    .replace("__DATA__", json.dumps(data, ensure_ascii=False))
    .replace("__M__", str(len(memories)))
    .replace("__S__", str(len(skills)))
    .replace("__E__", str(len(edges))))
open(out, "w", encoding="utf-8").write(htmlout)
print(f"[journey] ✅ 그래프 생성: {out}")
print(f"[journey]    메모리 {len(memories)} · 스킬 {len(skills)} · 연결 {len(edges)}")
PY
