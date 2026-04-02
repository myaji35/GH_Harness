# Self-Evolving Harness System

## 트리거
아래 문장을 받으면 즉시 `harness-orchestrator` 스킬을 읽고 시스템을 초기화하라:
- "Harness 개념으로 프로젝트를 실행하자"
- "harness 시작"
- "harness init"

## 에이전트 팀 (모델 차등 배치)
| 에이전트 | Model | 역할 | 담당 이슈 |
|---------|-------|------|---------|
| agent-harness | opus | 코드 생성/수정 | GENERATE_CODE, REFACTOR, FIX_BUG |
| meta-agent | opus | 관찰/진화 | SYSTEMIC_ISSUE, PATTERN_ANALYSIS |
| ux-harness | sonnet | UX 검증 | UI_REVIEW, UX_FIX |
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
출력에 따라 아래 규칙을 따른다:

1. **IN_PROGRESS 이슈 있음** → 중단된 작업. 사용자에게 재개/실패/완료 선택지 제시
2. **READY 이슈만 있음** → "자동 실행 지시"에 따라 즉시 다음 에이전트 스폰
3. **이슈 없음** → `harness 시작`으로 초기화 안내

## Harness 엔진 핵심: 결과 분석 → 자동 Plan → 실행 루프

```
코드 생성 완료
  → on_complete.sh (결과 분석 → Plan 수립 → 파생 이슈 생성)
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
| GENERATE_CODE/FIX_BUG | 항상 | RUN_TESTS + UI_REVIEW (UI파일 있으면) |
| RUN_TESTS | 테스트 실패 | FIX_BUG (실패 테스트 목록 포함) |
| RUN_TESTS | 통과 + 커버리지 < 80% | IMPROVE_COVERAGE + SCORE |
| RUN_TESTS | 전체 통과 | SCORE |
| SCORE | 점수 ≥ 70 | DEPLOY_READY |
| SCORE | 점수 < 70 | QUALITY_IMPROVEMENT (최약 영역 포함) |
| SCORE | 점수 -10% 이상 하락 | REGRESSION_CHECK |
| UI_REVIEW | UX fail | UX_FIX (이슈 목록 포함) |
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
- Full: 8 에이전트 전체 (hook-router, ux-harness 포함)
- Reduced: agent + test + meta + hook-router
- Single: agent만 (긴급)
