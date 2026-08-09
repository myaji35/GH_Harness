#!/usr/bin/env python3
"""일자별 작업보고서(인덱스 노트) 생성. 실제 파일명 기반 [[링크]]라 절대 안 깨짐.
사용: python3 build_report.py <YYYY-MM-DD> [candidates.json]
- candidates.json(선택): [{"id","in_wl","in_ll"}, ...] 순서/소속 플래그. 없으면 archived 노트 전부를 날짜순.
동작:
  1) 볼트 유튜브 폴더에서 archived==날짜인 노트를 스캔 → video_id→실제파일명 매핑
  2) 실제 파일명으로 [[링크]] 생성 (제목 재가공 금지 → 링크 깨짐 원천 차단)
  3) 프론트매터 YAML-safe (title/tags 인용)
  4) 볼트 루트 📋일자별보고서/<날짜>_작업보고서.md 에 저장
  5) 생성 직후 자기 [[링크]]가 실제 파일과 일치하는지 검증 (불일치 시 비정상 종료)
출력 마지막 줄: REPORT_PATH=<경로>
"""
import sys, os, re, glob, json

DATE = sys.argv[1]
cand_path = sys.argv[2] if len(sys.argv) > 2 else None

VAULT = os.path.expanduser("~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Obsidian")
YTDIR = os.path.join(VAULT, "📥아카이브/유튜브")
REPDIR = os.path.join(VAULT, "📋일자별보고서")   # ← 볼트 루트 (하위 아님)
os.makedirs(REPDIR, exist_ok=True)

def fm_get(txt, key):
    m = re.search(rf'^{key}:\s?(.*)$', txt, re.M)
    if not m: return ""
    v = m.group(1).strip()
    if len(v) >= 2 and ((v[0] == '"' and v[-1] == '"') or (v[0] == "'" and v[-1] == "'")):
        v = v[1:-1]
    return v

# 1) archived==DATE 노트 스캔 → video_id -> (실제파일명 stem, title, channel, in_wl용정보)
byid = {}
for f in glob.glob(YTDIR + "/*.md"):
    b = os.path.basename(f)
    if b.startswith("._"): continue
    head = open(f, encoding="utf-8").read(1000)
    if f"archived: {DATE}" not in head: continue
    vid = fm_get(head, "video_id")
    if not vid: continue
    byid[vid] = {"note": b[:-3], "title": fm_get(head, "title"),
                 "channel": fm_get(head, "channel"),
                 "method": fm_get(head, "analysis_method")}

# 2) 순서 결정: candidates.json 있으면 그 순서/소속, 없으면 파일명 정렬
wl_rows, ll_rows = [], []
if cand_path and os.path.exists(cand_path):
    cands = json.load(open(cand_path))
    for c in cands:
        vid = c["id"]
        if vid not in byid: continue
        row = {"vid": vid, **byid[vid]}
        if c.get("in_wl"): wl_rows.append(row)
        else: ll_rows.append(row)
else:
    for vid in sorted(byid, key=lambda v: byid[v]["note"]):
        wl_rows.append({"vid": vid, **byid[vid]})

rows = wl_rows + ll_rows
transcript_cnt = 0  # 정보용 (선택): 노트 analysis_method 재스캔 생략, 호출측이 헤더 채움

def yq(v):
    return '"' + str(v).replace('"', "'") + '"'

def render_block(title, items, start):
    out = [f"## {title} ({len(items)}개)\n"]
    for i, r in enumerate(items, start):
        # 실제 파일명(stem)을 그대로 링크 → 절대 안 깨짐. []는 write_note가 이미 ()로 안전화.
        note = r["note"]
        url = f"https://www.youtube.com/watch?v={r['vid']}"
        ch = r["channel"] or ""
        out.append(f"{i}. [[{note}]] · {ch} · [🔗영상]({url})")
    out.append("")
    return out

lines = [
    "---",
    f"title: {yq(DATE + ' 유튜브 정리 작업보고서')}",
    f"date: {DATE}",
    "type: 일자별작업보고서",
    "tags: [유튜브, 작업보고서, 지식화]",
    f"처리건수: {len(rows)}",
    "---",
    "",
    f"# 📋 {DATE} 유튜브 정리 작업보고서",
    "",
    f"- **총 지식화**: {len(rows)}개 (나중에볼영상 {len(wl_rows)} + 좋아요 {len(ll_rows)})",
    f"- **분석**: 자막 전문 {sum(1 for r in rows if '자막' in r.get('method',''))}개 / 설명 폴백 {sum(1 for r in rows if '자막' not in r.get('method',''))}개",
    "- **저장 위치**: `📥아카이브/유튜브/`",
    "",
]
lines += render_block("📌 나중에 볼 동영상 (WL)", wl_rows, 1)
if ll_rows:
    lines += render_block("👍 좋아요 (LL)", ll_rows, len(wl_rows) + 1)

path = os.path.join(REPDIR, f"{DATE}_작업보고서.md")
open(path, "w", encoding="utf-8").write("\n".join(lines))

# 5) 자기 링크 검증
notes = set(os.path.basename(f)[:-3] for f in glob.glob(YTDIR + "/*.md")
            if not os.path.basename(f).startswith("._"))
txt = open(path, encoding="utf-8").read()
links = re.findall(r'\[\[([^\]]+)\]\]', txt)
missing = [l for l in links if l not in notes]
print(f"보고서 생성: {len(rows)}개 항목, [[링크]] {len(links)}개")
if missing:
    print(f"⚠️ 깨진 링크 {len(missing)}개: {missing[:5]}")
    print(f"REPORT_PATH={path}")
    sys.exit(1)
print(f"✅ 링크 {len(links)}/{len(links)} 실제 파일과 일치")
print(f"REPORT_PATH={path}")
