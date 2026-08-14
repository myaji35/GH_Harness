# GH_Harness v5 고도화 기획안

**작성일**: 2026-05-15
**작성자**: Claude Opus 4.7 (Phoenix 프로젝트 세션 中)
**상태**: 대표님 검토 대기

---

## 0. TL;DR

- **왜 v5인가**: v4 기획안(2026-04-22)이 Phase 4.1 4개 산출물(Dashboard / Computational Gate / Sandbox / Decision Trace) 모두 *미완* 상태로 8개월째 표류 중. **계획만 있고 실행은 없는 harness drift** 자체가 우리가 잡으려던 가장 큰 안티패턴이었음. v5는 v4를 폐기하는 것이 아니라 **"Phoenix 실전 운영에서 검출된 10개 갭"**으로 v4의 P0 항목을 재정렬하고, **2주 단위 매주 1개 산출물**로 잘게 쪼개 실제 출시까지 끌고 간다.

- **무엇이 달라지는가**: ① 프로젝트 타입(code/doc/hybrid) 인식 → 트리거 차등. ② PARKED 이슈 좀비화 방지. ③ artifacts 레지스트리(PDF/HTML 등 결과물 자산화). ④ 사용자 메시지 우선 게이트(harness 큐가 사용자 즉답을 가리지 못함). ⑤ T2 자동 감지(PreToolUse 정규식).

- **언제**: Track A(즉시 가치, 1주 내) 3개, Track B(2~4주) 4개, Track C(v4 잔여) 4개. 총 11개 산출물 / 7주.

- **승인 후 첫 액션**: 이 문서를 Phoenix 폴더의 ISS-NEW로 등록 → product-manager 분해 → 매주 1개 출시.

---

## 1. v4 기획안 회고 (8개월의 교훈)

| 항목 | v4 계획 (2026-04-22) | 실제 상태 (2026-05-15) | 교훈 |
|---|---|---|---|
| Phase 4.1 (2주) | Dashboard + 강제 게이트 + Sandbox-lite + Decision Trace | dashboard.sh / sandbox-enforce.sh / decision-trace.sh 파일은 생겼지만 **실 트리거 0회** | 산출물 = 파일 생성 아닌 *작동 검증*. 검증 게이트가 빠지면 drift |
| Phase 4.2 (3주) | Plan-File + Compaction + Offloading + Ralph Loop + Whitelist | **미착수** | 9주 큰 덩어리 — 매주 산출물 1개로 쪼개야 함 |
| Phase 4.3 (4주) | Fitness + Auto-Rollback + Drift Detection + Benchmark | **미착수** | "다음 Phase 검토" 게이트가 자기참조 — 외부 데드라인 필요 |
| KPI 측정 | decision-trace로 5개 지표 | **단 한 번도 측정 안 됨** | 측정 도구가 만들어도 *측정 트리거*가 없으면 의미 없음 |

**구조적 원인**:
1. **자기참조 데드라인** — "Phase 4.1 완료 시 4.2 착수 결정"이라는 게이트 자체가 사용자 결정에 의존. 외부 트리거 없음.
2. **검증 부재** — 산출물이 "작동했다"의 정의가 없음. 파일 존재 = 완성.
3. **너무 큰 단위** — 9주짜리 phase가 우선순위에서 항상 밀림.

→ **v5는 매주 1개 산출물 + 다음 주 차주 산출물 검증 게이트 + 외부 일자 데드라인** 3종 세트로 운영.

---

## 2. Phoenix 5월 세션에서 검출된 10개 실전 갭

5월 14~15일 Phoenix 프로젝트(매수 GA·보험채권평가, 비즈 문서 워크스페이스) 운영 중 노출된 갭. v4 기획안은 *코드 프로젝트* 전제로 만들어졌으나 Phoenix는 *문서 프로젝트* — 이 차이가 첫 갭이다.

### 갭 1 · 프로젝트 타입 인식 부재 ⭐
- **증상**: proactive-scan이 "console.error/warn 2개" 같은 코드 신호를 비즈 문서 프로젝트에 보고. tsc/eslint 트리거가 무의미하게 시도됨.
- **원인**: `PROJECT_TYPE`이 없음. 모든 프로젝트를 code 워크스페이스로 가정.
- **해법**: `.claude/project-type.yaml` (code / doc / hybrid) + 트리거 매트릭스 차등.

### 갭 2 · PARKED 이슈 좀비화
- **증상**: PLAN 27건이 4월부터 PARKED 누적. 자동 부활 조건 없음.
- **원인**: 부활 트리거가 사용자 수동 명령에만 의존.
- **해법**: 마일스톤 날짜 도래 / 주기 N일 / 의존 이슈 완료 3가지 부활 트리거.

### 갭 3 · Assignee 92% 누락
- **증상**: 50개 이슈 중 46개가 `assignee: null`.
- **원인**: registry write 시 어사인 강제 안 됨. axis-router가 dispatch 시점에만 동작.
- **해법**: registry write hook 강제 어사인 + 부재 시 axis-router 자동 호출.

### 갭 4 · meta_observations 0건
- **증상**: v3 meta-review 시스템 도입됐지만 누적 0건. session-resume이 "Meta관찰 75개" 표시는 다른 카운터의 오인.
- **원인**: meta-review.sh가 SubagentStop에서 트리거되지만 실제 분석 로직이 빈 함수.
- **해법**: 7개 패턴 탐지 로직 실구현 + 주 1회 강제 회고.

### 갭 5 · 보고서 산출물(Artifacts) 미자산화 ⭐
- **증상**: 이번 세션 PDF 2개 생성됐지만 registry에 메타 없음. "어떤 보고서가 언제 누구를 위해" 추적 불가.
- **원인**: result JSON에 file 경로만 들어가고 별도 자산 레지스트리 없음.
- **해법**: `.claude/artifacts/registry.json` 별도 인덱스 + 보고서·디자인·PDF·HTML 모두 메타 (target_audience, version, supersedes, locale).

### 갭 6 · Dispatch 큐 중복 알림
- **증상**: Stop hook이 매 턴마다 같은 "READY N개" 알림 반복 → 노이즈.
- **원인**: 큐 알림이 idempotent 아님.
- **해법**: 큐 hash 기반 dedup — 직전 턴과 동일하면 알림 생략.

### 갭 7 · 사용자 메시지 vs harness 큐 충돌 ⭐
- **증상**: 대표님이 "0019 reverse what-if 시나리오" 질문했는데 harness는 "ISS-052 즉시 실행" 요구. 직접 충돌.
- **원인**: 사용자 입력 우선 게이트 없음. Stop hook이 어떤 상황에서도 큐 강제.
- **해법**: 직전 사용자 메시지가 있으면 그 처리 먼저, harness 큐는 사용자 응답 후 재개.

### 갭 8 · T2 컨펌 자동 감지 부재
- **증상**: 이번 세션에 git push(원격 첫 push, EXTERNAL), repo public→private 전환(SECURITY) 모두 T2 발동 안 됨. 사람 판단으로만 컨펌.
- **원인**: T2 카테고리 정의는 있지만 자동 감지 hook 없음.
- **해법**: PreToolUse Bash 정규식 매처 — `gh repo edit`, `git push --force`, `gh api ... visibility` 등.

### 갭 9 · CHECK 축 Codex 전환 트리거 부재
- **증상**: v4 2축 아키텍처 도입됐지만 8개월째 `CHECK_PROVIDER=claude` 고정.
- **원인**: Phase 2 진입 조건 명문화 안 됨.
- **해법**: 모드별 진입 조건 (예: `code` 모드 통과율 95%+ 시 자동 Codex 파일럿).

### 갭 10 · 보고서 PDF 자동 검증 부재
- **증상**: 이번 세션도 표지 PNG 추출 + 시각 확인을 수동으로 함. 2026-05-14 백지 incident 재발 가능성.
- **원인**: `post-generate-verify.sh`에 PDF 분기 없음.
- **해법**: 파일 확장자 `.pdf` 감지 → sips PNG 자동 추출 → 백지 휴리스틱 (단색 비율) → 실패 시 재시도.

---

## 3. v5 산출물 11개 (3 Track)

### Track A · 즉시 가치 (Week 1, 3개)
*이번 주 안에 한 개씩 출시. 검증 게이트 반드시 통과해야 다음으로 진행.*

#### A1. `.claude/project-type.yaml` + 트리거 매트릭스
- **무엇**: 프로젝트 루트에 `project-type: doc` / `code` / `hybrid` 선언. installer가 자동 감지 후 초안 작성.
- **트리거 매트릭스** (예):
  | Trigger | code | doc | hybrid |
  |---|---|---|---|
  | proactive-scan tsc/eslint | ✅ | ❌ | ✅ |
  | proactive-scan TODO/FIXME | ✅ | ⚠️ md 한정 | ✅ |
  | screen-gap-scan | ✅ | ❌ | ✅ |
  | PDF/문서 동기화 검사 | ❌ | ✅ | ✅ |
  | git status 미커밋 알림 | ✅ | ✅ | ✅ |
- **검증**: Phoenix(doc) + InsureGraph(code) 각 1회 proactive-scan 실행 결과가 다르게 나오는지.
- **위치**: `global/installers/detect-project-type.sh` + `project/.claude/project-type.yaml`

#### A2. User-Input Priority Gate (갭 7)
- **무엇**: Stop hook 진입 시 직전 turn의 user 메시지가 *질문 형태*거나 *명시 지시*면, harness 큐 강제 발동 보류.
- **로직**:
  ```bash
  # last user message에 "?" 또는 명령형 동사 포함 시
  if has_pending_user_request; then
    suppress_queue_dispatch
    show_quiet_status_only
  fi
  ```
- **검증**: 이번 세션 같은 충돌이 재발하지 않는지 (시뮬레이션 케이스 3개).
- **위치**: `project/.claude/hooks/dispatch-ready.sh`에 PriorityGate 추가.

#### A3. Dispatch 큐 dedup (갭 6)
- **무엇**: 큐 알림 텍스트의 hash를 `.claude/.last-dispatch-hash`에 저장 → 동일하면 침묵.
- **검증**: 동일 큐 상태에서 Stop hook 2회 연속 실행 시 두 번째는 출력 없음.
- **위치**: `dispatch-ready.sh` 마지막 단계.

---

### Track B · 자산화 + 자동 검증 (Week 2~3, 4개)

#### B1. Artifacts Registry (갭 5)
- **무엇**: `.claude/artifacts/registry.json` — PDF/HTML/디자인 시안/JSON 데이터 등 산출물 통합 인덱스.
- **스키마**:
  ```json
  {
    "id": "ART-001",
    "type": "pdf|html|json|design",
    "path": "/Users/.../Downloads/거꾸로계산기_Phoenix시나리오_260515.pdf",
    "issue_id": "ISS-055",
    "title": "거꾸로 생각하는 계산기 — Phoenix 적용 시나리오",
    "audience": "general|exec|engineering|legal",
    "version": "v1",
    "supersedes": null,
    "created_at": "2026-05-15T10:31:00Z",
    "verified": {"cover_png": true, "page_count": 6, "blank_ratio": 0.0}
  }
  ```
- **연동**: report-pdf-builder skill이 PDF 생성 후 자동 등록.
- **검증**: ISS-052/055 산출물 2건이 등록되는지.

#### B2. PDF 자동 검증 (갭 10)
- **무엇**: `post-generate-verify.sh` PDF 분기 — sips로 1페이지 PNG 추출 → 백지 휴리스틱.
- **백지 휴리스틱**: PNG 픽셀 분석 — 단일 색상 비율 > 95% → 백지 의심 → 재빌드 트리거.
- **검증**: 의도적으로 빈 HTML로 PDF 생성 시 자동 감지되는지.
- **위치**: `project/.claude/hooks/post-generate-verify.sh`

#### B3. T2 자동 감지 hook (갭 8)
- **무엇**: PreToolUse Bash 정규식 매처 → T2 패턴 발견 시 자동 `request-user-confirm.sh` 호출.
- **패턴 (초기 12개)**:
  - EXTERNAL: `git push --force`, `gh repo create`, `gh repo edit.*visibility`, `kamal deploy`, `npm publish`
  - SECURITY: `chmod -R`, `gh api.*collaborators`, `.env` write, `secrets`
  - BUDGET: opus-budget-check.sh가 Hard Cap 근접 신호
  - DIRECTION: brand-dna.json write, CLAUDE.md write
  - EXPLICIT: 이슈 payload의 requires_user_confirm
- **검증**: 이번 세션 git push / repo visibility 변경이 자동 컨펌 요구하는지.

#### B4. PARKED 이슈 부활 엔진 (갭 2)
- **무엇**: session-resume 시점에 PARKED 이슈 스캔 → 부활 조건 충족 시 READY 승격.
- **부활 조건**:
  1. payload.milestone_date 도래 (예: "2026-06-01" 이전 7일)
  2. payload.depends_on의 모든 이슈 DONE
  3. parked_at + 30일 경과 시 "stale review" 알림 (자동 부활은 안 함, 사용자 결정 촉구)
- **검증**: Phoenix PARKED 27개 중 마일스톤 도래분 자동 식별되는지.

---

### Track C · v4 잔여 핵심 (Week 4~7, 4개)

v4 P0 4개 중 *실제 작동 검증까지* 끌고 가는 게 목표.

#### C1. Decision Trace 실작동 (v4 D)
- **현재**: `decision-trace.sh` 파일 존재, 호출 0회.
- **할 일**: on_complete/on_fail/dispatch-ready 3개 hook에 trace 기록 코드 의무화 + `.claude/trace/YYYY-MM-DD.jsonl` 누적 검증.
- **검증**: 1일 운영 후 trace 파일에 5개 이상 이벤트 기록.

#### C2. Computational Sensor 강제 게이트 (v4 B)
- **현재**: lint/test가 ON_COMPLETE 후 *병렬*로 실행됨 → 실패해도 다음 단계 진행 가능.
- **할 일**: blocking gate 전환 + 3회 연속 실패 시 hermes-escalate.
- **검증**: 의도적 타입 에러로 GENERATE_CODE 완료 시 DEPLOY_READY 차단되는지.

#### C3. Observability Dashboard (v4 A)
- **현재**: `dashboard.sh` 존재, 사용 0회.
- **할 일**: `harness status` 단일 커맨드 + ANSI 컬러 + `--json` 옵션. session-resume에서 자동 호출.
- **검증**: 매 세션 시작 시 대시보드 출력이 의미 있는 숫자(이슈/예산/최근 실패) 표시하는지.

#### C4. Sandbox-lite (v4 C-lite)
- **현재**: `sandbox-enforce.sh` 존재. 정책 문서 없음.
- **할 일**: `SANDBOX_POLICY.md` 작성 + 12개 패턴 정규식. PreToolUse에 등록.
- **검증**: `rm -rf /`, `git push -f main` 등 실행 시 자동 차단.

---

## 4. v4와의 관계

| v4 항목 | v5 처리 |
|---|---|
| Phase 4.1 A Dashboard | **C3로 흡수** (실작동 검증까지) |
| Phase 4.1 B 강제 게이트 | **C2로 흡수** |
| Phase 4.1 C Sandbox-lite | **C4로 흡수** |
| Phase 4.1 D Decision Trace | **C1로 흡수** |
| Phase 4.2 (5개) | v5.1로 별도 (이번 기획 범위 밖) |
| Phase 4.3 (4개) | v5.2로 별도 |

→ v4 기획은 **폐기 아닌 흡수**. v5 Track C가 v4 P0를 완결한다.

---

## 5. KPI (v5)

| 지표 | v4 baseline | v5 target | 측정 방법 |
|---|---|---|---|
| 산출물 출시 주기 | 0개 / 8개월 | **1개 / 1주** | git log + registry |
| PARKED 좀비 이슈 | 27건 | < 5건 | session-resume 보고 |
| Assignee 누락률 | 92% | < 10% | registry 스캔 |
| 사용자 메시지 우선 충돌 | 이번 세션 1회 | 0회 / 월 | dispatch-ready 로그 |
| T2 자동 감지율 | 0% (수동) | > 80% (12 패턴 기준) | PreToolUse 로그 |
| PDF 백지 incident | 1건 (2026-05-14) | 0건 | post-verify 로그 |
| Trace 일일 이벤트 | 0 | > 20 | trace/*.jsonl |
| Codex CHECK 전환 모드 수 | 0/11 | 최소 1개 (Week 7) | check-harness.md status |

**측정 데드라인**: Week 8(2026-07-10) — 측정 못하면 v5도 drift.

---

## 6. 일정 (외부 데드라인 강제)

| 주차 | 산출물 | 외부 검증 데드라인 |
|---|---|---|
| Week 1 (5/15~5/22) | A1 A2 A3 | 5/22 — Phoenix proactive-scan 결과로 검증 |
| Week 2 (5/23~5/29) | B1 B2 | 5/29 — 이번 세션 PDF 2건 자산 등록 검증 |
| Week 3 (5/30~6/5) | B3 B4 | 6/5 — Phoenix PARKED 27건 자동 분류 결과 |
| Week 4 (6/6~6/12) | C1 (Decision Trace) | 6/12 — 5일치 trace JSONL 분석 보고 |
| Week 5 (6/13~6/19) | C2 (Computational Gate) | 6/19 — 의도적 실패 케이스 차단 데모 |
| Week 6 (6/20~6/26) | C3 (Dashboard) | 6/26 — 매 세션 첫 5초 안에 대시보드 확인 |
| Week 7 (6/27~7/3) | C4 (Sandbox-lite) | 7/3 — 5개 위험 명령 차단 데모 |
| Week 8 (7/4~7/10) | KPI 측정 + 회고 | 7/10 — v5.1(Phase 4.2 이관) 진입 결정 |

**외부 데드라인**: 매주 금요일 18시 — 산출물 미완 시 다음 주 첫 작업으로 자동 carry-over + 메타 회고 1건 강제 기록.

---

## 7. 리스크 & 완화

| 리스크 | 영향 | 완화 |
|---|---|---|
| v4 같은 표류 재발 | 또 8개월 미실행 | 외부 일자 데드라인 + Week 8 KPI 측정 강제 |
| 프로젝트 타입 오분류 | Phoenix가 code로 잡혀 부적절 트리거 | A1 출시 직후 5개 프로젝트 수동 검증 |
| T2 자동 감지 오탐 | 정상 작업 차단 | 초기 12 패턴 한정 + 화이트리스트 우회 가능 |
| Codex 전환 비용 | 외부 API 호출 비용 | Week 7는 *드라이런*만 (실호출 안 함) — v5.1에서 본 전환 |
| Phoenix 본업 방해 | harness 작업이 비즈 문서 작업 지연 | Phoenix Stage 0 Closing(12월)과 무관 영역 — 병행 가능 |

---

## 8. 승인 사항 (대표님 결정 필요)

다음 4가지에 대한 결정 부탁드립니다:

### 결정 1 — Track 범위
- **A안**: 11개 전부 7주에 (위 일정)
- **B안**: Track A + B만 (8개, 3주) → C는 별도 진입 결정
- **C안**: Track A만 (3개, 1주) → 검증 후 B/C 진입 재논의 ⭐ *추천*

### 결정 2 — 첫 산출물
- A1 (프로젝트 타입 인식) — Phoenix 본인이 첫 수혜자
- A2 (User-Input Priority Gate) — 이번 세션 충돌 즉시 해결
- A3 (Dispatch dedup) — 노이즈 즉시 감소

### 결정 3 — KPI 외부 데드라인 (Week 8)
- 측정 못하면 v5도 drift로 간주하고 **harness 자체를 단순화**할 것인가?
- 또는 한 번 더 연장할 것인가?

### 결정 4 — Phoenix와의 우선순위
- Phoenix Stage 0 Closing(12월)이 절대 마일스톤. 그 전에 GA Watch List·평가모델·샌드박스 신청서 작업 비중이 매우 큼.
- v5는 **유휴 시간 활용** 정도로 처리할지, **전용 1일/주 할당**할지?

---

## 9. 참고

- v4 기획안: `GH_Harness/docs/v4-upgrade-plan.md` (2026-04-22)
- Phoenix 세션 trace: `.claude/trace/2026-05-15.jsonl`
- Phoenix registry 스냅샷: 50 이슈, PARKED 27, DONE 23, READY 0
- Fowler/LangChain/NxCode 3개 레퍼런스: v4 §1 참고
