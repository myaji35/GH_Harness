#!/usr/bin/env python3
"""보고서 PDF만 아카이빙: 구글드라이브 이동(PDF 로컬삭제) + 옵시디언 노트.
사용: python3 archive_report.py <pdf경로> [프로젝트명]
대표님 확정(2026-07-02):
- **HTML(편집 소스)은 로컬 ./docs/ 유지** — 이 스크립트가 안 건드림. PDF만 이동.
- 프로젝트별 폴더 라우팅. **같은 이름이면 덮어쓰기**(최신본 1개만) — 수정 재생성 시 이전 PDF·노트 갱신.
수정 워크플로우: 로컬 HTML 편집 → PDF 재생성 → 이 스크립트로 새 PDF만 이동(덮어씀)."""
import sys, os, re, subprocess, datetime

pdf = sys.argv[1]
project_hint = sys.argv[2] if len(sys.argv) > 2 else ""

if not os.path.isfile(pdf):
    print(f"ERROR: PDF 없음: {pdf}"); sys.exit(1)

VAULT = os.path.expanduser("~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Obsidian/📥아카이브/보고서")
os.makedirs(VAULT, exist_ok=True)

fname = os.path.basename(pdf)
base = os.path.splitext(fname)[0]

# 프로젝트 라우팅 (파일명/힌트 → gdrive 목적지). download-organizer와 동일 체계.
ROUTES = [
    (r"SMG|신라메디컬|의료바이오|IFMC|NPL|RWA|엔케이젠|AI데이터센터|홈즈페이|메디컬센터", "Project/SMG/보고서"),
    (r"심티어|XimTier|SimTier|거꾸로계산기", "Project/XimTier/보고서"),
    (r"누리팜|누리셀|스마트팜", "Project/누리팜/보고서"),
    (r"InsureGraph|인슈어그래프", "Project/InsureGraph/보고서"),
    (r"Townin|타운인", "Project/Townin/보고서"),
    (r"장애인표준사업장|표준사업장|무상지원금", "Project/장애인표준사업장/보고서"),
    (r"부동산|개발사업|상권|NPL자산|물건지", "Project/부동산개발/보고서"),
    (r"기업실사|인수|M&A|실사보고", "Project/기업실사M&A/보고서"),
    (r"보봇|Bobot|특허|상표", "Project/보봇/보고서"),
]
dest = "Document/보고서"  # 기본
hay = f"{base} {project_hint}"
for pat, d in ROUTES:
    if re.search(pat, hay, re.IGNORECASE):
        dest = d; break

# 날짜 추출 (파일명 YYMMDD/YYYYMMDD → 없으면 오늘)
date = datetime.date.today().isoformat()
m = re.search(r"(\d{2})(\d{2})(\d{2})(?:\D|$)", base)
if m and "01" <= m.group(2) <= "12":
    date = f"20{m.group(1)}-{m.group(2)}-{m.group(3)}"

# PDF 요약용 텍스트 (앞부분)
summary_lines = []
try:
    r = subprocess.run(["pdftotext", "-l", "2", pdf, "-"], capture_output=True, text=True, timeout=20)
    summary_lines = [l.strip() for l in r.stdout.split("\n") if l.strip()][:6]
except Exception:
    pass

# 페이지 수
pages = "?"
try:
    r = subprocess.run(["pdfinfo", pdf], capture_output=True, text=True, timeout=10)
    pm = re.search(r"Pages:\s*(\d+)", r.stdout)
    if pm: pages = pm.group(1)
except Exception:
    pass

size = os.path.getsize(pdf)
size_h = f"{size/1048576:.1f}MB" if size > 1048576 else f"{size//1024}KB"

# === rclone 이동 (업로드→검증→로컬삭제) ===
gdest = f"gdrive:{dest}/{fname}"
rr = subprocess.run(["rclone", "moveto", pdf, gdest], capture_output=True, text=True)
remote_ok = subprocess.run(["rclone", "lsf", gdest], capture_output=True, text=True).stdout.strip()
local_gone = not os.path.isfile(pdf)
if not (remote_ok and local_gone):
    print(f"⚠️ 이동 검증 실패: remote={bool(remote_ok)} local_gone={local_gone}\n{rr.stderr[:200]}")
    sys.exit(2)

# === 옵시디언 노트 생성 ===
proj = dest.split("/")[1] if dest.startswith("Project/") else "문서"
tags = ["보고서", proj] if proj != "문서" else ["보고서"]
note = f"""---
title: {base}
category: 보고서
project: {proj}
tags: [{', '.join(tags)}]
date: {date}
gdrive_path: {dest}/
filename: {fname}
pages: {pages}
filesize: {size_h}
archived: {datetime.date.today().isoformat()}
status: 아카이브됨
---

# {base}

## 📌 요약
"""
if summary_lines:
    for s in summary_lines:
        note += f"- {s}\n"
else:
    note += "- (요약 텍스트 없음 — 원본 참조)\n"
note += f"""
## 🔗 관련
[[보고서]]{f' · [[{proj}]]' if proj != '문서' else ''}

## 📂 원본 위치
구글 드라이브 → `{dest}/{fname}`
"""
notepath = os.path.join(VAULT, base + ".md")
with open(notepath, "w", encoding="utf-8") as f:
    f.write(note)

print(f"✅ 보고서 아카이빙 완료")
print(f"   구글드라이브: {dest}/{fname} ({pages}p, {size_h})")
print(f"   옵시디언 노트: 📥아카이브/보고서/{base}.md")
print(f"   로컬 원본: 삭제됨")
