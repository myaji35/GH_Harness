# 경계 규율 (Boundary Discipline)

> 언제: 검증·에러 처리·프레임워크 어댑터를 연결할 때.

검증, 타입 좁히기, 에러 처리는 **시스템 경계**에 모은다. 내부 코드는 조건 없이 믿는다. 비즈니스 로직은 순수 함수에 둔다. 바깥 껍데기(shell)는 얇고 기계적으로 유지한다.

**왜:** 흩어진 검증은 시끄럽고 중복되며 안전하다는 착각만 준다. 로직을 프레임워크 배선 밖에 두어야 프레임워크 없이 테스트할 수 있다.

**패턴:**
- **경계에서**(CLI 인자, 설정 파일, 외부 API, 네트워크 프로토콜): 검증하고, 에러를 돌려주고, 방어적으로 처리한다.
- **시스템 안에서:** 타입이 있는 데이터, 에러 전파, 재검증 없음. 타입을 믿는다.
- **경계를 넘을 때:** 경계의 내부 표현이 아니라 도메인 개념을 노출한다. 범용 메커니즘은 안쪽에, 특수 목적 정책은 가장자리에 둔다.

**적용:**

검증과 에러 처리
- 설정은 비즈니스 로직 안이 아니라 파싱 시점(경계)에 검증한다.
- 원시 데이터는 경계에서 도메인 타입으로 파싱한다.
- 전송·저장소·프레임워크·와이어 타입을 공개 표면으로 다시 내보내지 않는다.
- 경계에서 이미 검증했다면 호출 체인 깊은 곳에 중복 nil 검사를 두지 않는다.

코드 구성
- 비즈니스 로직은 프레임워크 의존이 없는 순수 함수로.
- 파싱 함수: 원시 바이트 → 타입 있는 상태로 바꾸는 순수 변환.
- 프롬프트 구성: 구조화된 상태를 넣으면 문자열이 나온다.
- 점수·평가: 상태 → 결과의 순수 변환.

**판별 질문:**
- "이 데이터가 지금 시스템 경계를 넘고 있나?" 아니라면 검증은 중복이다.
- "이걸 껍데기가 호출만 하는 순수 함수로 만들 수 있나?" 그렇다면 뽑아낸다.

---

## 영어 원문 (open-pstack `principle-boundary-discipline`, 그대로)

원문의 상대 링크(`../principle-*/SKILL.md`)는 이 스킬에서 `references/<원칙이름>.md` 에 해당한다.

````markdown
---
name: principle-boundary-discipline
description: "Apply when wiring validation, error handling, or framework adapters. Concentrate guards at system boundaries (CLI, config, network, external APIs); trust internal types and keep business logic in pure functions."
user-invocable: false
---

# Boundary Discipline

Place validation, type narrowing, and error handling at system boundaries. Trust internal code unconditionally. Business logic lives in pure functions. The shell is thin and mechanical.

**Why:** Scattered validation is noisy, redundant, and gives a false sense of safety. Keep logic out of framework wiring so it can be tested without the framework.

**The pattern:**
- **At boundaries** (CLI args, config files, external APIs, network protocols): validate, return errors, handle defensively.
- **Inside the system:** typed data, error propagation, no re-validation. Trust the types.
- **Across the boundary.** Expose domain concepts, not the boundary's private representation. Keep general-purpose mechanism inside and special-purpose policy at the edge.

**Applications:**

Validation and error handling:
- Validate config at parse time (the boundary), not inside business logic
- Parse raw data into domain types at the boundary
- Do not re-export transport, storage, framework, or wire types through the public surface
- No redundant nil checks deep in call chains if the boundary already validated

Code organization:
- Business logic in pure functions with no framework dependencies
- Parse functions: pure transforms from raw bytes to typed state
- Prompt construction: structured state in, string out
- Scoring and assessment: pure transforms from state to results

**The tests:**
- "Is this data crossing a system boundary right now?" If not, validation is redundant.
- "Can this be a pure function that the shell just calls?" If yes, extract it.
````
