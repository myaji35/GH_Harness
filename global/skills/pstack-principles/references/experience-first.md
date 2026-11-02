# 경험이 먼저다 (Experience First)

> 언제: 제품·UX·기능 범위의 트레이드오프가 생길 때.

구현의 편리함과 사용자의 기쁨이 부딪히면 기쁨을 고른다.

- 모든 기능·컨트롤·옵션은 존재 이유가 있어야 한다.
- 적게, 더 좋게 낸다(다듬어진 기능 3개가 거친 기능 10개보다 낫다).
- 확정 전에 프로토타입을 만든다(설계 결정은 운영 코드보다 버리는 HTML 에서 훨씬 싸다).
- 세부를 제대로 한다(전환, 정렬, 간격, 피드백, 에러 상태).
- 핵심 루프를 조인다(모든 기능은 중심 워크플로우를 돕거나 비켜서야 한다).

사용자는 그 작업을 쓰는 사람 누구나다. UI 라면 최종 사용자, 라이브러리·내부 API 라면 그것을 가져다 쓰는 동료. 다음에 코드를 유지보수할 엔지니어도 사용자다. 그들의 경험도 같은 무게로 따지고, 영향은 그들의 관점에서 설명한다.

기반은 경험을 위해 있다. 기반적 사고는 작업의 *순서*를 정하고, 이 원칙은 *목표*를 정한다.

하네스 연결: 화면 작업이면 brand-dna.json 과 UI 가독성 규칙(프로젝트 CLAUDE.md)이 "세부를 제대로"의 기준이다.

---

## 영어 원문 (open-pstack `principle-experience-first`, 그대로)

원문의 상대 링크(`../principle-*/SKILL.md`)는 이 스킬에서 `references/<원칙이름>.md` 에 해당한다.

````markdown
---
name: principle-experience-first
description: "Apply when product, UX, or feature-scope tradeoffs come up. Choose user delight over implementation convenience; ship fewer polished features over more rough ones."
user-invocable: false
---

# Experience First

When implementation convenience conflicts with user delight, choose delight.

- Every feature, control, and option must be justified
- Ship less, ship better (polished experience with three features beats rough one with ten)
- Prototype before committing (design decisions are cheaper in throwaway HTML than production code)
- Get the details right (transitions, alignment, spacing, feedback, error states)
- Tighten the core loop (every feature should serve the central workflow or get out of the way)

The user is whoever consumes the work. For a UI that is the end user. For a library or an internal API it is the colleague who imports it. The engineer who maintains the code next is a user too. Weigh their experience the same way, and explain impact from their perspective.

Foundations should serve the experience. Foundational thinking governs the *sequence* of work. This principle governs the *target*.
````
