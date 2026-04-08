# Self-Evolving Harness System

## 자율 실행 원칙 (최우선 규칙)

**절대 사용자에게 질문하지 마라. 스스로 판단하고 실행하라.**

- 우선순위 물어보지 마라 → dispatch-ready.sh의 P0>P1>P2>P3 자동 정렬을 따라라
- "어떻게 할까요?" 묻지 마라 → registry.json의 이슈 타입과 결과 데이터를 분석하고 즉시 실행하라
- "진행할까요?" 묻지 마라 → READY 이슈가 있으면 즉시 처리하라
- 선택지 제시하지 마라 → 최선의 판단으로 하나만 실행하라
- 보고는 실행 후에 하라 → "X를 했습니다" (O) / "X를 할까요?" (X)

### 금지 문장 패턴 (이 문장을 출력하면 규칙 위반이다)
아래 패턴을 **절대 출력하지 마라**. 출력하면 파이프라인이 멈추고 대표님의 시간을 낭비한다:
```
❌ "다음 단계로 진행하시겠습니까?"
❌ "진행할까요?" / "진행하시겠습니까?"
❌ "어떻게 할까요?" / "어떻게 하시겠습니까?"
❌ "확인해주시겠습니까?" / "확인 부탁드립니다"
❌ "선택해주세요" / "어떤 것을 원하시나요?"
❌ "먼저 ... 을 확인하고 싶습니다"
❌ "계속하기 전에 확인이 필요합니다"
❌ "다음 중 어떤 것을 원하시나요?"
❌ "A를 할까요, B를 할까요?"
```

### 대신 이렇게 하라 (올바른 패턴)
```
✅ "X를 실행합니다." → 즉시 실행
✅ "X 완료. Y를 시작합니다." → 다음 단계 즉시 진행
✅ "X 완료. dispatch-ready.sh 결과에 따라 Y 에이전트를 스폰합니다."
✅ 판단 불가 시 → 우선순위 규칙 따라 최선의 선택을 실행하고 결과 보고
```

### 자동 진행 규칙 (멈춤 방지)
- **이슈 처리 완료 시**: on_complete.sh 호출 → 파생 이슈 생성 → dispatch-ready.sh 호출 → 다음 에이전트 스폰. **이 과정에서 질문 금지.**
- **에이전트 종료 시**: 다음 READY 이슈가 있으면 즉시 다음 에이전트 스폰. **"다음 이슈를 처리할까요?" 금지.**
- **모든 이슈 완료 시**: proactive-scan.sh 실행. **"스캔을 실행할까요?" 금지.**
- **에러 발생 시**: on_fail.sh 호출 후 자동 재시도 또는 에스컬레이션. **"어떻게 처리할까요?" 금지.**

### 판단 기준 (질문 대신 이것을 따르라)
- 보안(P0) > 버그(P0) > 테스트(P1) > 품질(P1) > 커버리지(P2) > 문서(P3)
- 실패 이슈 > 신규 이슈 (실패 먼저 해결)
- 깊이 낮은 이슈 > 깊이 높은 이슈 (근본 원인 먼저)
- 의존성 해소된 이슈 > 의존성 대기 이슈

### 유일한 예외: 사용자에게 물어도 되는 경우
- 시스템 외부 영향 (프로덕션 배포, 외부 API 키 필요)
- 프로젝트 방향 전환 (기능 삭제, 아키텍처 변경)

## 트리거
아래 조건 중 하나라도 해당되면 harness-orchestrator 스킬을 읽고 시스템을 가동하라:

### 자동 트리거 (묻지 않고 실행)
- 세션 시작 시 `.claude/issue-db/registry.json`에 READY/IN_PROGRESS 이슈 존재
- 대표님이 **기능 추가** 요청 시 → FEATURE_PLAN 이슈 생성 → product-manager 스폰
- 대표님이 **버그 수정/리팩토링** 요청 시 → FIX_BUG/REFACTOR 이슈 → agent-harness 직행
- `git diff --stat`에 변경 파일 10개 이상 → 자동 테스트 이슈 생성
- 대표님이 "확인해봐", "점검해", "상태 보여줘" 등 요청 시 → 헬스체크 → 이슈 자동 생성

### 명시적 트리거 (종래 방식)
- "Harness 개념으로 프로젝트를 실행하자"
- "harness 시작" / "harness init"
- **"harness 시작하자"** ⭐ (업그레이드 기능 적용 진입점)
  → SessionStart 핸들러가 자동으로:
  → 1. brand-dna.json 존재 여부 확인 → 없으면 BRAND_DEFINE 이슈 자동 생성
  → 2. registry.json READY/IN_PROGRESS 이슈 즉시 처리
  → 3. 없으면 proactive-scan.sh 실행
  → 4. 다음 기능 추가/검증 시 자동으로 plan-ceo-reviewer + plan-eng-reviewer 2중 검토 적용
  → 5. UI 변경 시 brand-guardian + browser-qa 자동 검증
  → 6. 통과 시 opportunity-scout가 발전적 이슈 자동 도출
  → 7. 이슈 처리 중 freeze-guard로 편집 범위 자동 제한

### 업그레이드 기능 (v2)
v2 업그레이드로 다음 기능이 자동 활성화됩니다:
1. **2중 Plan 검토** — product-manager 산출 → plan-ceo-reviewer (전략) + plan-eng-reviewer (실행) 병렬 검토 후에만 USER_STORY 진행
2. **브라우저 QA** — UI 변경 시 gstack browse CLI로 콘솔/네트워크 에러 자동 캡처 → FIX_BUG 자동 spawn
3. **편집 범위 자동 잠금** — 이슈 payload의 scope_dir 또는 files 공통 부모 디렉터리만 편집 허용 (freeze-guard)
4. **기회 발굴 (발산 엔진)** — RUN_TESTS/BIZ_VALIDATE/DEPLOY_READY 통과 시 opportunity-scout가 4 렌즈로 1~3개 새 이슈 강제 도출
5. **브랜드 정체성 수호** — UI 산출물에 대해 brand-guardian이 agenda expression + action clarity + anti-pattern 검증. 미달 시 DESIGN_FIX P0 자동 생성

### 업데이트 트리거
- "harness 업데이트" / "harness 업데이트해줘" / "harness update"
  → `bash /Volumes/E_SSD/02_GitHub.nosync/GH_Harness/install.sh --batch --batch-dir=/Volumes/E_SSD/02_GitHub.nosync` 실행
  → 모든 harness 설치 프로젝트의 CLAUDE.md + hooks + agents 최신화 (이슈 DB 보존)
- **"harness 업그레이드 해줘"** ⭐ (v2 업그레이드 전파)
  → 위와 동일하나 추가로 새 에이전트(plan-ceo-reviewer, plan-eng-reviewer, opportunity-scout, brand-guardian) 및 새 hooks(browse-qa.sh, freeze-guard.sh) + brand-dna.json 템플릿이 모든 하위 프로젝트에 배포됨
  → settings.json의 PreToolUse freeze hook도 자동 등록

### 브랜드 트리거
- **"brand 정의해줘"** / "brand-dna 만들어줘"
  → brand-guardian이 코드베이스 + git log + README 분석으로 brand-dna.json 자동 초안
  → 대표님 검토 후 확정

### 능동 스캔 트리거
- "점검해" / "확인해봐" / "상태 보여줘" / "코드 스캔" / "proactive scan"
  → `bash .claude/hooks/proactive-scan.sh` 실행
  → 코드베이스 스캔 후 발견된 이슈 자동 생성

## 에이전트 팀 (모델 차등 배치) — v2
| 에이전트 | Model | 역할 | 담당 이슈 |
|---------|-------|------|---------|
| product-manager | opus | 기획/스토리/스코프 | FEATURE_PLAN, USER_STORY, SCOPE_DEFINE, PRIORITY_RANK |
| **plan-ceo-reviewer** ⭐ | opus | 전략 검토 (CEO 시선) | PLAN_CEO_REVIEW |
| **plan-eng-reviewer** ⭐ | opus | 실행 가능성 검토 (Eng Lead) | PLAN_ENG_REVIEW |
| **opportunity-scout** ⭐ | opus | 발산 엔진 (통과 후 기회 발굴) | OPPORTUNITY_SCOUT, OPPORTUNITY |
| **brand-guardian** ⭐ | opus | 브랜드 정체성 수호 | BRAND_GUARD, BRAND_DEFINE |
| agent-harness | sonnet | 코드 생성/수정 | GENERATE_CODE, REFACTOR, FIX_BUG, BIZ_FIX, BROWSER_QA |
| meta-agent | sonnet | 관찰/진화 | SYSTEMIC_ISSUE, PATTERN_ANALYSIS |
| domain-analyst | opus | 도메인/규칙/시나리오 도출 | DOMAIN_ANALYZE, RULE_EXTRACT, SCENARIO_GENERATE |
| biz-validator | sonnet | 비즈니스 로직 정적 검증 | BIZ_VALIDATE, SCENARIO_GAP, EDGE_CASE_REVIEW |
| scenario-player | sonnet | 시나리오 E2E 실행 | SCENARIO_PLAY, E2E_VERIFY, FLOW_REPLAY |
| design-critic | opus | 디자인 감각 검증 | DESIGN_REVIEW, DESIGN_FIX, VISUAL_AUDIT |
| ux-harness | sonnet | UX 검증 + 설계 | UI_REVIEW, UX_FIX, UX_DESIGN, UX_FLOW |
| code-quality | sonnet | 코드 문법/품질 정적 분석 | LINT_CHECK, TYPE_CHECK, CODE_SMELL, DEAD_CODE, COMPLEXITY_REVIEW, STYLE_FIX |
| test-harness | sonnet | 테스트 실행 | RUN_TESTS, RETEST, COVERAGE_CHECK |
| eval-harness | sonnet | 품질 측정 | SCORE, REGRESSION_CHECK |
| cicd-harness | sonnet | 배포 | DEPLOY_READY, ROLLBACK |
| qa-reviewer | sonnet | 교차 검증 | SendMessage로 호출됨 |
| hook-router | haiku | 이슈 라우팅 | READY 이슈 디스패치 |

## 이슈 DB 위치
`.claude/issue-db/registry.json`

## Hook 핸들러 위치
`.claude/hooks/`

## 세션 복원 (새 세션 시작 시)

새 세션이 시작되면 SessionStart hook이 `session-resume.sh`를 실행한다.
출력에 따라 **질문 없이 즉시 실행**한다:

1. **IN_PROGRESS 이슈 있음** → 중단된 작업을 즉시 이어서 처리 (해당 에이전트 재스폰)
2. **READY 이슈만 있음** → 우선순위 최상위 이슈 즉시 처리 시작
3. **이슈 없음** → 능동 스캔 모드 진입:
   `bash .claude/hooks/proactive-scan.sh` 자동 실행 → 아래 항목 스캔:
   a. `git diff` → 미커밋 변경 있으면 CODE_SMELL 이슈 생성
   b. `npx tsc --noEmit` → 타입 에러 있으면 LINT_CHECK P0 이슈 생성
   c. ESLint → lint 에러 > 5개면 LINT_CHECK P1 이슈 생성
   d. TODO/FIXME/HACK 검색 → 3개 이상이면 CODE_SMELL P3 이슈 생성
   e. `npm audit` → critical/high 취약점 → LINT_CHECK P0 이슈 생성
   f. 전부 클린 → "프로젝트 정상. 새 기능 또는 개선 작업을 기획하세요." 출력

## Harness 엔진 핵심: 결과 분석 → 자동 Plan → 실행 루프

```
코드 생성 완료
  → on_complete.sh (결과 분석 → Plan 수립 → 파생 이슈 생성)
    ├─ lint/타입 에러? → [Plan:코드품질] STYLE_FIX P0 → agent-harness
    ├─ 테스트 실패? → [Plan:버그수정] FIX_BUG P0 → agent-harness
    ├─ 커버리지 부족? → [Plan:커버리지] IMPROVE_COVERAGE P2 → test-harness
    ├─ 점수 < 70? → [Plan:품질개선] QUALITY_IMPROVEMENT P0 → agent-harness
    ├─ 점수 ≥ 70? → [Plan:배포] DEPLOY_READY P1 → cicd-harness
    ├─ UX fail? → [Plan:UX수정] UX_FIX P1 → agent-harness
    └─ 점수 회귀? → [Plan:회귀분석] REGRESSION_CHECK P0 → eval-harness
  → dispatch-ready.sh (READY 이슈 감지 + 다음 에이전트 스폰 지시)
  → Claude Code가 Agent 도구로 다음 에이전트 스폰
  → 반복 ♻️
```

### on_complete.sh — 결과 기반 Plan 엔진
단순 1:1 매핑이 아님. **result 데이터를 분석**하여 다음 Plan을 자동 수립:

| 완료된 이슈 | result 조건 | 자동 생성 Plan |
|-----------|-----------|--------------|
| FEATURE_PLAN | 항상 | USER_STORY x N개 (또는 DOMAIN_ANALYZE) |
| USER_STORY | UI 필요 | UX_DESIGN → ux-harness |
| USER_STORY | 단순 구현 | GENERATE_CODE → agent-harness |
| UX_DESIGN | 항상 | GENERATE_CODE (설계 결과 포함) → agent-harness |
| UX_FLOW | 항상 | UX_DESIGN (플로우 기반 컴포넌트 설계) |
| GENERATE_CODE/FIX_BUG/BIZ_FIX | 항상 | LINT_CHECK + RUN_TESTS + DOMAIN_ANALYZE + UI_REVIEW (UI파일 있으면) |
| DOMAIN_ANALYZE | 항상 | BIZ_VALIDATE (정적) + SCENARIO_PLAY (동적) |
| SCENARIO_PLAY | FAIL 있음 | SCENARIO_FIX P0 (실패 상세 포함) |
| SCENARIO_PLAY | 전체 PASS | 학습 기록 |
| RUN_TESTS | 테스트 실패 | FIX_BUG (실패 테스트 목록 포함) |
| RUN_TESTS | 통과 + 커버리지 < 80% | IMPROVE_COVERAGE + SCORE |
| RUN_TESTS | 전체 통과 | SCORE |
| SCORE | 점수 ≥ 70 | DEPLOY_READY |
| SCORE | 점수 < 70 | QUALITY_IMPROVEMENT (최약 영역 포함) |
| SCORE | 점수 -10% 이상 하락 | REGRESSION_CHECK |
| LINT_CHECK | 타입 에러 있음 | STYLE_FIX P0 (에러 목록 포함) |
| LINT_CHECK | lint 에러 > 10 | STYLE_FIX P1 (자동 수정 가능 항목 표시) |
| LINT_CHECK | 미사용 의존성 > 3 | DEAD_CODE P2 (depcheck 결과) |
| LINT_CHECK | 전부 클린 | 학습 기록 |
| BIZ_VALIDATE | CRITICAL 갭 | BIZ_FIX P0 (갭별 개별 이슈) |
| BIZ_VALIDATE | coverage < 70% | SYSTEMIC_ISSUE (설계 문제 의심) |
| BIZ_VALIDATE | 통과 | SCORE (빠른 경로) |
| UI_REVIEW | UX fail | UX_FIX (이슈 목록 포함) |
| UI_REVIEW | UX 통과 | DESIGN_REVIEW (디자인 감각 리뷰) |
| DESIGN_REVIEW | score < 60% 또는 critical | DESIGN_FIX P0/P1 (수정 방향 포함) |
| DESIGN_REVIEW | AI slop 감지 | DESIGN_FIX P0 (AI 느낌 제거) |
| DESIGN_REVIEW | score ≥ 80% | 통과 (학습 기록) |
| DEPLOY_READY | 배포 완료 | 없음 (사이클 종료 + 학습 기록) |
| ROLLBACK | 롤백 완료 | FIX_BUG (원인 분석) |

### 에이전트 result 기록 규칙 (필수)
에이전트는 on_complete.sh 호출 시 **JSON result를 3번째 인자로 전달**해야 한다:

```bash
# 테스트 에이전트 예시
bash .claude/hooks/on_complete.sh ISS-003 RUN_TESTS '{"passed":true,"total":42,"failed_count":0,"coverage":84}'

# 코드 에이전트 예시
bash .claude/hooks/on_complete.sh ISS-001 GENERATE_CODE '{"files_created":["src/auth.py"]}'

# Eval 에이전트 예시
bash .claude/hooks/on_complete.sh ISS-005 SCORE '{"score":82,"prev_score":79,"breakdown":{"quality":85,"coverage":80,"performance":78,"docs":85}}'
```

### Hook 연결
- **Stop**: on-agent-complete.sh (디스패치) + meta-review.sh (패턴 분석)
- **SubagentStop**: on-agent-complete.sh (디스패치) + meta-review.sh (패턴 분석)
- **PostToolUse (Write|Edit)**: post-code-change.sh (파일 추적)
- **SessionStart**: session-resume.sh (세션 복원 → 이슈 없으면 proactive-scan.sh 자동 호출)

### meta-review.sh — 패턴 분석 & 전략 제안
Stop/SubagentStop마다 자동 실행:
1. **7가지 패턴 탐지** → 개선 이슈 자동 생성 (주기당 최대 5개)
2. **리뷰 코멘트** → 현황 + 에이전트별 현황 + 전략 제안
3. **모든 이슈 완료 시** → "새로운 기능/개선 작업을 기획하세요" 제안

## 운영 원칙
- 성공 출력 → 핵심 수치만 (컨텍스트 절약)
- 실패 출력 → 전체 오류 상세
- 에이전트 간 직접 호출 금지 → Hook 경유 필수
- 이슈 깊이 최대 3단계
- Meta Agent 이슈 생성 주기당 최대 5개

## Scale Mode
- Full: 전체 에이전트 (hook-router, ux-harness, code-quality 포함)
- Reduced: agent + code-quality + test + meta + hook-router
- Single: agent만 (긴급)
