#!/usr/bin/env python3
"""영상 ID로 자막+메타데이터 추출. yt-dlp 사용 (fetch API는 유튜브가 차단).
사용: python3 fetch_video.py <video_id>
출력: JSON {title, channel, upload_date, duration, description, chapters, transcript, has_transcript}
자막 우선순위: 수동자막 > 자동자막(en). 없으면 has_transcript=false → 설명 기반 폴백."""
import sys, os, re, json, subprocess, tempfile

VID = sys.argv[1]
WORK = os.environ.get("YT_WORK", os.path.expanduser("~/.youtube-archiver"))
os.makedirs(WORK, exist_ok=True)
URL = f"https://www.youtube.com/watch?v={VID}"

# 1) 메타데이터 (--dump-json, 다운로드 없이)
meta = {}
try:
    r = subprocess.run(["yt-dlp", "--dump-json", "--skip-download", URL],
                       capture_output=True, text=True, timeout=120)
    if r.returncode == 0:
        j = json.loads(r.stdout)
        meta = {
            "title": j.get("title", ""),
            "channel": j.get("channel") or j.get("uploader", ""),
            "upload_date": j.get("upload_date", ""),  # YYYYMMDD
            "duration": j.get("duration", 0),
            "view_count": j.get("view_count", 0),
            "description": (j.get("description") or "")[:2000],
            "chapters": [{"t": c.get("start_time"), "title": c.get("title")} for c in (j.get("chapters") or [])],
        }
except Exception as e:
    meta = {"error": str(e)}

# 2) 자막 다운로드 (수동 우선, 없으면 자동 en)
transcript = ""
subpath = os.path.join(WORK, f"cap_{VID}")
for args in (["--write-subs", "--sub-langs", "ko.*,ko,en.*,en"],
             ["--write-auto-subs", "--sub-langs", "ko.*,ko,en.*,en"]):
    try:
        subprocess.run(["yt-dlp"] + args + ["--skip-download", "--sub-format", "vtt",
                        "-o", subpath + ".%(ext)s", URL],
                       capture_output=True, text=True, timeout=120)
    except Exception:
        pass
    # 받은 vtt 찾기
    found = [f for f in os.listdir(WORK) if f.startswith(f"cap_{VID}") and f.endswith(".vtt")]
    if found:
        raw = open(os.path.join(WORK, found[0]), encoding="utf-8", errors="ignore").read()
        seen = []
        for l in raw.split("\n"):
            l = l.strip()
            if not l or "-->" in l or l.startswith(("WEBVTT", "Kind:", "Language:")):
                continue
            l = re.sub(r"<[^>]+>", "", l)
            l = l.strip()
            if l and (not seen or seen[-1] != l):
                seen.append(l)
        transcript = re.sub(r"\s+", " ", " ".join(seen)).strip()
        # 정리
        for f in found:
            try: os.remove(os.path.join(WORK, f))
            except: pass
        if transcript:
            break

out = dict(meta)
out["video_id"] = VID
out["url"] = URL
out["transcript"] = transcript
out["has_transcript"] = bool(transcript)
out["transcript_words"] = len(transcript.split()) if transcript else 0
print(json.dumps(out, ensure_ascii=False))
