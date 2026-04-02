# Issue Registry

## 역할
모든 이슈(태스크)의 생성/처리/완료/파생을 관리하는 중앙 두뇌.
`.claude/issue-db/registry.json`이 실제 저장소.

## Trigger
- 이슈 생성/조회/업데이트 시
- 에이전트가 다음 이슈를 찾을 때

---

## 이슈 구조

```json
{
  "id": "ISS-001",
  "title": "auth.py 유닛 테스트 작성",
  "type": "RUN_TESTS",
  "status": "READY",
  "priority": "P1",
  "assign_to": "test-harness",
  "depth": 1,
  "retry_count": 0,
  "parent_id": "ISS-000",
  "depends_on": [],
  "created_at": "2026-01-01T00:00:00Z",
  "started_at": null,
  "completed_at": null,
  "payload": {
    "files": ["src/auth.py"],
    "scope": "unit"
  },
  "result": null,
  "spawn_rules": [
    {
      "condition": "coverage < 80",
      "new_issue": {
        "title": "커버리지 80% 달성",
        "type": "IMPROVE_COVERAGE",
        "priority": "P1"
      }
    }
  ]
}
```

---

## 이슈 상태 흐름

```
CREATED → READY → IN_PROGRESS → DONE → LEARNED
                       ↓
                     FAILED → (retry) → IN_PROGRESS
                                      → ESCALATED
```

---

## 이슈 타입 목록

| 타입 | 담당 하네스 | 설명 |
|------|------------|------|
| GENERATE_CODE | agent-harness | 코드 생성 |
| REFACTOR | agent-harness | 리팩토링 |
| FIX_BUG | agent-harness | 버그 수정 |
| RUN_TESTS | test-harness | 테스트 실행 |
| RETEST | test-harness | 재테스트 |
| COVERAGE_CHECK | test-harness | 커버리지 확인 |
| SCORE | eval-harness | 품질 점수화 |
| REGRESSION_CHECK | eval-harness | 회귀 분석 |
| DEPLOY_READY | cicd-harness | 배포 |
| ROLLBACK | cicd-harness | 롤백 |
| BIZ_VALIDATE | biz-validator | 비즈니스 로직 검증 |
| DESIGN_REVIEW | design-critic | 디자인 감각 리뷰 |
| DESIGN_FIX | agent-harness | 디자인 수정 |
| VISUAL_AUDIT | design-critic | 시각적 일관성 감사 |
| SCENARIO_GAP | biz-validator | 시나리오 갭 재검증 |
| EDGE_CASE_REVIEW | biz-validator | 엣지 케이스 검증 |
| BIZ_FIX | agent-harness | 비즈니스 로직 수정 |
| SYSTEMIC_ISSUE | meta-agent | 반복 문제 근본 분석 |
| PATTERN_ANALYSIS | meta-agent | 패턴 분석 |

---

## 파생 이슈 방지 규칙 (이슈 폭발 방지)

```
1. 유사 이슈 중복 체크 → 이미 존재하면 생성 안 함
2. 깊이 제한: depth >= 3 → BACKLOG_SUGGESTION으로 강등
3. 백로그 > 50개: 낮은 우선순위 이슈 생성 안 함
4. 같은 제목 3회 이상 → SYSTEMIC_ISSUE로 에스컬레이션
```

---

## 에이전트가 이슈 가져오는 방법

```
1. registry.json에서 status=="READY" && assign_to=="[내 이름]" 조회
2. 가장 오래된 이슈부터 처리 (FIFO)
3. status를 "IN_PROGRESS"로 변경
4. 처리 완료 후 result 기록 + spawn_rules 평가
5. on_complete Hook 발화
```
