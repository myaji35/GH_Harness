#!/usr/bin/env python3
"""이동 실행 + 옵시디언 노트 생성. rclone move (업로드→검증→로컬삭제) + 이동로그.
사용: python3 execute.py <카테고리|ALL>"""
import os, sys, json, subprocess, datetime, unicodedata

# 경로는 환경변수로 재정의 가능 (기본값은 검증된 값)
DL = os.environ.get("DL_DIR", os.path.expanduser("~/Downloads"))
VAULT = os.environ.get("OBSIDIAN_VAULT", os.path.expanduser("~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Obsidian"))
ARCHIVE = os.path.join(VAULT, "📥아카이브")
IDX = os.path.join(ARCHIVE, "_인덱스")
WORK = os.environ.get("ORGANIZER_WORK", os.path.expanduser("~/.download-organizer"))
os.makedirs(WORK, exist_ok=True)
PLAN = os.path.join(WORK, "plan.json")
MOVELOG = os.path.join(WORK, "moved.jsonl")
GDRIVE_BASE = ""  # gdrive: 루트가 곧 '내 드라이브'. 별도 중간폴더 없음

target = sys.argv[1] if len(sys.argv) > 1 else "ALL"
plan = json.load(open(PLAN))
items = [p for p in plan if (target == "ALL" or p["cat"] == target)]

os.makedirs(ARCHIVE, exist_ok=True)
os.makedirs(IDX, exist_ok=True)

def human_size(path):
    try:
        b = os.path.getsize(path)
        return f"{b/1048576:.1f}MB" if b > 1048576 else f"{b//1024}KB"
    except: return "?"

def pdf_summary(path):
    """PDF 앞부분 텍스트 3줄 (룰베이스, AI 없이)"""
    try:
        r = subprocess.run(["pdftotext", "-l", "1", path, "-"], capture_output=True, text=True, timeout=15)
        lines = [l.strip() for l in r.stdout.split("\n") if l.strip()]
        return lines[:4]
    except: return []

# 디스크의 실제 파일명(raw, NFD일 수 있음) → NFC 매핑. plan은 NFC라 raw로 접근해야 rclone이 찾음.
_disk = {}
for _f in os.listdir(DL):
    if os.path.isfile(os.path.join(DL, _f)):
        _disk[unicodedata.normalize("NFC", _f)] = _f

moved, failed = [], []
for p in items:
    raw = _disk.get(unicodedata.normalize("NFC", p["orig"]))
    if not raw:
        continue  # 이미 이동됨(로컬에 없음)
    src = os.path.join(DL, raw)  # 실제 디스크 파일명 사용 (NFD 대응)
    if not os.path.isfile(src):
        continue
    size = human_size(src)
    ext = os.path.splitext(p["new"])[1].lstrip(".")
    gdest = f"gdrive:{p['dest']}"
    # 요약 (PDF만)
    summary = pdf_summary(src) if ext == "pdf" else []

    # === rclone move: 새 이름으로 업로드 후 로컬 삭제 ===
    # move + 이름변경을 위해 --> moveto (파일→파일)
    dst_full = f"{gdest}/{p['new']}"
    r = subprocess.run(["rclone", "moveto", src, dst_full, "--drive-import-formats", ""],
                       capture_output=True, text=True)
    if r.returncode != 0:
        failed.append((p["orig"], r.stderr[:200]))
        continue
    # 검증: 로컬 파일이 실제로 사라졌는지 + 원격에 있는지
    remote_ok = subprocess.run(["rclone", "lsf", dst_full], capture_output=True, text=True).stdout.strip()
    local_gone = not os.path.isfile(src)
    if not (remote_ok and local_gone):
        failed.append((p["orig"], f"검증실패 remote={bool(remote_ok)} local_gone={local_gone}"))
        continue

    moved.append(p)
    with open(MOVELOG, "a") as lf:
        lf.write(json.dumps({"orig": p["orig"], "new": p["new"], "dest": p["dest"],
                             "gdrive": dst_full, "cat": p["cat"], "size": size}, ensure_ascii=False) + "\n")

    # === 옵시디언 파일노트 생성 ===
    title = os.path.splitext(p["new"])[0]
    date = p["new"][:10]
    is_smg = "SMG" in p["dest"]
    project = p["dest"].split("/")[1] if p["dest"].startswith("Project/") else ""
    tags = [p["cat"]]
    if is_smg: tags.append("SMG")
    if project and project != p["cat"]: tags.append(project)
    note = f"""---
title: {title}
date: {date}
category: {p['cat']}
project: {project or p['cat']}
tags: [{', '.join(tags)}]
gdrive_path: {GDRIVE_BASE}/{p['dest']}/
filename: {p['new']}
filesize: {size}
filetype: {ext}
archived: {datetime.date.today().isoformat()}
status: 아카이브됨
---

# {title}

## 📌 요약
"""
    if summary:
        for s in summary:
            note += f"- {s}\n"
    else:
        note += "- (내용 요약 없음 — 원본 참조)\n"
    note += f"""
## 🔗 관련
[[{p['cat']}]]{' · [[SMG]]' if is_smg else ''}

## 📂 원본 위치
구글 드라이브 → `{GDRIVE_BASE}/{p['dest']}/{p['new']}`
"""
    notepath = os.path.join(ARCHIVE, title + ".md")
    with open(notepath, "w") as nf:
        nf.write(note)

# 인덱스 노트 갱신 (카테고리별 허브)
from collections import defaultdict
bycat = defaultdict(list)
for p in moved:
    bycat[p["cat"]].append(p)
for cat, ps in bycat.items():
    idxpath = os.path.join(IDX, cat + ".md")
    header = f"# {cat} 인덱스\n\n아카이브된 파일 목록:\n\n"
    lines = "".join(f"- [[{os.path.splitext(p['new'])[0]}]] ({p['new'][:10]})\n" for p in ps)
    # append 모드로 누적
    existing = ""
    if os.path.isfile(idxpath):
        existing = open(idxpath).read()
        if not existing.startswith("#"):
            existing = header + existing
        with open(idxpath, "a") as f:
            f.write(lines)
    else:
        with open(idxpath, "w") as f:
            f.write(header + lines)

print(f"✅ 이동완료 {len(moved)}개 → 구글드라이브 + 옵시디언 노트 생성")
for p in moved:
    print(f"   {p['orig'][:38]:38s} → {p['dest']}/{p['new']}")
if failed:
    print(f"\n❌ 실패 {len(failed)}개:")
    for o, e in failed:
        print(f"   {o}: {e}")
