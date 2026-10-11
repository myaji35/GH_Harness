#!/usr/bin/env python3
# Validate scrap notes and report errors or missing body sections.
# Check shared frontmatter fields plus platform-specific requirements.

import argparse
import re
from collections import defaultdict
from pathlib import Path

import yaml


HEADERS = ("## 한 줄", "## 핵심 내용", "## 써먹을 곳")
BAD_NAME = re.compile(r'[/\\:*?"<>|\[\]#^]')


def check_note(path, platform_override):
    errors = []
    warnings = []
    if BAD_NAME.search(path.name):
        errors.append("invalid filename")
    text = path.read_text(encoding="utf-8")
    match = re.match(r"\A---\s*\n(.*?)\n---\s*(?:\n|\Z)", text, re.S)
    if not match:
        return None, [*errors, "missing YAML frontmatter"], warnings
    try:
        data = yaml.safe_load(match.group(1))
    except yaml.YAMLError as exc:
        return None, [*errors, f"YAML parse failed: {exc.problem or exc}"], warnings
    if not isinstance(data, dict):
        return None, [*errors, "frontmatter must be a mapping"], warnings

    def required(name):
        if name not in data or data[name] is None or data[name] == "":
            errors.append(f"missing {name}")

    for field in ("platform", "author", "clipped", "origin_list"):
        required(field)
    if not isinstance(data.get("categories"), list) or "[[스크랩]]" not in data["categories"]:
        errors.append("categories must be a list containing [[스크랩]]")
    if not isinstance(data.get("title"), str) or not data["title"].strip():
        errors.append("title must be a nonempty string")
    source = data.get("source")
    if not isinstance(source, str) or not source.startswith("http"):
        errors.append("source must start with http")
    for field in ("topics", "use_for"):
        if not isinstance(data.get(field), list):
            errors.append(f"{field} must be a list")
    if not isinstance(data.get("summary"), str):
        errors.append("summary must be a string")
    if data.get("status") not in ("new", "used", "archived"):
        errors.append("invalid status")
    if data.get("origin_status") not in ("kept", "removed"):
        errors.append("invalid origin_status")

    platform = platform_override or data.get("platform")
    if data.get("platform") != platform:
        errors.append(f"platform must be {platform}")
    if platform == "youtube":
        video_id = data.get("video_id")
        if not isinstance(video_id, str) or len(video_id) != 11:
            errors.append("video_id must be 11 characters")
        elif isinstance(source, str) and video_id not in source:
            errors.append("source must contain video_id")
        if data.get("depth") not in ("심층", "표준", "로그"):
            errors.append("invalid depth")
        if not isinstance(data.get("transcript"), bool):
            errors.append("transcript must be a boolean")
    elif platform == "instagram":
        if data.get("kind") not in ("상품", "서비스", "장소", "정보", "영감", "광고"):
            errors.append("invalid kind")
        if data.get("confidence") not in ("높음", "중간", "낮음"):
            errors.append("invalid confidence")
        for field in ("official_site", "buy_link"):
            value = data.get(field)
            if not isinstance(value, str) or (not value.startswith("http") and value != "확인 안 됨"):
                errors.append(f"invalid {field}")
        for field in ("price", "shipping"):
            if field not in data:
                errors.append(f"missing {field}")
    else:
        errors.append("platform must be youtube or instagram")

    body = text[match.end():]
    for header in HEADERS:
        if not re.search(rf"^{re.escape(header)}\s*$", body, re.M):
            warnings.append(f"missing {header}")
    return source if isinstance(source, str) else None, errors, warnings


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("folder", type=Path)
    parser.add_argument("--platform", choices=("youtube", "instagram"))
    args = parser.parse_args()

    results = {}
    sources = defaultdict(list)
    for path in sorted(args.folder.glob("*.md")):
        source, errors, warnings = check_note(path, args.platform)
        results[path] = (errors, warnings)
        if source:
            sources[source].append(path)
    for paths in sources.values():
        if len(paths) > 1:
            for path in paths:
                results[path][0].append("duplicate source")

    counts = {"OK": 0, "WARN": 0, "ERROR": 0}
    for path, (errors, warnings) in results.items():
        status = "ERROR" if errors else "WARN" if warnings else "OK"
        counts[status] += 1
        detail = "; ".join(errors + warnings)
        print(f"{path.name}: {status}" + (f" - {detail}" if detail else ""))
    print(f"Total: OK={counts['OK']} WARN={counts['WARN']} ERROR={counts['ERROR']}")
    return 1 if counts["ERROR"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
