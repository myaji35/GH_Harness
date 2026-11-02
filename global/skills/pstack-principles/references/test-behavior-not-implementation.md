# 구현이 아니라 동작을 테스트한다 (Test Behavior, Not Implementation)

> 언제: 테스트를 쓰거나, 바꾸거나, 남길지 정할 때.

테스트는 코드가 그 사용자(호출자, 최종 사용자, 다른 서비스)에게 무엇을 해 주는지에 대한 주장이다. 동작은 그 사용자가 쓰는 인터페이스로 관찰할 수 있는 것이다: 반환값, 에러, 다시 읽을 수 있는 상태, 코드 밖 시스템에 미친 효과(보낸 요청, 쓴 행, 내보낸 메시지). 구현은 그들이 관찰할 수 없는 것이다: 비공개 헬퍼, 내부 호출 순서, 중간 데이터, 어떤 내부 협력자가 일을 했는지.

각 테스트를 두 가지 상상 수정으로 판정한다:

- **동작을 깨뜨린다.** 코드가 틀린 값을 돌려주게, 효과를 건너뛰게, 효과를 두 번 하게 만든다. 그래도 테스트가 통과하면 아무것도 증명하지 못한다. 흔한 원인: 계약보다 느슨한 단언, 테스트 대상 코드로 계산한 기대값, 그것을 읽는 코드를 한 번도 돌리지 않는 상수·프롬프트 문자열 재진술, 테스트가 스스로 만든 데이터에 대한 단언.
- **내부를 바꾼다.** 관찰 가능한 결과는 모두 그대로 두고 아래 코드를 재구성한다. 테스트가 이제 실패하면 구현에 박혀 있는 것이다. 리팩토링마다 다시 써야 하고, 그래도 버그는 못 잡는다.

첫 번째 수정을 잡고 두 번째에서 살아남는 테스트를 남긴다. 나머지는 다시 쓰거나 지운다. 둘 다 하는 테스트를 쓰려면, 사용자의 인터페이스로 구체적 입력을 넣어 코드를 구동한다. 기대값은 코드 실행이 아니라 요구사항에서 도출한다. 계약이 약속하는 것을, 그보다 적지도 많지도 않게 단언한다.

단언의 모양이 아니라 계약이 결정한다. "빈 장바구니는 결제하지 않는다"가 약속이면 결제 클라이언트가 호출되지 않았다는 단언이 동작이다. 결제가 일어나는 사례와 짝지어, 테스트가 호출을 볼 수 있음을 보인다. 모킹된 외부 서비스가 받는 페이로드는 동작이다 — 그 서비스가 관찰하니까. 내부 헬퍼 호출은 구현이다 — 어떤 사용자도 볼 수 없으니까. 일치하는 레코드가 없을 때 빈 목록은 정확한 답이지만, 테스트가 아무 결과나 필요할 때는 빈 껍데기 검사다. 정확한 에러 메시지는 어떤 호출자도 읽지 않는 문구를 박는다. 호출자가 분기하는 에러 타입이 계약이다.

테스트는 호출 대신 불변식을 박을 수도 있다 — 두 테이블에 반드시 있어야 하는 키, 컴파일 타임 타입 검사. 불변식이 곧 동작이다.

하네스 연결: 테스트 작성·수정도 코드이므로 Codex 에 위임하고, 위 두 상상 수정을 검수 기준으로 지시에 넣는다.

---

## 영어 원문 (open-pstack `principle-test-behavior-not-implementation`, 그대로)

원문의 상대 링크(`../principle-*/SKILL.md`)는 이 스킬에서 `references/<원칙이름>.md` 에 해당한다.

````markdown
---
name: principle-test-behavior-not-implementation
description: "Apply when you write, change, or keep a test. Assert what the code's users can observe, so that the test fails when that behavior breaks and keeps passing when only the internals change."
user-invocable: false
---

# Test Behavior, Not Implementation

A test is a claim about what the code does for its users: a caller, an end user, or another service. Behavior is what those users can observe through the interface they use. That includes return values, errors, state they can read back, and effects on systems outside the code, such as a request sent, a row written, or a message emitted. Implementation is what they cannot observe: private helpers, internal call order, intermediate data, and which internal collaborator did the work.

Judge each test against two imagined edits:

- **Break the behavior.** Make the code return a wrong value, skip an effect, or do the effect twice. If the test still passes, it proves nothing. The usual causes are an assertion looser than the contract, an expected value computed by the code under test, a restated constant or prompt string that never runs the code that reads it, and an assertion on data that the test built itself.
- **Change the internals.** Keep every observable result the same and restructure the code underneath. If the test now fails, it is pinned to the implementation. It will need a rewrite on every refactor and still catches no bug.

Keep a test that catches the first edit and survives the second. Rewrite or delete the rest. To write a test that does both, drive the code through its users' interface with a concrete input. Derive the expected value from the requirement, not from a run of the code. Assert what the contract promises, no less and no more.

The contract decides, not the shape of the assertion. When "an empty cart never charges" is the promise, an assertion that the payment client got no call is behavior. Pair it with a case where the charge happens, so that the test shows it can see a call. The payload that a mocked external service receives is behavior, because that service observes it. A call to an internal helper is implementation, because no user can see it. An empty list is the exact answer when no record matches, and a hollow check when the test only needs some result. An exact error message pins wording that no caller reads. The error type that callers branch on is the contract.

A test can pin an invariant instead of a call, such as a key that must exist in two tables or a compile-time type check. The invariant is the behavior.
````
