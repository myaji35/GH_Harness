# 게으름 규약 (Laziness Protocol)

> 언제: 리팩토링할 때, diff 크기를 따질 때, 추상화·계층·신호 전달 경로를 더하고 싶을 때.

삭제 쪽으로, 문제를 푸는 가장 작은 변경 쪽으로 기운다. (원문 frontmatter 설명)

- **결정을 한곳에 모은다.** 같은 선택을 여러 곳에서 반복하지 않는다. 진실의 원천 하나 뒤에 두고 결과를 단순한 플래그로 넘긴다.
- **diff 를 최소화한다.** 문제를 푸는 가장 작은 변경을 한다. "우아한" 보일러플레이트보다 줄 수가 적은 쪽이 낫다.

하네스 연결: Codex 위임 지시에 "이 범위 밖은 건드리지 마라"를 적고, 위임 후 검수에서 과잉 변경을 잡는다(RACE_MODE 채점의 diff_size 항목과 같은 방향).

> 참고: 원문 본문은 이 두 항목뿐이다(원본 그대로).

---

## 영어 원문 (open-pstack `principle-laziness-protocol`, 그대로)

원문의 상대 링크(`../principle-*/SKILL.md`)는 이 스킬에서 `references/<원칙이름>.md` 에 해당한다.

````markdown
---
name: principle-laziness-protocol
description: "Apply when refactoring, evaluating diff size, or tempted to add abstractions, layers, or signal threading. Bias toward deletion and the smallest change that solves the problem."
user-invocable: false
---

# Laziness Protocol

- **Consolidate decisions.** Do not repeat the same choice in several places. Put it behind one source of truth and pass the result as a simple flag.
- **Minimize the diff.** Make the smallest change that solves the problem. Fewer lines beat "elegant" boilerplate.
````
