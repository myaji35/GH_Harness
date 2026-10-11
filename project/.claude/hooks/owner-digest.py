#!/usr/bin/env python3
"""열린 이슈에서 대표님이 확인할 목록을 읽기 전용으로 출력한다."""

import datetime as dt
import json
from pathlib import Path
import re


OPEN = {"READY", "IN_PROGRESS", "PARTIAL", "HANDED_OFF", "AWAITING_USER", "BLOCKED_USER", "BACKLOG"}
DECISION_TAGS = ("[결정필요]", "[T2]", "[CONFIRM]")
GROUPS = ("대표님 답을 기다리는 것", "아이디어로만 남은 것", "지시했는데 아직 안 끝난 것")


def age(issue):
    progress = (issue.get("payload") or {}).get("progress") or {}
    value = progress.get("at") or issue.get("created_at")
    try:
        parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
        if parsed.tzinfo is None:
            parsed = parsed.astimezone()
        return max(0, (dt.datetime.now().astimezone() - parsed).days)
    except (AttributeError, TypeError, ValueError, OverflowError):
        return None


def group(issue):
    title = issue.get("title") or ""
    status = issue.get("status")
    origin = (issue.get("payload") or {}).get("origin")
    if status in {"AWAITING_USER", "BLOCKED_USER", "HANDED_OFF"} or any(tag in title for tag in DECISION_TAGS):
        return GROUPS[0]
    if origin == "intent-gate:idea":
        return GROUPS[1]
    return GROUPS[2]


def main():
    try:
        data = json.loads(Path(".claude/issue-db/registry.json").read_text(encoding="utf-8"))
        issues = [item for item in data["issues"] if isinstance(item, dict) and item.get("status") in OPEN]
    except (OSError, ValueError, KeyError, TypeError):
        return
    if not issues:
        return
    buckets = {name: [] for name in GROUPS}
    automated = 0
    for issue in issues:
        title = issue.get("title") or ""
        origin = (issue.get("payload") or {}).get("origin")
        if title.startswith("[Plan:") or origin in {"self", "restored-from-linear"}:
            automated += 1
            continue
        buckets[group(issue)].append(issue)
    print(f"━━━ 📋 대표님 결정 목록 (열린 이슈 {len(issues)}건) ━━━")
    for name in GROUPS:
        entries = buckets[name]
        if not entries:
            continue
        entries.sort(key=lambda item: age(item) if age(item) is not None else -1, reverse=True)
        print(f"{name} ({len(entries)}건)")
        for issue in entries[:8]:
            days = age(issue)
            title = re.sub(r"^\[[^\]\n]+\]\s*", "", issue.get("title") or "", count=1)[:48]
            print(f"  {issue.get('id', '?')}  {issue.get('priority', '?')}  {str(days) + '일' if days is not None else '?'}  {title}")
            progress = (issue.get("payload") or {}).get("progress")
            if isinstance(progress, dict):
                done = str(progress.get("done") or "")[:60]
                next_step = str(progress.get("next") or "")[:60]
                print(f"      ↳ 어디까지: {done} / 다음: {next_step}")
        if len(entries) > 8:
            print(f"  … 외 {len(entries) - 8}건")
    if automated:
        print(f"기계 자동 파생 이슈 {automated}건")
    print('→ 중단 지점 기록: bash .claude/hooks/progress-note.sh ISS-NNN "어디까지" "다음 할 일"')


if __name__ == "__main__":
    main()
