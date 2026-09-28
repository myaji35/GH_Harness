#!/usr/bin/env python3
"""Mirror selected Claude and Hermes knowledge into an Obsidian vault."""

import argparse
import hashlib
import json
import os
import re
import sys
import tempfile
import time
from datetime import datetime
from pathlib import Path


DEFAULT_VAULT = "/Users/gangseungsig/Library/Mobile Documents/iCloud~md~obsidian/Documents/Obsidian"
EXCLUDED_NAME = re.compile(
    r"계좌|통장|채무|채권|등기|주민|세무|급여|연봉|계약서|개인정보|공제금|보험|대출|신용|credential|password|corporate-account",
    re.IGNORECASE,
)
MASKS = (
    (re.compile(r"(?<!\d)01[016-9]-?\d{3,4}-?\d{4}(?!\d)"), "<휴대폰번호>"),
    (re.compile(r"(?<!\d)\d{6}-[1-4]\d{6}(?!\d)"), "<주민번호>"),
    (re.compile(r"(?<!\d)\d{3}-\d{2}-\d{5}(?!\d)"), "<사업자번호>"),
    (
        re.compile(
            r"(?<![A-Za-z0-9])(?:AIza[0-9A-Za-z_-]{35}|sk-ant-[A-Za-z0-9_-]{20,}|sk-[A-Za-z0-9]{20,}|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{22,}|AKIA[0-9A-Z]{16})"
        ),
        "<시크릿>",
    ),
    (re.compile(r"(?<!\d)\d{3,6}-\d{2,6}-\d{4,8}(?!\d)"), "<계좌번호>"),
)
GUIDE = """# AI 지식 동기화 안내

이 구역은 기계가 관리하는 단방향 동기화 사본입니다.
여기 있는 파일은 직접 고치지 마세요. 원본을 수정하세요.
원본: ~/.claude/CLAUDE.md, ~/.claude/skills, ~/.claude/projects, ~/.hermes/memories
동기화 시점: Claude 세션 종료 및 Hermes 새벽 cron 실행 시
1단계 범위: Claude 전역 규칙, 스킬 목록, 선별된 프로젝트 기억, Hermes 기억
사라진 원본의 사본은 _보관 날짜 폴더로 이동합니다.
"""


def configured(name, default):
    return Path(os.environ.get(name, default)).expanduser().absolute()


def safe_path(zone, relative):
    """Reject traversal and symlink escapes before any vault mutation."""
    candidate = zone / relative
    if (not zone.is_symlink()
            and zone.resolve(strict=False).is_relative_to(zone.parent.resolve(strict=False))
            and candidate.resolve(strict=False).is_relative_to(zone.resolve(strict=False))):
        return candidate
    raise ValueError("destination outside AI knowledge zone")


def atomic_write(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    temp_name = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", dir=path.parent, prefix=".ai-knowledge-",
            delete=False,
        ) as handle:
            temp_name = handle.name
            handle.write(content)
        os.replace(temp_name, path)
    finally:
        if temp_name and os.path.exists(temp_name):
            os.unlink(temp_name)


def mask(body):
    for pattern, replacement in MASKS:
        body = pattern.sub(replacement, body)
    return body


def frontmatter(text):
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return []
    for index in range(1, len(lines)):
        if lines[index].strip() == "---":
            return lines[1:index]
    return []


def scalar(value):
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] == '"':
        try:
            return json.loads(value)
        except json.JSONDecodeError:
            return value[1:-1]
    if len(value) >= 2 and value[0] == value[-1] == "'":
        return value[1:-1].replace("''", "'")
    return value.split(" #", 1)[0].strip()


def field(lines, key):
    """Read the first matching YAML-like scalar, including block descriptions."""
    pattern = re.compile(r"^([ \t]*)" + re.escape(key) + r"\s*:\s*(.*)$", re.IGNORECASE)
    for index, line in enumerate(lines):
        match = pattern.match(line)
        if not match:
            continue
        value = match.group(2)
        if value.startswith(("|", ">")):
            indent = len(match.group(1).expandtabs(2))
            block = []
            for following in lines[index + 1:]:
                if following.strip() and len(following) - len(following.lstrip()) <= indent:
                    break
                block.append(following.strip())
            return ("\n" if value.startswith("|") else " ").join(block).strip()
        return scalar(value)
    return None


def project_name(directory):
    name = directory.name
    return name.split("-nosync-", 1)[1] if "-nosync-" in name else name.split("-")[-1]


def source_label(path):
    resolved = str(path.resolve(strict=False))
    home = str(Path.home())
    return "~" + resolved[len(home):] if resolved == home or resolved.startswith(home + os.sep) else resolved


def record(body, source, kind, memory_type=None, project=None):
    body = mask(body)
    digest = hashlib.sha256(body.encode("utf-8")).hexdigest()[:16]
    label = source_label(source)
    fields = ["---", "ai_knowledge: true", "source: " + json.dumps(label, ensure_ascii=False),
              "kind: " + kind]
    if memory_type is not None:
        fields.append("type: " + memory_type)
        fields.append("project: " + json.dumps(project, ensure_ascii=False))
    fields.extend(("content_hash: " + digest,
                   "synced_at: " + datetime.now().astimezone().isoformat(timespec="seconds"),
                   "---", "> 기계 동기화 사본 — 직접 고치지 마라. 원본: `" + label + "`", "", body))
    return digest, "\n".join(fields)


def load_state(path):
    if not path.exists():
        return {}
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict) or any(not isinstance(k, str) or not isinstance(v, str)
                                         for k, v in data.items()):
        raise ValueError("invalid state format")
    return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args()
    started = time.monotonic()
    vault = configured("AIK_VAULT", DEFAULT_VAULT)
    zone_name = os.environ.get("AIK_ZONE", "07-AI-Knowledge")
    if not vault.is_dir() or not os.access(vault, os.R_OK | os.W_OK | os.X_OK):
        print("ai-knowledge-sync: 볼트가 없거나 접근할 수 없습니다.", file=sys.stderr)
        return
    if len(Path(zone_name).parts) != 1 or zone_name in ("", ".", ".."):
        print("ai-knowledge-sync: AIK_ZONE 경로가 유효하지 않습니다.", file=sys.stderr)
        return
    zone = vault / zone_name
    if zone.is_symlink() or not zone.resolve(strict=False).is_relative_to(vault.resolve()):
        print("ai-knowledge-sync: 동기화 구역이 볼트 밖을 가리킵니다.", file=sys.stderr)
        return

    projects = configured("AIK_PROJECTS", "~/.claude/projects")
    claude_md = configured("AIK_CLAUDE_MD", "~/.claude/CLAUDE.md")
    skills = configured("AIK_SKILLS", "~/.claude/skills")
    hermes = configured("AIK_HERMES_MEM", "~/.hermes/memories")
    state_path = configured("AIK_STATE", "~/.claude/ai-knowledge-sync.state.json")
    last_path = Path.home() / ".claude/ai-knowledge-sync.last.json"
    counts = dict(targets=0, new=0, updated=0, same=0, archived=0, excluded=0, errors=0)
    errors = []

    def error(path, exc):
        counts["errors"] += 1
        if len(errors) < 20:
            errors.append({"path": str(path), "type": type(exc).__name__})

    try:
        state = load_state(state_path)
    except Exception as exc:
        error(state_path, exc)
        state = {}
    next_state = dict(state)
    targets = {}

    def add(relative, body, source, kind, memory_type=None, project=None):
        try:
            destination = safe_path(zone, relative)
            targets[str(relative)] = (destination, *record(body, source, kind, memory_type, project))
        except Exception as exc:
            error(relative, exc)

    try:
        if claude_md.is_file():
            add(Path("규칙/Claude-전역규칙.md"), claude_md.read_text(encoding="utf-8"), claude_md, "rule")
    except Exception as exc:
        error(claude_md, exc)

    try:
        skill_rows = []
        if skills.is_dir():
            for directory in sorted(skills.iterdir()):
                try:
                    if not directory.is_dir():
                        continue
                    source = next((directory / name for name in ("SKILL.md", "skill.md")
                                   if (directory / name).is_file()), None)
                    if source is None:
                        continue
                    meta = frontmatter(source.read_text(encoding="utf-8"))
                    name = field(meta, "name") or directory.name
                    description = field(meta, "description") or ""
                    skill_rows.append((str(name), str(description)))
                except Exception as exc:
                    error(directory, exc)
        skill_rows.sort(key=lambda row: row[0].casefold())
        rows = ["# Claude 스킬 목록", "", "| 이름 | 설명 |", "| --- | --- |"]
        for name, description in skill_rows:
            clean_name = name.replace("|", "\\|").replace("\n", " ")
            clean_description = description[:300].replace("|", "\\|").replace("\n", " ")
            rows.append("| " + clean_name + " | " + clean_description + " |")
        add(Path("규칙/Claude-스킬목록.md"), "\n".join(rows) + "\n", skills, "skills")
    except Exception as exc:
        error(skills, exc)

    try:
        if projects.is_dir():
            for directory in sorted(projects.iterdir()):
                if not directory.is_dir():
                    continue
                if directory.name.startswith(("-var-folders", "-private-")):
                    counts["excluded"] += 1
                    continue
                memory_dir = directory / "memory"
                if not memory_dir.is_dir():
                    continue
                for source in sorted(memory_dir.glob("*.md")):
                    if source.name == "MEMORY.md" or source.name.startswith("._") or EXCLUDED_NAME.search(source.stem):
                        counts["excluded"] += 1
                        continue
                    try:
                        body = source.read_text(encoding="utf-8")
                        memory_type = field(frontmatter(body), "type")
                        if memory_type not in ("feedback", "user", "reference"):
                            counts["excluded"] += 1
                            continue
                        project = project_name(directory)
                        add(Path("프로젝트") / project / source.name, body, source,
                            "memory", memory_type, project)
                    except Exception as exc:
                        error(source, exc)
    except Exception as exc:
        error(projects, exc)

    for filename in ("MEMORY.md", "USER.md"):
        source = hermes / filename
        try:
            if source.is_file():
                add(Path("Hermes") / ("Hermes-" + filename), source.read_text(encoding="utf-8"),
                    source, "hermes")
        except Exception as exc:
            error(source, exc)

    counts["targets"] = len(targets)
    for relative, (destination, digest, content) in targets.items():
        try:
            # Recheck after discovery in case a directory was changed to a symlink.
            safe_path(zone, Path(relative))
            if state.get(relative) == digest and destination.is_file():
                counts["same"] += 1
                continue
            is_new = not destination.exists()
            if not args.dry_run:
                atomic_write(destination, content)
                next_state[relative] = digest
            counts["new" if is_new else "updated"] += 1
        except Exception as exc:
            error(destination, exc)

    today = datetime.now().astimezone().date().isoformat()
    if counts["errors"] == 0:
        for relative in state.keys() - targets.keys():
            try:
                old = safe_path(zone, Path(relative))
                archive = safe_path(zone, Path("_보관") / today / relative)
                if old.exists():
                    if not args.dry_run:
                        archive.parent.mkdir(parents=True, exist_ok=True)
                        safe_path(zone, Path("_보관") / today / relative)
                        os.replace(old, archive)
                    counts["archived"] += 1
                if not args.dry_run:
                    next_state.pop(relative, None)
            except Exception as exc:
                error(relative, exc)

    if not args.dry_run:
        try:
            guide = safe_path(zone, Path("00-안내.md"))
            if not guide.exists():
                atomic_write(guide, GUIDE)
            atomic_write(state_path, json.dumps(next_state, ensure_ascii=False, indent=2) + "\n")
        except Exception as exc:
            error(zone, exc)
        try:
            result = {"ts": datetime.now().astimezone().isoformat(timespec="seconds"),
                      "counts": counts, "errors": errors}
            atomic_write(last_path, json.dumps(result, ensure_ascii=False, indent=2) + "\n")
        except Exception:
            pass

    if not args.quiet:
        elapsed = round((time.monotonic() - started) * 1000)
        print(f"ai-knowledge-sync: 대상 {counts['targets']} / 신규 {counts['new']} / "
              f"갱신 {counts['updated']} / 동일 {counts['same']} / 보관 {counts['archived']} / "
              f"제외 {counts['excluded']} / 오류 {counts['errors']} ({elapsed}ms)")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        # Claude's stop hook must never fail because of this optional mirror.
        print("ai-knowledge-sync: " + type(exc).__name__, file=sys.stderr)
    sys.exit(0)
