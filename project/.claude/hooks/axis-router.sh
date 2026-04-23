#!/bin/bash
# axis-router.sh — 이슈 타입 → 2축 에이전트(plan-harness|check-harness) + mode 결정
#
# 사용법:
#   source axis-router.sh
#   route_axis "FEATURE_PLAN" → "plan-harness:product"
#   route_axis "BIZ_VALIDATE" → "check-harness:biz"
#
# 환경변수 HARNESS_AXIS_MODE로 제어:
#   - "2axis" (기본) : 2축 라우팅 사용
#   - "legacy"       : 기존 22개 에이전트 직접 호출 (호환 모드)

route_axis() {
  local issue_type="$1"
  local mode_override="${2:-}"
  local axis_mode="${HARNESS_AXIS_MODE:-2axis}"

  if [ "$axis_mode" = "legacy" ]; then
    echo "legacy:${issue_type}"
    return
  fi

  case "$issue_type" in
    # ──────── PLAN 축 ────────
    FEATURE_PLAN|USER_STORY|SCOPE_DEFINE|PRIORITY_RANK)
      echo "plan-harness:product" ;;
    PLAN_CEO_REVIEW)
      echo "plan-harness:ceo-review" ;;
    PLAN_ENG_REVIEW)
      echo "plan-harness:eng-review" ;;
    OPPORTUNITY_SCOUT|OPPORTUNITY)
      echo "plan-harness:opportunity" ;;
    DOMAIN_ANALYZE|RULE_EXTRACT|SCENARIO_GENERATE)
      echo "plan-harness:domain" ;;
    AUDIENCE_RESEARCH|AUDIENCE_REFRESH)
      echo "plan-harness:audience" ;;
    UX_DESIGN|UX_FLOW|UX_FIX)
      echo "plan-harness:ux-design" ;;
    GENERATE_CODE|REFACTOR|FIX_BUG|BIZ_FIX|STYLE_FIX|QUALITY_IMPROVEMENT|BROWSER_QA)
      echo "plan-harness:code" ;;
    DEPLOY_READY|ROLLBACK)
      echo "plan-harness:deploy" ;;
    SCREEN_GAP)
      echo "plan-harness:product" ;;

    # ──────── CHECK 축 ────────
    LINT_CHECK|TYPE_CHECK|CODE_SMELL|DEAD_CODE|COMPLEXITY_REVIEW)
      echo "check-harness:code" ;;
    RUN_TESTS|RETEST|COVERAGE_CHECK|IMPROVE_COVERAGE)
      echo "check-harness:test" ;;
    SCORE|REGRESSION_CHECK)
      echo "check-harness:eval" ;;
    BIZ_VALIDATE|SCENARIO_GAP|EDGE_CASE_REVIEW)
      echo "check-harness:biz" ;;
    JOURNEY_VALIDATE|ROLE_AUDIT|ONBOARDING_CHECK|IMPACT_REVIEW)
      echo "check-harness:journey" ;;
    SCENARIO_PLAY|E2E_VERIFY|FLOW_REPLAY)
      echo "check-harness:scenario" ;;
    DESIGN_REVIEW|DESIGN_FIX|VISUAL_AUDIT)
      echo "check-harness:design" ;;
    BRAND_GUARD|BRAND_DEFINE)
      echo "check-harness:brand" ;;
    UI_REVIEW)
      echo "check-harness:ux-review" ;;
    SYSTEMIC_ISSUE|PATTERN_ANALYSIS)
      echo "check-harness:meta" ;;

    # ──────── 메타 (축 외부) ────────
    HERMES_CONSULT)
      echo "hermes:-" ;;
    ADVISOR_CONSULT)
      echo "advisor:-" ;;
    RACE_MODE)
      # 다중 provider 병렬 구현 경쟁 — race-dispatch.sh가 직접 처리
      echo "race:dispatch" ;;

    *)
      # 미매핑 이슈 → hermes로 에스컬레이션
      echo "hermes:unknown-type" ;;
  esac
}

# CLI로도 호출 가능
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  route_axis "$@"
fi
