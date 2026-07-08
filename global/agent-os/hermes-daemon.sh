#!/bin/bash
# hermes-daemon.sh — Hermes 자율 운영 데몬 (launchd 외장볼륨 제약 우회)
AOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PATH="/Applications/cmux.app/Contents/Resources/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
while true; do
  if [ ! -f "$AOS_DIR/hermes.stop" ]; then
    bash "$AOS_DIR/hermes-run.sh" >> "$AOS_DIR/hermes.daemon.log" 2>&1
  fi
  sleep 300
done
