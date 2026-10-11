#!/usr/bin/env bash
if [ "$#" -lt 3 ]; then
  echo '사용법: progress-note.sh ISS-NNN "어디까지 했나" "다음 할 일"' >&2
  exit 2
fi

python3 - "$1" "$2" "$3" <<'PYEOF'
import datetime as dt
import json
import os
import sys
import tempfile

issue_id, done, next_step = sys.argv[1:4]
path = ".claude/issue-db/registry.json"
try:
    with open(path, encoding="utf-8") as stream:
        registry = json.load(stream)
    issue = next((item for item in registry["issues"] if item.get("id") == issue_id), None)
    if issue is None:
        print(f"오류: 이슈 {issue_id}을(를) 찾지 못했습니다.", file=sys.stderr)
        sys.exit(1)
    now = dt.datetime.now().astimezone().isoformat(timespec="seconds")
    issue.setdefault("payload", {})["progress"] = {"at": now, "done": done, "next": next_step}
    issue["updated_at"] = now
    for lib in (os.environ.get("HARNESS_HOOK_LIB", ""),
                os.path.join(os.environ.get("HOME", ""), ".claude/harness-core/hooks/lib"),
                os.path.realpath(".claude/hooks/lib")):
        if os.path.isdir(lib) and lib not in sys.path:
            sys.path.insert(0, lib)
    try:
        from registry_lock import atomic_write_json
    except ImportError:
        def atomic_write_json(target, data):
            fd, temporary = tempfile.mkstemp(dir=os.path.dirname(os.path.abspath(target)))
            try:
                with os.fdopen(fd, "w", encoding="utf-8") as stream:
                    json.dump(data, stream, ensure_ascii=False, indent=2)
                    stream.write("\n")
                os.replace(temporary, target)
            finally:
                if os.path.exists(temporary):
                    os.unlink(temporary)
    atomic_write_json(path, registry)
except (OSError, ValueError, KeyError, TypeError) as exc:
    print(f"오류: 진행 기록을 저장하지 못했습니다 ({type(exc).__name__}).", file=sys.stderr)
    sys.exit(1)
PYEOF
