#!/bin/bash
# rtk-guard.sh — RTK 토큰 절약 hook의 안전 래퍼 (v5.3)
# rtk 바이너리가 설치된 경우에만 'rtk hook claude'를 위임하고,
# 미설치 프로젝트에서는 입력을 그대로 통과(no-op)시킨다.
# → 배포 템플릿에 박아도 rtk 없는 프로젝트가 깨지지 않음.
#
# PreToolUse(Bash)에서 secret-guard 뒤(맨 마지막)에 실행되어야 한다.
# (secret-guard가 원본 command를 먼저 스캔 → RTK 재작성이 시크릿 스캔 우회 불가)
set -euo pipefail

# stdin(JSON) 보존
INPUT="$(cat)"

if command -v rtk >/dev/null 2>&1; then
  printf '%s' "$INPUT" | rtk hook claude
else
  # rtk 미설치 → 입력 그대로 통과(명령 재작성 없음). exit 0.
  :
fi
exit 0
