# Dynamic Workflows 사용 정책 (Opus 4.8)

> 결정: 2026-05-30 대표님 승인 — **대형 작업 한정**. ISS-340.
> 근거 기능: Opus 4.8 Dynamic Workflows (Claude Code `Workflow` 네이티브 도구, 한 세션 내 수백 서브에이전트 병렬 오케스트레이션).

## 1. 원칙

Harness의 일상 이슈 처리는 **기존 `Agent` 스폰 방식을 유지**한다.
`Workflow` 도구는 **명시적 대형 작업에서만** 사용한다. 무분별한 수백 서브에이전트 발사는 금지.

## 2. Workflow 허용 조건 (모두 충족)

1. **작업 성격이 대형**일 것 — 아래 중 하나:
   - 코드베이스 전체 마이그레이션 (수십~수백 파일)
   - 전체 감사 (보안/품질/디자인 코드베이스 스윕)
   - 대량 리팩토링 (패턴 일괄 변경)
   - 광범위 리서치 (멀티소스 fan-out + 교차검증)
2. **사전 토큰 규모 보고** — 실행 전 예상 서브에이전트 수 + 토큰 규모를 대표님께 1줄 보고.
3. **T2 BUDGET 게이트 통과** — 일일 Opus Hard Cap($20) 정책 유지. 근접/초과 시 `request-user-confirm.sh BUDGET` 발동.

## 3. Workflow 금지 영역

- 단일 이슈 처리 (FIX_BUG, STYLE_FIX 등) → 기존 Agent 스폰
- 일상 PDCA 사이클 (GENERATE_CODE → LINT → TEST → SCORE)
- 예산 Hard Cap 근접 상태

## 4. race-mode 와의 관계

기존 `race-dispatch.sh`(provider 경쟁, git worktree 격리)와 `Workflow`(단일 provider 병렬 fan-out)는 **목적이 다르다**:
- **race-mode** — 같은 작업을 여러 LLM(claude/codex/gemini)이 경쟁 → 승자 선정
- **Workflow** — 한 LLM이 작업을 분해해 병렬 서브에이전트로 동시 처리 → 종합

→ 둘은 대체 관계가 아니다. race-mode를 Workflow로 흡수하지 않는다.
→ 향후 PoC: 대형 마이그레이션 1건을 Workflow로 시범 실행해 토큰/완성도 측정 (대표님 대형작업 지시 시점에 한해).

## 5. 실행 시 보고 템플릿

```
[Workflow 사용 사전 보고]
- 작업: <대형 작업 설명>
- 예상 서브에이전트: ~N개
- 예상 토큰 규모: ~Xk output
- 현재 일일 Opus 비용: $Y / Hard Cap $20
→ GO/STOP 판단 요청
```

## 6. PoC 실측 — 비즈니스 로직 점검 재구현 (2026-06-29, 대표님 승인 PoC)

5절의 "향후 PoC"를 실행했다. 대형 마이그레이션 대신, 이미 *병렬 fan-out 성격*인 **비즈니스 로직 점검**(domain → biz/journey/view)을 Workflow 스크립트로 재구현해 1회 실측했다.

### 구현
- 스크립트: `.claude/workflows/biz-check.js` (~110줄, 흩어진 오케스트레이션 로직 응축)
- 흐름: `phase('Domain')` → domain-analyst 1개 → `parallel()`로 biz/journey/view 3축 동시
- 모든 축 `agentType: 'check-harness'` 재사용(기존 22개 에이전트 자산 보존), schema로 StructuredOutput 강제

### 실측 결과 (1회)
| 항목 | 값 |
|---|---|
| 에이전트 | 4개 (domain 1 → 3축 병렬) |
| 소요 | ~10.5분 (628s), 3축 진짜 동시 실행 |
| 토큰 | subagent 합계 346k, tool_use 125회 |
| 산출 | domain 규칙 17·시나리오 15(admin4/user10/guest3), biz C3, journey 26/40·C1, view C2 |

### 검출한 실전 결함 (PoC가 진짜 가치를 증명한 부분)
정적 점검이 다음 **운영 결함 8건**을 잡아냈다 — 단순 데모가 아니라 실사용 가치 입증:
1. `VIEW_AUDIT`가 `axis-router.sh`에 미매핑 → "비즈 점검" 트리거가 만든 VIEW_AUDIT 이슈가 Hermes로 소실
2. `on_complete.sh`에 VIEW_AUDIT 완료 핸들러 + rubric_fail 처리 누락 → CRITICAL 갭이 STYLE_FIX로 안 이어짐
3. `on_complete.sh`에 DAILY_ISSUE_CAP(30) 미적용 → 파생 이슈 무제한 생성 가능
4. `session-resume.sh`가 brand uninitialized 시 BRAND_DEFINE 이슈를 실제 생성 안 함(텍스트 경고만)
5. `dispatch-ready.sh` 우선순위에 '실패 이슈 > 신규 이슈' 차원 없음 → BR-014 미집행
6. `session-resume.sh` MODEL_MAP에 v3+ 에이전트(advisor/plan-ceo-reviewer 등) 누락 → sonnet 강제 강등
7. 신규 훅 12개 git 미추적 → install.sh --batch 배포 시 누락
8. `daily-dream.sh`가 meta-agent.md엔 있으나 settings.json 미등록 → 작동 안 함

### 결론 — 조건부 도입
- **YES (래퍼 한정)**: 이미 병렬 fan-out인 3개만 Workflow로 래핑 — ① 비즈니스 로직 점검(본 PoC, 확정), ② 화면 갭 스캔, ③ RACE_MODE. 흐름 응축·재현성·자동 병렬이 실증됨.
- **NO (대체 금지)**: registry.json·이슈 DB·세션 복원 = 하네스 영속성 레이어. Workflow엔 영속성 없음 → 보완이지 대체 아님.
- **NO (자동 트리거 금지)**: Workflow는 명시 옵트인 전용. 무인 체인에 끼우면 비용 폭주(Hard Cap $20 충돌).
- 단일 이슈 PDCA 파이프라인은 현행 유지(Karpathy #2 단순함·#3 외과적 변경).

### 확정본 수정 사항 (PoC → biz-check.js)
- 종료 규율 추가: "탐색 최대 8회, 반드시 StructuredOutput으로 종료" (PoC transcript 파싱 시 view 축 미도달로 오인 → 규율 명문화)
- view 축 `effort: 'high'`(탐색량 과다 대응)
- null 축 silent drop 금지 → `missing_axes`로 명시 보고(CLAUDE.md "no silent caps")

### 확정본 검증 실측 (2회차, w1n4hlq10)
종료 규율이 토큰/시간/도구호출을 절반으로 줄이면서 품질은 유지됨:

| 지표 | 1회 PoC | 확정본 2회 | 변화 |
|---|---|---|---|
| `missing_axes` | (파싱 오인) | `[]` (3축 전부 종료) | ✅ |
| subagent 토큰 | 346k | 222k | −36% |
| tool_use | 125회 | 61회 | −51% |
| 소요 | 628s | 334s | −47% |

→ 확정본도 동일 결함(VIEW_AUDIT 3중 단절: axis-router 미등록 + check-harness.md 모드 테이블 누락 + on_complete 핸들러 부재)을 더 정밀하게 검출. **biz-check.js 운영 투입 가능 상태 확정.**

> 후속: 검출된 결함 8건은 본 정책과 별개로 FIX_BUG/SYSTEMIC_ISSUE 이슈로 분리 처리(Surgical — 이번 PoC diff엔 미포함).
