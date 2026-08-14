#!/usr/bin/env python3
"""승인된 계획(plan.json)을 rclone moveto로 실행 — 드라이브 내부 재배치 + 리네임.
plan.json 형식: [{"src":"루트파일명","dest":"목적지폴더","newname":"새이름(옵션)"}, ...]
  dest="__DELETE__" → deletefile. 이미 이동된 것(원본이 루트에 없음)은 자동 스킵(재실행 안전).
사용: python3 gdrive_apply.py plan.json [gdrive루트=gdrive:] [작업디렉토리=.]
검증됨 2026-07-07: 루트 100개 이동/삭제, 실패 0. 1704→1604.
"""
import json, sys, subprocess, unicodedata
plan = json.load(open(sys.argv[1]))
REMOTE = sys.argv[2] if len(sys.argv) > 2 else "gdrive:"
WORK = sys.argv[3] if len(sys.argv) > 3 else "."
def N(s): return unicodedata.normalize("NFC", s)  # ⚠️ NFD→NFC 필수
import re, os, tempfile
def has_glob(s):  # 대괄호 등 glob 문자 있으면 moveto가 실패 → move --files-from 경로 사용
    return bool(re.search(r'[\[\]\*\?\{\}]', s))
def move_via_files_from(real, dest, newname):
    # 정확한 원본 바이트를 --files-from에 담아 dest폴더로 이동 후, 필요시 리네임.
    ff = tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False, encoding="utf-8")
    ff.write(real + "\n"); ff.close()
    try:
        r = subprocess.run(["rclone","move","gdrive:",f"gdrive:{dest}","--files-from",ff.name,"--max-depth","1"],
                           capture_output=True,text=True,timeout=180)
        if r.returncode==0 and newname != N(real):  # 목적지에서 리네임 필요
            base = os.path.basename(real)
            subprocess.run(["rclone","moveto",f"gdrive:{dest}/{base}",f"gdrive:{dest}/{newname}"],
                           capture_output=True,text=True,timeout=120)
        return r
    finally:
        os.unlink(ff.name)

# 현재 루트 목록 (재실행 시 이미 이동된 것 스킵용)
# ⚠️ 루트 파일명은 NFD(자모분리)일 수 있음. plan은 NFC라 그대로 moveto하면 rclone이 소스를 못 찾고
#    "directory move failed: directory not found"로 실패. → NFC키→원본(NFD) 역매핑으로 원본 바이트 전달.
root = subprocess.run(["rclone","lsf",REMOTE,"--files-only"],capture_output=True,text=True).stdout
root_map = {N(l.strip()): l.strip() for l in root.splitlines() if l.strip()}
log = open(f"{WORK}/gdrive_moved.jsonl","a")

ok=deleted=skip=fail=0
for x in plan:
    src = x["src"]
    if N(src) not in root_map:          # 이미 처리됨
        skip += 1; continue
    real = root_map[N(src)]             # 루트 실제 이름(NFD 원본)
    if x["dest"] == "__DELETE__":
        r = subprocess.run(["rclone","deletefile",f"gdrive:{real}"],
                           capture_output=True,text=True,timeout=60)
        deleted += (r.returncode==0); continue
    newname = x.get("newname", N(src))
    if has_glob(real):                  # 대괄호 등 → moveto 불가, --files-from 사용
        r = move_via_files_from(real, x["dest"], newname)
    else:
        r = subprocess.run(["rclone","moveto",f"gdrive:{real}",f"gdrive:{x['dest']}/{newname}"],
                           capture_output=True,text=True,timeout=120)
    if r.returncode==0:
        ok += 1
        log.write(json.dumps({"src":src,"dest":f"{x['dest']}/{newname}"},ensure_ascii=False)+"\n"); log.flush()
    else:
        fail += 1; print(f"FAIL {N(src)[:40]}: {r.stderr.strip()[:80]}",flush=True)
log.close()
print(f"DONE ok={ok} deleted={deleted} skip={skip} fail={fail}")
# ⚠️ 완료판정: 이 출력만 믿지 말 것. 루트 파일수 감소분 = plan 대상수 인지 rclone lsf로 재검증.
