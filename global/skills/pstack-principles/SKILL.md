---
name: pstack-principles
description: |
  설계·디버깅·리팩토링·마이그레이션·테스트 작성·수치 보고·병렬 작업 직전에 지금 상황에 맞는
  엔지니어링 원칙 하나를 골라 읽는다(open-pstack principle-* 23개를 하네스 규칙에 맞게 옮김).
  자료구조·타입 설계, 근본 원인 디버깅, 빼기 먼저, 멱등성, 공유 상태 분리, 동작 테스트,
  완료 전 증명, 숫자 설명, 컨텍스트 관리, 멈추지 않기 등. 대표님이 "원칙대로", "pstack 원칙",
  "/pstack-principles" 라고 할 때도 사용한다. 상황 표에서 파일 하나만 읽는다.
triggers:
  - 원칙대로
  - pstack 원칙
  - /pstack-principles
  - 설계 직전
  - 디버깅
  - 리팩토링
  - 마이그레이션
  - 테스트 작성
  - 수치 보고
  - 병렬 작업
---

# pstack 원칙

> 출처: open-pstack principle-* (MIT, NOTICE.md). GH_Harness 규칙에 맞게 옮김.

## 쓰는 법

1. 아래 표에서 **지금 상황**에 해당하는 행을 찾는다.
2. 그 행의 `references/<원칙이름>.md` **하나만** 읽는다(점진적 로딩). 상황이 둘에 걸치면 둘까지만.
3. 답변·보고에서 그 원칙이 **어떤 결정을 바꿨는지** 한 줄로 밝힌다. 이번 세션에 읽지 않은 원칙은 인용하지 않는다.
4. 각 파일은 한국어 본문(하네스 규칙과 연결) + 맨 아래 영어 원문이다. 충돌하면 한국어 본문의 하네스 규칙이 이긴다.

원칙은 하네스 규칙을 **대체하지 않는다.** 자율 실행 원칙·3-Tier 컨펌(T0/T1/T2)·사용자 명시값 절대 우선·Codex 위임(코드는 Codex 가 짠다)이 언제나 위에 있다.

## 상황 → 읽을 원칙 파일

### 설계 (코드를 쓰기 전)
| 상황 | 원칙 — 한 줄 요약 | 파일 |
|---|---|---|
| 로직을 쓰기 전 핵심 타입·자료구조를 고를 때, 뼈대 대 기능 순서 | 기반부터 생각한다 — 데이터 모양을 먼저 바로 잡으면 이후 코드가 뻔해진다 | `references/foundational-thinking.md` |
| 상태 있는 로직, 분기가 많거나 같은 모양 가정이 여러 파일에 반복 | 도메인을 모델링한다 — 조건문 대신 상태 기계·타입 모델·테이블에 도메인을 새긴다 | `references/model-the-domain.md` |
| 타입·함수 시그니처 설계 | 타입 시스템 규율 — 불가능한 상태를 표현 못 하게, 원시 타입에 상표, 스키마에서 도출 | `references/type-system-discipline.md` |
| 검증·에러 처리·프레임워크 어댑터 연결 | 경계 규율 — 가드는 시스템 경계에, 내부는 타입을 믿고, 로직은 순수 함수로 | `references/boundary-discipline.md` |
| 새 요구사항을 기존 설계에 통합 | 제1원리에서 다시 설계한다 — 덧대지 말고 처음부터 있던 가정처럼 재설계 | `references/redesign-from-first-principles.md` |
| 선례 없는 UI 상호작용·아키텍처 결정 | 설계 공간을 다 훑는다 — 프로토타입 2~3개를 나란히 비교한 뒤 확정 | `references/exhaust-the-design-space.md` |
| 제품·UX·기능 범위 트레이드오프 | 경험이 먼저다 — 구현 편의보다 사용자 기쁨, 적게 더 좋게 | `references/experience-first.md` |
| 충돌·재시작·재시도 속에서 돌 명령·루프·hook 설계 | 연산을 멱등하게 — 몇 번 돌든 어디서 멈췄든 같은 최종 상태로 수렴 | `references/make-operations-idempotent.md` |

### 리팩토링·마이그레이션
| 상황 | 원칙 — 한 줄 요약 | 파일 |
|---|---|---|
| 추가·리팩토링·재작성의 순서 정하기 | 더하기 전에 뺀다 — 죽은 코드·중복 검증부터 걷어 낸다 (**핵심 기능 삭제는 T2 경계 안쪽에서만**) | `references/subtract-before-you-add.md` |
| 리팩토링, diff 크기 판단, 추상화·계층을 더하고 싶을 때 | 게으름 규약 — 삭제 쪽으로, 문제를 푸는 가장 작은 변경 | `references/laziness-protocol.md` |
| 따라가기 어려운 코드 검토·정리 | 읽는 사람의 부담을 줄인다 — 계층 수와 숨은 상태를 세고 접는다 | `references/minimize-reader-load.md` |
| 옛 호출자가 남은 채 새 내부 API 도입 | 호출자를 옮기고 옛 API 를 지운다 — 호환 계층 없이 한 물결에 | `references/migrate-callers-then-delete-legacy-apis.md` |
| 단계 경계가 있는 계획된 재작성·마이그레이션 | 결과 중심으로 실행한다 — 매끄러운 중간 상태보다 검증 가능한 최종 상태 | `references/outcome-oriented-execution.md` |
| 사소하지 않은 수정·분석·점검 (일괄 작업 포함) | 지렛대를 만든다 — 손 대신 다시 돌릴 수 있는 스크립트·codemod (지렛대 코드도 Codex 가 짠다) | `references/build-the-lever.md` |

### 디버깅·검증·테스트
| 상황 | 원칙 — 한 줄 요약 | 파일 |
|---|---|---|
| 디버깅 | 근본 원인을 고친다 — 증상이 아니라 처음 잘못된 곳을 고친다, 가드는 정당한 상태일 때만 수정 | `references/fix-root-causes.md` |
| 테스트를 쓰거나 바꾸거나 남길지 정할 때 | 구현이 아니라 동작을 테스트한다 — 동작이 깨지면 실패, 내부만 바뀌면 통과 | `references/test-behavior-not-implementation.md` |
| 완료 선언 직전 | 동작을 증명한다 — 대리 지표 말고 진짜를 확인 (**on_complete 가 `result.proof` 없으면 거부 — 이미 게이트**) | `references/prove-it-works.md` |
| 여러 단계 작업, 커밋·PR 쌓기 | 검증 가능한 단위로 순서를 짠다 — 단위마다 초록 확인 후 다음 | `references/sequence-verifiable-units.md` |
| 잰 숫자(속도·회귀·처리량·지연·평가)를 보고·신뢰하기 전 | 숫자를 설명한다 — 제한 요인을 대고 다른 걸 잰 게 아닌지 배제 (**on_complete 게이트: result.number_sources 필수, 2026-11-03부터 warn 모드**) | `references/explain-the-number.md` |

### 병렬·위임·운영
| 상황 | 원칙 — 한 줄 요약 | 파일 |
|---|---|---|
| 동시 행위자가 같은 파일·브랜치·키에 쓸 수 있을 때 | 직렬화하기 전에 분리한다 — 공유를 먼저 없애고, 진짜 불변식일 때만 구조로 직렬화 | `references/separate-before-serializing-shared-state.md` |
| 컨텍스트가 차오를 때(큰 출력·긴 파일·팬아웃 계획) | 컨텍스트 창을 지킨다 — progressive-disclosure 로 덜 읽고, 대량 탐색만 서브에이전트, 코드는 Codex | `references/guard-the-context-window.md` |
| 되돌릴 수 있는 일에 "할까요?"가 떠오를 때 | 사람을 기다리며 멈추지 않는다 — 하네스 T0/T1/T2 와 같은 방향 (**T2 5개 카테고리는 예외**) | `references/never-block-on-the-human.md` |
| 같은 지시·교정을 두 번째 쓰고 있을 때 | 교훈을 구조에 새긴다 — 글을 늘리지 말고 lint·hook·검사로 | `references/encode-lessons-in-structure.md` |

## 제외 원칙과 이유

- `principle-attack-the-premise`(실패한 수정들의 공통 전제를 의심하라) — **2026-10-18 대표님 결정으로 넣지 않는다.** 하네스의 "사용자 명시값 절대 우선" 규칙과 충돌한다(명시값을 전제로 의심해 대체하는 근거가 될 수 있음). 같은 수정이 반복 실패하면 대신 T1(`hermes-escalate.sh`, REPEAT_FAIL)로 올린다.

## 하네스 규칙에 맞춘 주요 변경

| 원칙 | 바뀐 점 |
|---|---|
| subtract-before-you-add | 핵심 기능 삭제는 T2(DIRECTION) 확인 후에만. 내부 정리는 T0 |
| prove-it-works | on_complete 의 `result.proof[{cmd,exit_code,output}]` 게이트와 연결. Codex 완료 보고는 proof 아님 |
| explain-the-number | 아직 게이트 아님(다음 단계 예정). 지금은 수치 보고 시 측정 명령 + 출처 파일을 같이 적는다 |
| never-block-on-the-human | T0/T1/T2 자율 실행 원칙과 연결. 원문의 "되돌릴 수 없는 행동"을 T2 5개 카테고리로 대응 |
| guard-the-context-window | "대량은 서브에이전트로"를 기본값으로 두지 않고 progressive-disclosure 우선 + 몇 번의 호출이면 직접 + 코드는 Codex |
| build-the-lever | 지렛대(스크립트·codemod)도 코드라 Codex 위임. 위임 스킬(.md)만 직접 작성. 같은 저장소 Codex 동시 실행 금지 |
