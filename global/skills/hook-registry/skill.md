# Hook Registry

## 역할
에이전트들이 서로를 직접 호출하지 않고 이벤트로 협력하게 하는 브로커.
"일 해라"가 아니라 "이런 일이 생겼어"를 알린다.

## Trigger
- harness-orchestrator가 Phase 4에서 호출
- 각 에이전트가 시작 시 구독 등록

## NOT Trigger
- 직접 에이전트 호출 시 (이건 Hook을 써야 함)

---

## 이벤트 목록

| 이벤트 | 발화 주체 | 구독 에이전트 | 설명 |
|--------|----------|-------------|------|
| on_create | Issue Registry | 모든 에이전트 | 새 이슈 생성됨 |
| on_start | 각 Harness | meta-agent | 처리 시작 |
| on_progress | 각 Harness | meta-agent | 중간 진행 상황 |
| on_complete | 각 Harness | 모든 에이전트 | 처리 완료 |
| on_fail | 각 Harness | agent-harness, meta-agent | 실패 발생 |
| on_learn | eval-harness | meta-agent | 학습 데이터 생성 |

---

## on_complete 처리 규칙 (가장 중요)

```
GENERATE_CODE 완료 → on_complete 발화
  ├─ test-harness 구독: RUN_TESTS 이슈 자동 생성
  ├─ meta-agent 구독: 패턴 관찰 데이터 저장
  └─ qa-reviewer 구독: 교차 검증 요청 (Producer-Reviewer 패턴 시)

RUN_TESTS 완료 → on_complete 발화
  ├─ eval-harness 구독: SCORE 이슈 자동 생성
  └─ meta-agent 구독: 테스트 결과 관찰

SCORE 완료 → on_complete 발화
  ├─ 점수 ≥ 70: cicd-harness 구독 → DEPLOY_READY 이슈 생성
  ├─ 점수 < 70: agent-harness 구독 → QUALITY_IMPROVEMENT 이슈 생성
  └─ meta-agent 구독: 품질 트렌드 관찰
```

---

## on_fail 처리 규칙

```
실패 발생 → on_fail 발화
  ├─ retry_count < 3: 동일 이슈 재시도
  ├─ retry_count == 3: 에스컬레이션 이슈 생성 (meta-agent)
  └─ 스냅샷 복구: 실패 전 상태로 롤백
```

---

## 구독 등록 방법
각 에이전트 시작 시 아래 형식으로 선언:
```json
{
  "agent": "test-harness",
  "subscribes": [
    { "event": "on_complete", "filter": "GENERATE_CODE" },
    { "event": "on_create",   "filter": "RUN_TESTS" }
  ]
}
```

---

## 발화 원칙
- 비동기 처리 (발화 후 대기 없이 다음 진행)
- 구독자 없어도 이벤트는 registry.json에 기록
- 실패한 Hook → 3회 재시도 후 포기
- 모든 발화 이력 → `.claude/issue-db/registry.json`의 hooks 섹션에 기록
