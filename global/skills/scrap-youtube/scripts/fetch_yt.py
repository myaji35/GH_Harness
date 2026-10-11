#!/usr/bin/env python3
# Fetch YouTube metadata and try one exact subtitle language at a time.
# Save a JSON record and print a compact transcript summary.

import argparse
import json
import re
import subprocess
import tempfile
import time
from pathlib import Path


def run_yt_dlp(args):
    return subprocess.run(
        ["yt-dlp", *args], capture_output=True, text=True, timeout=120, check=False
    )


def clean_vtt(raw):
    lines = []
    for line in raw.splitlines():
        line = line.strip()
        if not line or "-->" in line or line.startswith(("WEBVTT", "Kind:", "Language:", "NOTE", "STYLE", "REGION")):
            continue
        if re.fullmatch(r"\d+", line):
            continue
        line = re.sub(r"<[^>]*>", "", line)
        line = re.sub(r"\s+", " ", line).strip()
        if line and (not lines or lines[-1] != line):
            lines.append(line)
    return " ".join(lines)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("video_id")
    parser.add_argument("--out", default=".")
    args = parser.parse_args()
    video_id = args.video_id
    url = f"https://www.youtube.com/watch?v={video_id}"
    output_dir = Path(args.out)
    output_dir.mkdir(parents=True, exist_ok=True)
    output_path = output_dir / f"{video_id}.json"
    record = {
        "video_id": video_id, "url": url, "title": "", "channel": "",
        "upload_date": "", "duration": None, "view_count": None,
        "description": "", "chapters": [], "language": "",
        "transcript": "", "has_transcript": False, "transcript_words": 0,
        "transcript_lang": "", "transcript_source": "none", "error": "",
    }

    try:
        result = run_yt_dlp(["--dump-json", "--skip-download", url])
        if result.returncode != 0:
            raise RuntimeError(result.stderr.strip() or f"yt-dlp exited {result.returncode}")
        info = json.loads(result.stdout)
    except (OSError, subprocess.TimeoutExpired, json.JSONDecodeError, RuntimeError) as exc:
        record["error"] = str(exc)
        output_path.write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"{video_id} has_transcript=false words=0 lang= source=none")
        return 2

    for field in ("title", "upload_date", "duration", "view_count", "description", "chapters", "language"):
        record[field] = info.get(field) or (0 if field in ("duration", "view_count") else [] if field == "chapters" else "")
    record["channel"] = info.get("channel") or info.get("uploader") or ""

    attempts = [("manual", "ko"), ("manual", "en")]
    for lang in (info.get("language"), "en", "ko"):
        if lang and ("auto", lang) not in attempts:
            attempts.append(("auto", lang))

    with tempfile.TemporaryDirectory() as temp_dir:
        for index, (source, lang) in enumerate(attempts):
            if index:
                time.sleep(2)
            template = str(Path(temp_dir) / "caption.%(ext)s")
            result = None
            try:
                result = run_yt_dlp([
                    "--write-subs" if source == "manual" else "--write-auto-subs",
                    "--sub-langs", lang, "--sub-format", "vtt", "--skip-download",
                    "-o", template, url,
                ])
            except (OSError, subprocess.TimeoutExpired):
                pass
            for vtt in Path(temp_dir).glob("*.vtt"):
                transcript = clean_vtt(vtt.read_text(encoding="utf-8", errors="ignore"))
                vtt.unlink()
                if result is not None and result.returncode == 0 and transcript:
                    record.update(
                        transcript=transcript, has_transcript=True,
                        transcript_words=len(transcript.split()),
                        transcript_lang=lang, transcript_source=source,
                    )
                    break
            if record["has_transcript"]:
                break

    output_path.write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"{video_id} has_transcript={str(record['has_transcript']).lower()} words={record['transcript_words']} lang={record['transcript_lang']} source={record['transcript_source']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
