#!/bin/bash
# self-audit.sh — registry 무결성 경고(비차단)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY="${1:-.claude/issue-db/registry.json}"

if [ ! -f "$REGISTRY" ]; then
  echo "⚠️ [self-audit] registry.json 없음: $REGISTRY"
  exit 0
fi

python3 - "$SCRIPT_DIR" "$REGISTRY" <<'PYEOF'
import json, os, sys

__file__ = os.path.join(sys.argv[1], "self-audit.sh")
sys.path.insert(0, os.path.join(os.path.dirname(__file__),'lib'))
from issue_id import validate_sequence

try:
    with open(sys.argv[2], "r", encoding="utf-8") as registry_file:
        registry = json.load(registry_file)
except Exception as exc:
    print(f"⚠️ [self-audit] registry 로딩 실패: {exc}")
else:
    for problem in validate_sequence(registry):
        print(f"⚠️ [self-audit] {problem}")
PYEOF

exit 0
