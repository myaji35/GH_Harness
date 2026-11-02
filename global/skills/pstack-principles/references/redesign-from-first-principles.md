# 제1원리에서 다시 설계한다 (Redesign From First Principles)

> 언제: 새 요구사항을 기존 설계에 통합할 때.

변경을 통합할 때 기존 설계에 덧대지 않는다. 그 요구사항이 처음부터 기반 가정이었던 것처럼 다시 설계한다.

- 영향받는 파일을 모두 읽고 현재 설계를 이해한다.
- 묻는다: "이 새 요구사항을 안고 처음부터 쓴다면 무엇을 만들까?"
- 변경을 모든 참조로 퍼뜨린다: 타입, 문서, 예시, 근거 절.
- 재설계 전체를 생각한 뒤, 점진적으로 전달한다.

이것이 기존 설계에 변경을 통합하면서 선택지의 가치를 지키는 방법이다.

하네스 연결: 재설계가 아키텍처 패러다임·기술 스택 교체에 이르면 T2 DIRECTION 이다.

---

## 영어 원문 (open-pstack `principle-redesign-from-first-principles`, 그대로)

원문의 상대 링크(`../principle-*/SKILL.md`)는 이 스킬에서 `references/<원칙이름>.md` 에 해당한다.

````markdown
---
name: principle-redesign-from-first-principles
description: "Apply when integrating a new requirement into an existing design."
user-invocable: false
---

# Redesign From First Principles

When integrating a change, don't bolt it onto the existing design. Redesign as if the requirement had been a foundational assumption from the start.

- Read all affected files and understand the current design
- Ask: "if we were writing this from scratch with this new requirement, what would we build?"
- Propagate the change through every reference: types, docs, examples, rationale sections
- Think about the whole redesign, then deliver it incrementally

This is the method for preserving option value when integrating changes into an existing design.
````
