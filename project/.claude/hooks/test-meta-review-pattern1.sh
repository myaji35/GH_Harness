#!/bin/bash
set -euo pipefail

HOOK_DIR=$(cd "$(dirname "$0")" && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/.claude/hooks/lib" "$TMP_DIR/.claude/issue-db"
cp "$HOOK_DIR/meta-review.sh" "$TMP_DIR/.claude/hooks/meta-review.sh"
cp "$HOOK_DIR/lib/issue_id.py" "$TMP_DIR/.claude/hooks/lib/issue_id.py"
if [ -f "$HOOK_DIR/lib/registry_lock.py" ]; then
  cp "$HOOK_DIR/lib/registry_lock.py" "$TMP_DIR/.claude/hooks/lib/registry_lock.py"
fi

python3 - "$TMP_DIR" <<'PYEOF'
import datetime
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
recent = datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z")

def registry(statuses, retries):
    issues = []
    for number, (status, retry_count) in enumerate(zip(statuses, retries), 1):
        issues.append({
            "id": f"ISS-{number}",
            "title": f"fixture {number}",
            "type": "FIX_BUG",
            "status": status,
            "priority": "P1",
            "assign_to": "fixture-agent",
            "retry_count": retry_count,
            "created_at": recent,
            "payload": {"files": ["src/foo.ts"]},
        })
    return {
        "issues": issues,
        "stats": {"total_issues": len(issues)},
        "knowledge": {},
        "hooks": {},
    }

fixtures = root / "fixtures"
fixtures.mkdir()
(fixtures / "registry-a.json").write_text(
    json.dumps(registry(["DONE"] * 3, [0] * 3)), encoding="utf-8"
)
(fixtures / "registry-b.json").write_text(
    json.dumps(registry(["DONE", "FAILED", "DONE"], [1, 0, 2])), encoding="utf-8"
)
PYEOF

run_fixture() {
  local fixture=$1
  cp "$TMP_DIR/fixtures/registry-$fixture.json" "$TMP_DIR/.claude/issue-db/registry.json"
  (cd "$TMP_DIR" && bash .claude/hooks/meta-review.sh >/dev/null) || {
    local status=$?
    [ "$status" -eq 2 ] || return "$status"
  }
}

has_target_refactor() {
  python3 - "$TMP_DIR/.claude/issue-db/registry.json" <<'PYEOF'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as registry_file:
    issues = json.load(registry_file).get("issues", [])
found = any(
    issue.get("type") == "REFACTOR"
    and issue.get("payload", {}).get("target_file") == "src/foo.ts"
    for issue in issues
)
raise SystemExit(0 if found else 1)
PYEOF
}

run_fixture a
if has_target_refactor; then
  echo "FAIL: fixture A created a REFACTOR issue" >&2
  exit 1
fi
echo "PASS: fixture A did not create a REFACTOR issue"

run_fixture b
if ! has_target_refactor; then
  echo "FAIL: fixture B did not create a REFACTOR issue" >&2
  exit 1
fi
echo "PASS: fixture B created a REFACTOR issue"
