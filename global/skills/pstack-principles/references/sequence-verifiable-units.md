# 검증 가능한 단위로 순서를 짠다 (Sequence Work into Verifiable Units)

> 언제: 여러 단계 작업(일괄 수정, 마이그레이션, 비슷한 수정의 연속)과 커밋·PR 을 쌓는 방식.

작업을 작은 단위의 순서로 짜고, 각 단위는 확인할 수 있는 상태로 끝나게 한다. 현재 단위가 초록이 될 때까지 다음으로 가지 않는다.

**왜:** 원인이 된 단위에서 잡힌 깨짐은 위치를 찾기 싸다. 묶음 뒤에 잡힌 깨짐은 묻혀 있고, 이미 깨진 바탕 위에 더 쌓은 뒤다. 같은 단위를 검수자가 재생할 수 있는 전달 순서로 짜면 "믿어 주세요"가 "빨강이 됐다가 초록이 되는 걸 보세요"로 바뀐다.

**실행.** 일괄 수정·마이그레이션 등 비슷한 수정의 연속에서는 다음을 시작하기 전에 각 변경을 검증한다. 각 단위는 앞뒤 괄호다: 알려진 정상 상태 → 변경 하나 → 점검 실행 → 진행. 먼저 깨끗한 trunk 위로 rebase 해서 모든 점검이 진짜 기준선과 비교되게 한다. 지렛대가 수정을 하면 단위별 점검은 거의 공짜다. 그래도 돌린다.

**전달.** 커밋과 PR 은 작업을 증명하는 순서로 쌓는다. 정석은 실패하는 테스트가 먼저, 그 위에 수정. 다른 이야기 순서: 재구성 전의 빼기, 처치 전의 기준선 측정, 기능 전의 뼈대. 각 커밋은 홀로 서고 순서 전체가 하나의 논증으로 읽힌다.

[동작을 증명한다](prove-it-works.md)(각 점검을 진짜로 유지)와 [지렛대를 만든다](build-the-lever.md)(단위별 점검을 싸게)의 순서 짜기 짝이다.

하네스 연결: 단위마다 Codex 위임 → `git diff` 검수 → 내가 실행해 검증 → 다음 위임. 커밋은 하네스 규칙대로 검증 통과 후에만.

---

## 영어 원문 (open-pstack `principle-sequence-verifiable-units`, 그대로)

원문의 상대 링크(`../principle-*/SKILL.md`)는 이 스킬에서 `references/<원칙이름>.md` 에 해당한다.

````markdown
---
name: principle-sequence-verifiable-units
description: "Apply to multi-step work (sweeps, migrations, runs of similar edits) and to how you stack commits and PRs. Break work into small units that each end in a verifiable state, check each before the next, and order delivery so the sequence proves itself to a reviewer."
user-invocable: false
---

# Sequence work into verifiable units

Order work as a sequence of small units, each ending in a state you can check, and don't advance until the current one is green.

**Why:** A break caught at the unit that caused it is cheap to localize. A break caught after a batch is buried, and you have already built further on a broken base. Sequencing those same units into a delivery a reviewer can replay turns "trust me" into "watch it go red, then green."

**Execution.** In a sweep, migration, or any run of similar edits, verify each change before starting the next. Each unit is a before/after bracket: known-good state, one change, run the check, then proceed. Rebase onto clean trunk first so every check measures against the real baseline. When a lever does the edits, the per-unit check is nearly free. Run it anyway.

**Delivery.** Stack commits and PRs in the order that proves the work. The canonical shape is the failing test first, then the fix on top. Other story orders are a subtraction before the reshape, a baseline capture before the treatment, the scaffold before the feature. Each commit lands on its own and the sequence reads as an argument.

The sequencing complement to the **prove-it-works** principle skill, which keeps each check real, and the **build-the-lever** principle skill, which makes the per-unit check cheap.
````
