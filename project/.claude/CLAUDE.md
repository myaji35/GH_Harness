# Self-Evolving Harness System

## 트리거
아래 문장을 받으면 즉시 `harness-orchestrator` 스킬을 읽고 시스템을 초기화하라:
- "Harness 개념으로 프로젝트를 실행하자"
- "harness 시작"
- "harness init"

## 에이전트 팀
| 에이전트 | 역할 | 담당 이슈 |
|---------|------|---------|
| agent-harness | 코드 생성/수정 | GENERATE_CODE, REFACTOR, FIX_BUG |
| test-harness | 테스트 실행 | RUN_TESTS, RETEST, COVERAGE_CHECK |
| eval-harness | 품질 측정 | SCORE, REGRESSION_CHECK |
| cicd-harness | 배포 | DEPLOY_READY, ROLLBACK |
| meta-agent | 관찰/진화 | 모든 이벤트 구독 |
| qa-reviewer | 교차 검증 | SendMessage로 호출됨 |

## 이슈 DB 위치
`.claude/issue-db/registry.json`

## Hook 핸들러 위치
`.claude/hooks/`

## 운영 원칙
- 성공 출력 → 핵심 수치만 (컨텍스트 절약)
- 실패 출력 → 전체 오류 상세
- 에이전트 간 직접 호출 금지 → Hook 경유 필수
- 이슈 깊이 최대 3단계
- Meta Agent 이슈 생성 주기당 최대 5개

## Scale Mode
- Full: 6 에이전트 전체
- Reduced: agent + test + meta
- Single: agent만 (긴급)
