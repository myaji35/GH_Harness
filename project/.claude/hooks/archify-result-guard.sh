#!/bin/bash
# 전역 Stop 훅: 처리결과 HTML이 없는 완료 이슈 묶음에 한 번만 알린다.
[ "${ARCHIFY_RESULT_GUARD:-}" = "0" ] && exit 0

(
  input=$(cat) || exit 0
  python3 - "$input" "$PWD" "${ARCHIFY_RESULTS_DIR:-$HOME/.claude/archify-results}" <<'PYEOF'
import datetime
import json
import os
from pathlib import Path
import sys


def main():
    payload = json.loads(sys.argv[1])
    if payload.get("stop_hook_active") is True:
        return

    cwd = payload.get("cwd") or sys.argv[2]
    directory = Path(sys.argv[3]) / os.path.basename(os.path.normpath(cwd))
    pending = directory / ".pending.jsonl"
    if not pending.exists():
        return

    threshold = max(
        (path.stat().st_mtime for path in directory.glob("*.html")
         if not path.name.endswith(".visual-check.html") and path.is_file()),
        default=0,
    )
    issues = set()
    latest = None
    with pending.open(encoding="utf-8") as stream:
        for line in stream:
            if not line.strip():
                continue
            try:
                record = json.loads(line)
                ts = record["ts"]
                timestamp = datetime.datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp()
                issue = record["issue"]
                if not isinstance(issue, str):
                    raise ValueError("issue must be a string")
            except (ValueError, KeyError, TypeError):
                continue
            if timestamp > threshold:
                issues.add(issue)
                candidate = (timestamp, ts)
                if latest is None or candidate > latest:
                    latest = candidate

    count = len(issues)
    if count < 3:
        return

    last_ts = latest[1]
    nagged = directory / ".guard-nagged"
    if nagged.exists() and nagged.read_text(encoding="utf-8").strip() == last_ts:
        return

    issue_list = ", ".join(sorted(issues)[:8])
    if count > 8:
        issue_list += f" 외 {count - 8}건"
    output = json.dumps({
        "decision": "block",
        "reason": (
            f"[처리결과 미생성] 이번 작업에서 이슈 {count}건({issue_list})을 완료했지만 archify 처리결과가 없다. "
            "result-archify 스킬로 처리결과 HTML 을 만들고, 완료 보고에 file:// 링크를 붙여라. "
            "만들 수 없는 사정이면 그 이유를 보고하고 끝내라. (이 묶음에 대해 1회만 알림)"
        ),
    }, ensure_ascii=False)
    nagged.write_text(last_ts + "\n", encoding="utf-8")
    print(output)


try:
    main()
except Exception:
    pass
PYEOF
) 2>/dev/null || true

exit 0
