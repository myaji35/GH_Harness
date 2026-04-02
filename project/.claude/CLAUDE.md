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

## 자동 반복 실행 루프 (핵심)

```
이슈 처리 완료
  → on_complete.sh (파생 이슈 생성 + registry.json 업데이트)
  → dispatch-ready.sh (READY 이슈 감지 + 다음 에이전트 스폰 지시)
  → Claude Code가 지시를 읽고 Agent 도구로 다음 에이전트 스폰
  → 반복
```

### 자동 실행 Hook 연결
- **SubagentStop**: 서브에이전트 완료 → on-agent-complete.sh → dispatch-ready.sh (asyncRewake)
- **Stop**: 메인 에이전트 완료 → on-agent-complete.sh → dispatch-ready.sh (asyncRewake)
- **PostToolUse (Write|Edit)**: 코드 변경 → post-code-change.sh (파일 추적)

### dispatch-ready.sh 동작
1. registry.json에서 READY 이슈 탐색
2. 우선순위 정렬 (P0 > P1 > P2 > P3)
3. 다음 에이전트 스폰 지시 출력
4. exit 2 (asyncRewake) → Claude Code 자동 깨어남

### 실행 규칙
- dispatch-ready.sh 출력에 "자동 실행 지시"가 포함되면 **즉시 실행**
- registry.json에서 이슈 status를 IN_PROGRESS로 변경 후 에이전트 스폰
- 에이전트 스폰 시 model 파라미터 필수 지정
- 처리 완료 후 반드시 on_complete.sh 또는 on_fail.sh 호출

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
