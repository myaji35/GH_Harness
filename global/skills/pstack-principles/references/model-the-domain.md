# 도메인을 모델링한다 (Model the Domain)

> 언제: 상태가 있는 로직을 쓸 때, 또는 코드가 분기를 많이 하거나 같은 모양 가정을 여러 파일에서 반복할 때.

실제 도메인을 조건문에 흩뿌리지 말고 **자료구조**에 새긴다. 도메인에 맞는 구조는 잘못된 상태를 표현할 수 없게 만들고 분기를 지운다. 쓸 때 고르면 싸다. 나중에 되찾으려면 리팩토링이 되고, 미뤄진다.

이런 걸 쓴다:
- 흩어진 불리언·단계·생명주기 검사 대신 상태 기계.
- 느슨한 매개변수나 반복되는 모양 가정 대신 타입 있는 모델.
- 여러 파일에 퍼진 분기 대신 맵·레지스트리·조회 테이블·판별 유니온.
- 임시방편 상태 변경 대신 리듀서나 명령/이벤트 모델.
- load·validate·transform·save 같은 순서가 아니라 **도메인 지식 한 덩어리**를 중심으로 짠 모듈. 실행 순서는 소유가 아니다.
- 반복 동작·소유·불변식을 모으는 작은 모듈 경계.
- 접근 패턴이 요구하면 큐·캐시·인덱스·그래프·트리·정규화된 컬렉션.
- 그 밖에 맞는 구조 무엇이든. 맞는 게 없으면, 코드가 절대 허용하면 안 되는 것과 데이터가 어떻게 읽히는지를 따져 정확히 그것을 새기는 구조를 찾는다.

추상화를 억지로 넣지 않는다. 현재 모양이 이미 명확하고 국소적이며 커질 것 같지 않으면 지루한 코드가 낫다. 분기·중복 규칙·잘못된 상태·생명주기 위험을 지우지 않으면서 간접 단계만 늘리는 추상화는 의심한다.

건너뛰었다는 신호: 새 기능이 기존 if/else 사슬에 가지를 하나 더 붙인다, 첫 번째와 동기화돼야 하는 두 번째 불리언이 생긴다. 시간 순 분해도 신호다 — 단계 이름의 모듈들이 같은 도메인 규칙을 단계마다 반복한다.

---

## 영어 원문 (open-pstack `principle-model-the-domain`, 그대로)

원문의 상대 링크(`../principle-*/SKILL.md`)는 이 스킬에서 `references/<원칙이름>.md` 에 해당한다.

````markdown
---
name: principle-model-the-domain
description: "Apply when writing stateful logic, or when code branches a lot or repeats a shape assumption across files."
user-invocable: false
---

# Model the Domain

Encode the real domain in a data structure instead of scattering it across conditionals. A structure that matches the domain makes invalid states unrepresentable and deletes branches. Choosing it at write time is cheap. Recovering it later reads as a refactor and gets deferred.

Reach for:

- A state machine instead of scattered booleans, phases, or lifecycle checks.
- A typed model instead of loose parameters or repeated shape assumptions.
- A map, registry, lookup table, or discriminated union instead of branching spread across files.
- A reducer or command/event model instead of ad hoc state mutations.
- A module organized around one body of domain knowledge instead of a sequence such as load, validate, transform, and save. Execution order is not ownership.
- A small module boundary that gathers repeated behavior, ownership, or invariants.
- A queue, cache, index, graph, tree, or normalized collection where the access pattern calls for it.
- Any other structure that fits. When none fits, work out what the code must never allow and how the data gets read, then find the structure that encodes exactly that.

Do not force an abstraction. Prefer boring code if the current shape is already clear, local, and unlikely to grow. Be skeptical of an abstraction that adds indirection without removing branches, duplicated rules, invalid states, or lifecycle risk.

The sign that you skipped this is a new feature that grows an existing if/else chain by one more branch, or a second boolean that must stay in sync with the first. Temporal decomposition is another sign. Phase-named modules repeat the same domain rules across steps.
````
