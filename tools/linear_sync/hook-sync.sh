#!/usr/bin/env bash

# Claude Code passes hook data on stdin; the sync does not use it.
cat >/dev/null 2>&1

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)" || exit 0
[[ -f "$repo_root/tools/linear_sync/.env" ]] || exit 0

stamp="$HOME/.cache/gh-harness/linear-sync.stamp"
if [[ -f "$stamp" ]]; then
  modified="$(stat -f %m "$stamp" 2>/dev/null)"
  now="$(date +%s)"
  if [[ "$modified" =~ ^[0-9]+$ ]] && (( now - modified < 600 )); then
    exit 0
  fi
fi

pgrep -f '(linear_sync|portfolio_sync)[.]py' >/dev/null 2>&1 && exit 0

log="$HOME/Library/Logs/gh-harness-linear-sync.log"
mkdir -p "$(dirname "$stamp")" "$(dirname "$log")" >/dev/null 2>&1 || exit 0
touch "$stamp" >/dev/null 2>&1 || exit 0

cd "$repo_root" || exit 0
nohup python3 tools/linear_sync/portfolio_sync.py --apply </dev/null >>"$log" 2>&1 &
exit 0
