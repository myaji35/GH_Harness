# 기반부터 생각한다 (Foundational Thinking)

> 언제: 로직을 쓰기 전 — 핵심 타입·자료구조 선택, 뼈대 대 기능 작업의 순서, 동시 행위자가 무엇을 공유하는지 물을 때.

**구조적 결정**은 선택지의 가치(option value)를 지킨다. **코드 수준 결정**은 단순함을 지킨다.

**자료구조가 먼저다.** 로직을 쓰기 전에 데이터 모양을 바로 잡는다. 핵심 타입을 일찍 정의하고, 모든 접근 패턴을 따라가 보고, 주된 경로에 맞는 구조를 고른다.

코드 수준에서는 모든 줄이 아니라 구조를 DRY 하게 한다. 타입과 데이터 모델은 하나로 모여야 한다. 비슷한 문장 세 개가 섣부른 추상화보다 낫다. 영리함보다 명시성을 택한다. 줄 수가 아니라 동작과 경계 사례를 테스트한다.

**동시성 따름정리.** 행위자 사이에 상태를 공유하기 전에 "다른 행위자가 이걸 동시에 바꾸면 어떻게 되나?"를 묻는다. 답이 "아무 일도 없다"가 아니면 격리한다.

**뼈대가 먼저다.** 이후 모든 단계를 돕는 것은 먼저 한다. "이게 있으면 이후 모든 단계가 득을 보나?"를 묻는다. CI, 린트, 테스트 인프라, 공유 타입이 뼈대다. 선택지의 가치를 위해 순서를 짠다: 기능 전에 설정, 수정 전에 테스트. 커밋은 작고 한 가지 목적으로.

각 증분은 일관된 추상화 하나를 세우거나 있는 것을 깊게 해야 한다. 새 능력을 호출자들에 특수 사례 조율로 흩뿌리지 않는다.

뼈대보다 빼기가 먼저다. 죽은 코드를 먼저 지우고 기반을 깐다.

---

## 영어 원문 (open-pstack `principle-foundational-thinking`, 그대로)

원문의 상대 링크(`../principle-*/SKILL.md`)는 이 스킬에서 `references/<원칙이름>.md` 에 해당한다.

````markdown
---
name: principle-foundational-thinking
description: "Apply before writing logic: choosing core types and data structures, sequencing scaffold-vs-feature work, asking what concurrent actors share. Get the data structures right so downstream code becomes obvious."
user-invocable: false
---

# Foundational Thinking

**Structural decisions** protect option value. **Code-level decisions** protect simplicity.

**Data structures first.** Get the data shape right before writing logic. Define core types early, trace every access pattern, and choose structures that match the dominant paths.

At code level, DRY the structure, not every line. Types and data models should converge. Three similar statements still beat a premature abstraction. Prefer explicit over clever. Test behavior and edge cases, not line counts.

**Concurrency corollary.** Before sharing state between actors, ask "what happens if another actor modifies this concurrently?" If not "nothing", isolate.

**Scaffold first.** If something helps every later phase, do it first. Ask "does every subsequent phase benefit from this existing?" CI, linting, test infrastructure, and shared types are scaffold. Sequence for option value: setup before features, tests before fixes. Keep commits small and single-purpose.

Each increment should land a coherent abstraction or deepen one that exists. Do not spread a new capability across callers as special-case coordination.

Subtraction comes before scaffolding. Remove dead code first, then lay foundations.
````
