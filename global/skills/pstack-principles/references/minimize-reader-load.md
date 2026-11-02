# 읽는 사람의 부담을 줄인다 (Minimize Reader Load)

> 언제: 따라가기 어려운 코드를 검토하거나 다듬을 때.

유지보수성은 읽는 사람이 코드를 이해하는 데 드는 일이다. 두 축을 본다: **따라갈 계층**(질문과 답 사이의 간접 단계)과 **머리에 들고 있을 상태**(숨겨지거나 바뀔 수 있는 맥락). 줄 수, 순환 복잡도, "클린 아키텍처"는 대리 지표다. 중요한 것은 읽는 부담이다. 두 축은 서로 독립이다. 전역 변수 50개가 있는 평평한 파일도 6층 어댑터 스택만큼 이해하기 어렵다. 둘 다 지킨다. 이것은 [컨텍스트 창을 지킨다](guard-the-context-window.md)의 사람 버전이다. 읽는 사람의 작업 기억도 유한하다.

- **값보다 비싼 계층은 접는다:** 호출자 하나뿐인 래퍼, 두 번째 구현이 없는 어댑터, 필요한 적 없는 추측성 간접 계층. 인라인한다.
- **인접 계층은 추상화를 바꿔야 한다.** 같은 메서드와 인자를 반복하는 계층은 압축 없이 부담만 더한다. 통과만 하는 계층은 접는다.
- **인터페이스 압축을 요구한다.** 숨기는 복잡도는 적은데 넓은 인터페이스는 읽는 사람에게 표면과 구현을 둘 다 배우게 한다. 의미 있는 결정을 숨기는 경계를 택한다.
- **상태 범위를 줄인다:** 순수 함수(변경보다 반환), 필드보다 지역 변수, 모듈 상태보다 필드, 전역보다 모듈 상태. 동기화하지 말고 도출한다.
- **불변식은 모든 소비자가 아니라 경계에서 이름 붙인다.** 읽는 사람이 한 번만 배우게.
- 계층이나 상태를 더하기 전에 묻는다: 이게 다른 곳의 읽는 부담을 최소한 그만큼 줄이나?

**판별:** 새로 온 사람이 "X는 어디서 오나?"와 "무엇이 X를 바꿀 수 있나?"에 30초 안에 답할 수 있나? 아니라면 계층을 자르거나 상태를 자른다.

---

## 영어 원문 (open-pstack `principle-minimize-reader-load`, 그대로)

원문의 상대 링크(`../principle-*/SKILL.md`)는 이 스킬에서 `references/<원칙이름>.md` 에 해당한다.

````markdown
---
name: principle-minimize-reader-load
description: "Apply when reviewing or shaping code that's hard to trace. Count layers between question and answer, and hidden state in the reader's head; collapse one-caller wrappers and shrink mutable scope."
user-invocable: false
---

# Minimize Reader Load

Maintainability is the work a reader must do to understand code. Track two axes: **layers to trace** (indirections between the question and the answer) and **state to hold** (hidden or mutable context the reader must keep in their head). LOC, cyclomatic complexity, and "clean architecture" are proxies. Reader load is the thing that matters. The two axes are independent. A flat file with 50 globals can be as hard to reason about as a 6-layer adapter stack. Guard both. This is the human analog of [Guard the Context Window](../principle-guard-the-context-window/SKILL.md). Working memory is finite for readers too.

- **Collapse layers** that cost more than they save: wrappers with one caller, adapters with no second implementation, speculative indirection that was never needed. Inline them.
- **Make adjacent layers change the abstraction.** A layer that repeats the same methods and arguments adds reader load without compression. Collapse pass-through layers.
- **Demand interface compression.** A broad interface that hides little complexity makes readers learn both the surface and the implementation. Prefer boundaries that hide meaningful decisions.
- **Shrink state scope:** prefer pure functions (returns over mutations), locals over fields, fields over module state, and module state over globals. Derive instead of sync.
- **Name the invariant at the boundary,** not in every consumer, so the reader learns it once.
- Before adding a layer or a piece of state, ask: does it reduce reader load elsewhere by at least as much?

**The test:** can a new reader answer "where does X come from?" and "what can change X?" in under 30 seconds? If not, cut layers or cut state.
````
