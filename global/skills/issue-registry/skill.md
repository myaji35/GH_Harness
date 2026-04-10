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
| DOMAIN_ANALYZE | domain-analyst | 도메인 분석/규칙 도출 |
| RULE_EXTRACT | domain-analyst | 비즈니스 규칙 추출 |
| SCENARIO_GENERATE | domain-analyst | 시나리오 자동 생성 |
| BIZ_VALIDATE | biz-validator | 비즈니스 로직 정적 검증 |
| SCENARIO_PLAY | scenario-player | 시나리오 E2E 실행 |
| E2E_VERIFY | scenario-player | E2E 흐름 검증 |
| SCENARIO_FIX | agent-harness | 시나리오 실패 수정 |
| DESIGN_REVIEW | design-critic | 디자인 감각 리뷰 |
| DESIGN_FIX | agent-harness | 디자인 수정 |
| VISUAL_AUDIT | design-critic | 시각적 일관성 감사 |
| SCENARIO_GAP | biz-validator | 시나리오 갭 재검증 |
| EDGE_CASE_REVIEW | biz-validator | 엣지 케이스 검증 |
| BIZ_FIX | agent-harness | 비즈니스 로직 수정 |
| SYSTEMIC_ISSUE | meta-agent | 반복 문제 근본 분석 |
| PATTERN_ANALYSIS | meta-agent | 패턴 분석 |
| HERMES_CONSULT | hermes | executor 막힘 실시간 중재 자문 |
| ADVISOR_CONSULT | advisor | Opus 수준 심층 자문 (Hermes 경유 전용) |
| AUDIENCE_RESEARCH | audience-researcher | 타겟 오디언스 언어/페인/드림아웃컴 조사 |
| AUDIENCE_REFRESH | audience-researcher | 오디언스 리서치 주기 재조사 |
| BRAND_SCRAPE | brand-guardian | Firecrawl 등으로 브랜드 자산 자동 스크레이핑 |
| UI_LEVEL_UPGRADE | ux-harness | UI 품질 레벨 1→5 단계적 승급 |
| JOURNEY_VALIDATE | journey-validator | 사용자 여정 전체 검증 (역할별/인팩트/온보딩) |
| ROLE_AUDIT | journey-validator | Admin/User/Guest 역할별 화면 접근 감사 |
| ONBOARDING_CHECK | journey-validator | 첫 사용 경험 5단계 검증 |
| IMPACT_REVIEW | journey-validator | 화면별 행동 유도력 검증 |

---

## Hermes 상태 구조 (v2+)

registry.json 루트에 `hermes_state` 필드가 자동 생성됨:

```json
{
  "hermes_state": {
    "invocations_by_issue": { "ISS-042": 2 },
    "daily_log": [
      { "date": "2026-04-10", "count": 7, "cost_usd": 0.35 }
    ],
    "total_invocations": 14
  }
}
```

이슈 객체에는 선택적으로 다음 필드 추가됨:
- `hermes_invocations`: 이 이슈에 대한 Hermes 호출 횟수
- `hermes_consults`: 생성된 HERMES_CONSULT 이슈 ID 목록
- `payload.hermes_plan`: Hermes/Advisor가 주입한 실행 plan

## Circuit Breaker 임계치 (`hermes-escalate.sh` 내장)
- 이슈당 최대 3회
- 일일 전체 최대 20회
- 일일 비용 최대 $5

초과 시 → meta-agent에 `SYSTEMIC_ISSUE P0` 자동 생성 (origin: "hermes_circuit_breaker")

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
