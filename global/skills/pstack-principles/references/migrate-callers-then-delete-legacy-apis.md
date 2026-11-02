# 호출자를 옮기고 옛 API 를 지운다 (Migrate Callers Then Delete Legacy APIs)

> 언제: 옛 호출자가 남아 있는 상태에서 새 내부 API 를 들일 때.

호환 계층을 남기지 말고, 호출자 이전과 옛 API 삭제를 **같은 물결**에서 끝낸다. (원문 frontmatter 설명)

- 테스트는 새 계약을 단언하도록 고치고, 리팩토링 전 구현 세부만 지키던 테스트는 지운다.

**적용 조건:**
- 하위 호환에 기대는 외부 사용자가 없다.
- 프로젝트가 조율된 깨짐 변경을 흡수할 수 있다.
- 새 API 가 단순화·리팩토링 작업의 일부다.

하네스 연결: 외부 사용자가 있는 API·핵심 기능 삭제는 T2(DIRECTION — 핵심 기능 삭제)이므로 대표님 확인 후에만. 내부 API 는 T0 로 진행한다.

> 참고: 원문 본문은 위 항목들뿐이다(원본 그대로).

---

## 영어 원문 (open-pstack `principle-migrate-callers-then-delete-legacy-apis`, 그대로)

원문의 상대 링크(`../principle-*/SKILL.md`)는 이 스킬에서 `references/<원칙이름>.md` 에 해당한다.

````markdown
---
name: principle-migrate-callers-then-delete-legacy-apis
description: "Apply when introducing a new internal API while old callers still exist. Migrate callers and delete the old API in the same wave instead of preserving compatibility layers."
user-invocable: false
---

# Migrate Callers Then Delete Legacy APIs

- Update tests to assert the new contract, and delete tests that only protect pre-refactor implementation details

**When this applies:**
- No external users depend on backward compatibility
- The project can absorb coordinated breaking changes
- The new API is part of a simplification or refactor initiative
````
