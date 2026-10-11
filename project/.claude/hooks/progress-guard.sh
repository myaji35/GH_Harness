#!/usr/bin/env bash
GH_PROGRESS_GUARD_INPUT="$(cat)" python3 <<'PYEOF'
import datetime as dt
import json
import os
from pathlib import Path
import sys

try:
    hook = json.loads(os.environ["GH_PROGRESS_GUARD_INPUT"])
    if hook.get("stop_hook_active") is True:
        sys.exit(0)
    session = hook.get("session_id")
    if not isinstance(session, str) or not session or session in {".", ".."} or "/" in session or "\\" in session:
        sys.exit(0)
    registry = json.loads(Path(".claude/issue-db/registry.json").read_text(encoding="utf-8"))
    cache = Path.home() / ".cache/gh-harness/progress-guard" / session
    seen = set(cache.read_text(encoding="utf-8").splitlines()) if cache.exists() else set()
    now = dt.datetime.now(dt.timezone.utc)
    missing = []
    for issue in registry["issues"]:
        payload = issue.get("payload") or {}
        if issue.get("status") != "IN_PROGRESS" or payload.get("session_id") != session:
            continue
        progress = payload.get("progress") or {}
        at = progress.get("at")
        try:
            parsed = dt.datetime.fromisoformat(at.replace("Z", "+00:00"))
            if parsed.tzinfo is None:
                parsed = parsed.astimezone()
            stale = now - parsed.astimezone(dt.timezone.utc) > dt.timedelta(hours=2)
        except (AttributeError, TypeError, ValueError, OverflowError):
            stale = True
        if stale and issue.get("id") not in seen:
            missing.append(issue["id"])
    if missing:
        cache.parent.mkdir(parents=True, exist_ok=True)
        with cache.open("a", encoding="utf-8") as stream:
            for issue_id in missing:
                stream.write(issue_id + "\n")
        ids = ", ".join(missing)
        reason = (f"진행 중 이슈 {ids}의 중단 지점이 기록되지 않았습니다. "
                  f"끝났으면 on_complete.sh 로 완료 처리하고, 아니면 bash .claude/hooks/progress-note.sh {missing[0]} "
                  '"어디까지" "다음 할 일" 을 실행하세요.')
        print(json.dumps({"decision": "block", "reason": reason}, ensure_ascii=False))
except BaseException:
    pass
PYEOF
