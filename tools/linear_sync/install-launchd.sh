#!/bin/bash
set -euo pipefail

label=com.gh-harness.linear-sync
domain="gui/$(id -u)"
agents_dir="$HOME/Library/LaunchAgents"
target="$agents_dir/$label.plist"
service="$domain/$label"

if [[ $# -gt 1 || ( $# -eq 1 && $1 != --uninstall ) ]]; then
    echo "Usage: $0 [--uninstall]" >&2
    exit 2
fi

if [[ ${1:-} == --uninstall ]]; then
    if launchctl print "$service" >/dev/null 2>&1; then
        launchctl bootout "$domain" "$target"
    fi
    rm -f "$target"
    echo "Removed $target"
    exit 0
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repo="$(cd "$script_dir/../.." && pwd -P)"
template="$script_dir/$label.plist.template"

mkdir -p "$agents_dir" "$HOME/Library/Logs"
tmp="$(mktemp "$agents_dir/.$label.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

/usr/bin/python3 - "$template" "$tmp" "$repo" "$HOME" <<'PY'
import sys
from pathlib import Path
from xml.sax.saxutils import escape

template, target, repo, home = sys.argv[1:]
content = Path(template).read_text(encoding="utf-8")
content = content.replace("__REPO__", escape(repo))
content = content.replace("__HOME__", escape(home))
Path(target).write_text(content, encoding="utf-8")
PY

plutil -lint "$tmp"
if launchctl print "$service" >/dev/null 2>&1; then
    launchctl bootout "$domain" "$target"
fi
mv -f "$tmp" "$target"
launchctl bootstrap "$domain" "$target"
echo "Installed $target"
