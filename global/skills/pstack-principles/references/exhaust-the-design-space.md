# 설계 공간을 다 훑는다 (Exhaust the Design Space)

> 언제: 코드베이스에 선례가 없는 새로운 UI 상호작용이나 아키텍처 결정을 앞뒀을 때.

결정하기 전에 경쟁하는 프로토타입 2~3개를 만들어 나란히 비교한다. (원문 frontmatter 설명)

사용자 경험이 논리보다 **느낌**에 달린 제품 설계 결정에도 적용된다.

하네스 연결: 프로토타입도 코드면 Codex 에 각각 위임한다(같은 저장소 동시 실행 금지 → 순차 또는 worktree 분리). 여러 provider 로 겨루려면 RACE_MODE 를 쓴다.

> 참고: 원문 본문은 이 한 문장뿐이다(원본 그대로).

---

## 영어 원문 (open-pstack `principle-exhaust-the-design-space`, 그대로)

원문의 상대 링크(`../principle-*/SKILL.md`)는 이 스킬에서 `references/<원칙이름>.md` 에 해당한다.

````markdown
---
name: principle-exhaust-the-design-space
description: "Apply when facing a novel UI interaction or architectural decision with no precedent in the codebase. Build 2-3 competing prototypes and compare side by side before committing."
user-invocable: false
---

# Exhaust the Design Space

It also applies to product design decisions where user experience depends on feel, not logic.
````
