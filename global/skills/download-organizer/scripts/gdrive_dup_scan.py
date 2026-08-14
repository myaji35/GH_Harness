#!/usr/bin/env python3
"""구글드라이브 특정 폴더의 md5 동일 중복 파일을 스캔.
사용: python3 gdrive_dup_scan.py [gdrive경로]  (기본: gdrive: 루트)
출력: dup_remove_list.json (그룹당 '의미있는 이름' 1개 KEEP, 나머지 제거후보)
검증됨 2026-07-07: 루트 627 실파일 중 15개 중복 제거(239MB).
"""
import json, sys, subprocess, unicodedata, re
from collections import defaultdict

REMOTE = sys.argv[1] if len(sys.argv) > 1 else "gdrive:"
WORK = sys.argv[2] if len(sys.argv) > 2 else "."
def N(s): return unicodedata.normalize("NFC", s)  # ⚠️ macOS/rclone 파일명은 NFD, 매칭 전 필수

# 1. 해시 수집 (구글 네이티브 문서는 md5 없음 → 자동 제외)
raw = subprocess.run(["rclone","lsjson",REMOTE,"--files-only","--hash","--no-modtime"],
                     capture_output=True, text=True).stdout
data = json.loads(raw)

by_hash = defaultdict(list)
for f in data:
    h = (f.get("Hashes") or {}).get("md5")
    if h: by_hash[h].append(f)
groups = [fs for fs in by_hash.values() if len(fs) > 1]

# 2. '의미있는 이름' KEEP 선택: 카톡TalkFile_·확장자중복·UUID·날짜코드·'사본'은 후순위
def junk(name):
    s = 0
    if name.startswith("TalkFile_"): s += 5
    if re.search(r'\.(pdf|PDF)\.(pdf|PDF)$', name): s += 4
    if re.match(r'^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}', name): s += 6
    if re.match(r'^\d{6,}[-.\d]*\.\w+$', name): s += 3
    if "사본" in N(name): s += 4
    return s - len(name) * 0.002  # 동점 시 설명적(긴) 이름 우대

remove = []
report = []
for fs in groups:
    fs2 = sorted(fs, key=lambda x: junk(x["Name"]))
    keep, dels = fs2[0], fs2[1:]
    report.append({"keep": N(keep["Name"]), "del": [N(x["Name"]) for x in dels],
                   "mb": round(keep["Size"]/1024/1024, 1)})
    remove += [x["Path"] for x in dels]

json.dump(remove, open(f"{WORK}/dup_remove_list.json","w"), ensure_ascii=False, indent=1)
json.dump(report, open(f"{WORK}/dup_report.json","w"), ensure_ascii=False, indent=1)
print(f"실파일(해시): {len(data)} | 중복그룹: {len(groups)} | 제거후보: {len(remove)}개")
print(f"→ dup_remove_list.json / dup_report.json 저장. 승인 후 gdrive_apply.py --delete 로 제거.")
