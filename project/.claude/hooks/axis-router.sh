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
    GENERATE_CODE|REFACTOR|FIX_BUG|BIZ_FIX|STYLE_FIX|QUALITY_IMPROVEMENT|BROWSER_QA|SCENARIO_FIX)
      echo "plan-harness:code" ;;
    DEPLOY_READY|ROLLBACK|CICD_BOOTSTRAP|PIPELINE_CHECK|PIPELINE_OPTIMIZE)
      echo "plan-harness:deploy" ;;
    SCREEN_GAP)
      echo "plan-harness:product" ;;

    # ──────── CHECK 축 ────────
    LINT_CHECK|TYPE_CHECK|CODE_SMELL|DEAD_CODE|COMPLEXITY_REVIEW|VIEW_AUDIT)
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

# ── Opus 4.8 agentic 힌트 (v5) ───────────────────────────────
# route_axis_hints "<ISSUE_TYPE>" → "effort=<v> background=<0|1> isolation=<0|1>"
# 능동 작동하되 오버 방지: background/isolation은 기본 0, 발동 조건 만족 시에만 1 권고.
# 실제 스폰 측(Claude Code)이 이 힌트 + CLAUDE.md 가드레일을 종합해 최종 판단.
route_axis_hints() {
  local issue_type="$1"
  local effort="medium" bg=0 iso=0

  case "$issue_type" in
    # high effort — 기획/설계/코드생성/도메인/브랜드/비즈로직/메타
    FEATURE_PLAN|USER_STORY|SCOPE_DEFINE|PRIORITY_RANK|SCREEN_GAP|\
    PLAN_CEO_REVIEW|PLAN_ENG_REVIEW|OPPORTUNITY_SCOUT|OPPORTUNITY|\
    DOMAIN_ANALYZE|RULE_EXTRACT|SCENARIO_GENERATE|\
    GENERATE_CODE|REFACTOR|FIX_BUG|BIZ_FIX|STYLE_FIX|QUALITY_IMPROVEMENT|SCENARIO_FIX|\
    BIZ_VALIDATE|SCENARIO_GAP|EDGE_CASE_REVIEW|VIEW_AUDIT|\
    BRAND_GUARD|BRAND_DEFINE|SYSTEMIC_ISSUE|PATTERN_ANALYSIS)
      effort="high" ;;
    # low effort — 절차적/기계적
    DEPLOY_READY|ROLLBACK|RUN_TESTS|RETEST|COVERAGE_CHECK|IMPROVE_COVERAGE|\
    SCENARIO_PLAY|E2E_VERIFY|FLOW_REPLAY)
      effort="low" ;;
    # 그 외 medium (정적 검증/리뷰/조사/UX)
  esac

  # background 권고: 장시간 추정 작업만 (조건 ②③은 스폰 측이 최종 판단)
  case "$issue_type" in
    RUN_TESTS|RETEST|COVERAGE_CHECK|IMPROVE_COVERAGE|\
    SCENARIO_PLAY|E2E_VERIFY|FLOW_REPLAY|BROWSER_QA)
      bg=1 ;;
  esac

  # isolation 권고: 병렬 파일수정 충돌 가능 작업만
  case "$issue_type" in
    RACE_MODE) iso=1 ;;
  esac

  # 헤드리스 도구잠금(ISS-350): CHECK 축(검증/읽기)만 화이트리스트.
  # 빈 문자열 = 잠금 미적용(기본). dispatch가 HARNESS_HEADLESS=1일 때만 사용.
  local allow=""
  case "$issue_type" in
    # 테스트/시나리오/eval/코드품질 — Bash 필요(테스트·린트 실행)
    RUN_TESTS|RETEST|COVERAGE_CHECK|IMPROVE_COVERAGE|\
    SCENARIO_PLAY|E2E_VERIFY|FLOW_REPLAY|\
    LINT_CHECK|TYPE_CHECK|CODE_SMELL|DEAD_CODE|COMPLEXITY_REVIEW|VIEW_AUDIT|\
    SCORE|REGRESSION_CHECK)
      allow="Read,Grep,Glob,Bash" ;;
    # 비즈/저니/디자인/UX/메타 — 읽기 전용(Bash 불필요)
    BIZ_VALIDATE|SCENARIO_GAP|EDGE_CASE_REVIEW|\
    JOURNEY_VALIDATE|ROLE_AUDIT|ONBOARDING_CHECK|IMPACT_REVIEW|\
    DESIGN_REVIEW|VISUAL_AUDIT|UI_REVIEW|\
    SYSTEMIC_ISSUE|PATTERN_ANALYSIS)
      allow="Read,Grep,Glob" ;;
    # brand(외부 스크레이핑 T2) + PLAN 축(쓰기 필요) = 잠금 없음
  esac

  echo "effort=${effort} background=${bg} isolation=${iso} allowed_tools=${allow}"
}

# CLI로도 호출 가능
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  if [ "$1" = "--hints" ]; then
    shift; route_axis_hints "$@"
  else
    route_axis "$@"
  fi
fi
