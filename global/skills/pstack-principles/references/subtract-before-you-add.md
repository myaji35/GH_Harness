# 더하기 전에 뺀다 (Subtract Before You Add)

> 언제: 추가·리팩토링·재작성의 순서를 정할 때.

시스템을 발전시킬 때는 복잡도를 먼저 걷어 내고 그다음 짓는다. 기본값은 빼기다.

단순화를 지속적인 투자로 삼는다. 처음 봤을 때보다 같거나 더 작은 표면 뒤에서 조금 더 단순하고 조금 더 능력 있는 설계를 남긴다.

- 짓기 전에 제거를 배치한다.
- 다듬기 전에 자른다(품질에 투자하기 전에 최소한까지 간다).
- 추측성 경계 사례가 아니라 관찰된 사용에 맞춰 설계한다.
- 명세가 요구하는 것 이상의 추측성 검증기·파서·가드는 두지 않는다.
- 프롬프트를 단순하게(중복 지시, 과한 템플릿 제거).
- 새 내용이 없는 참조는 빈 껍데기로 두지 말고 지운다.

## 하네스 경계
- **핵심 기능 삭제는 T2(DIRECTION) 경계 안쪽에서만 이 원칙을 적용한다.** 죽은 코드·중복 검증·빈 참조 같은 내부 정리는 T0 로 바로 뺀다. 사용자에게 보이는 핵심 기능을 지우는 것은 `request-user-confirm.sh` 로 대표님 확인을 받은 뒤에만 한다.
- 지우는 작업도 코드 변경이면 Codex 에 위임한다.

---

## 영어 원문 (open-pstack `principle-subtract-before-you-add`, 그대로)

원문의 상대 링크(`../principle-*/SKILL.md`)는 이 스킬에서 `references/<원칙이름>.md` 에 해당한다.

````markdown
---
name: principle-subtract-before-you-add
description: "Apply when sequencing an addition, refactor, or rewrite. Remove dead code, redundant validators, and stub references first, then build on the simpler base."
user-invocable: false
---

# Subtract Before You Add

When evolving a system, remove complexity first, then build. Default to subtraction.

Make simplification a continual investment. Leave the design slightly simpler and more capable behind the same or smaller surface than you found it.

- Sequence removal before construction
- Cut before you polish (get to the minimum before investing in quality)
- Design for observed usage, not speculative edge cases
- No speculative validators, parsers, or guards beyond what the spec demands
- Simplify prompts (remove redundant instructions, excessive templates)
- When a reference has no novel content, delete it rather than leaving a stub
````
