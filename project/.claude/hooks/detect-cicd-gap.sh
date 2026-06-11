#!/usr/bin/env bash
# detect-cicd-gap.sh
# v5.1 — CI/CD 부재 감지 (GitHub Actions 기준)
# "CI/CD 개념 없이 운영되는 프로젝트"를 harness가 상시 탐지 → CICD_BOOTSTRAP 이슈 주입.
#
# 사용:
#   bash detect-cicd-gap.sh            # gap 여부만 stdout: "GAP" | "OK" | "SKIP:<이유>"
#   bash detect-cicd-gap.sh --json     # 세부 시그널 JSON
#   bash detect-cicd-gap.sh --explain  # 사람이 읽는 설명
#
# 판정:
#   GAP  → git repo이고 GitHub remote 있으나 .github/workflows/*.yml 이 하나도 없음
#   OK   → 워크플로 파일이 1개 이상 존재 (이미 CI/CD 있음)
#   SKIP → git repo 아님 / GitHub remote 없음 (Actions 기준 부적합)

set -euo pipefail

MODE="${1:-detect}"
ROOT_DIR="$(pwd)"

# --- git repo 확인 ---
if ! git -C "$ROOT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  case "$MODE" in
    --json)    echo '{"verdict":"SKIP","reason":"not_a_git_repo","workflows":0}' ;;
    --explain) echo "git 저장소가 아님 — CI/CD gap 판정 대상 아님" ;;
    *)         echo "SKIP:not_a_git_repo" ;;
  esac
  exit 0
fi

# --- GitHub remote 확인 ---
REMOTE_URL="$(git -C "$ROOT_DIR" remote get-url origin 2>/dev/null || echo "")"
IS_GITHUB=0
if echo "$REMOTE_URL" | grep -qiE "github\.com"; then
  IS_GITHUB=1
fi

# --- 워크플로 파일 카운트 ---
WF_DIR="$ROOT_DIR/.github/workflows"
WF_COUNT=0
if [[ -d "$WF_DIR" ]]; then
  WF_COUNT=$(find "$WF_DIR" -maxdepth 1 -type f \( -name "*.yml" -o -name "*.yaml" \) 2>/dev/null | wc -l | tr -d ' ')
fi

# --- 판정 ---
VERDICT="OK"
REASON="workflows_present"

if [[ "$IS_GITHUB" -eq 0 ]]; then
  VERDICT="SKIP"
  REASON="no_github_remote"
elif [[ "$WF_COUNT" -eq 0 ]]; then
  VERDICT="GAP"
  REASON="no_workflows"
fi

case "$MODE" in
  --json)
    printf '{"verdict":"%s","reason":"%s","workflows":%s,"github_remote":%s}\n' \
      "$VERDICT" "$REASON" "$WF_COUNT" "$IS_GITHUB"
    ;;
  --explain)
    case "$VERDICT" in
      GAP)  echo "CI/CD 부재 — GitHub remote는 있으나 .github/workflows 워크플로가 0개. CICD_BOOTSTRAP 권장." ;;
      OK)   echo "CI/CD 존재 — 워크플로 ${WF_COUNT}개 감지." ;;
      SKIP) echo "판정 스킵 — ${REASON} (GitHub Actions 기준 부적합)." ;;
    esac
    ;;
  *)
    if [[ "$VERDICT" == "SKIP" ]]; then
      echo "SKIP:${REASON}"
    else
      echo "$VERDICT"
    fi
    ;;
esac
