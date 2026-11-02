# 지렛대를 만든다 (Build the Lever)

> 언제: 사소하지 않은 모든 작업 — 대량 작업만이 아니라 수정·마이그레이션·분석·점검 전부.

일이 사소하지 않으면 손으로 하지 말고 **그 일을 하는(또는 증명하는) 도구**를 만든다.

codemod·생성기·스크립트는 매번 같은 방식으로 일하고 공짜로 다시 돌릴 수 있다. 도구는 검수자가 읽고 다시 돌려 작업을 확인할 수 있는 산출물 하나다. 손으로 한 변경은 다시 해 보는 것 말고는 재검증할 방법이 없다. 결정적(deterministic) 스크립트는 "믿어 주세요"를 "이걸 돌려 보세요"로 바꾼다.

기본값은 지렛대를 만드는 것이다. 한눈에 보이는 뻔한 수정 두어 개처럼 사소할 때만 건너뛴다.

**하네스에 맞춘 실행 방법 (Codex 위임 규칙과 함께):**
- 지렛대(codemod·스크립트·생성기)도 **코드이므로 Codex 가 짠다.** 나(오케스트레이터)는 레시피·대상 파일·검증 기준을 정확히 적어 위임하고, 결과는 `git diff` 와 내가 직접 돌린 실행 결과로 검수한다. "짧은 스크립트라 직접 짠다"는 위반이다.
- 첫 단위 하나를 먼저 처리해 레시피를 익힌다(그 단위의 수정도 Codex 위임). 그다음 지렛대를 만들게 하고, 그 단위에 다시 돌려 앞의 결과와 diff 로 비교해 증명한다. 지렛대는 다시 돌려도 안전하게(멱등) 만든다.
- 수정에는 codemod·스크립트, 반복 파일에는 생성기, 분석에는 sqlite 로 덤프 후 쿼리, 검증에는 다시 돌릴 수 있는 점검.
- 결정적 지렛대가 팬아웃보다 낫다. 도구 한 번에 모든 단위를 처리할 수 있으면 그걸 돌린다. 스크립트가 할 일을 여러 서브에이전트에 손으로 나눠 시키지 않는다. 같은 저장소에서 Codex 를 동시에 여러 개 돌리지 않는다.
- 일을 서브에이전트에 나눠 줄 때는 지렛대를 **그들이 모두 읽는 스킬(.md)** 로 쓴다 — 레시피, 검증 계약, 건드리지 말 범위를 한 문서에. 위임받는 쪽의 쓰기 범위 밖에 두어 계약을 몰래 고치지 못하게 한다. 이 문서는 .md 이므로 내가 직접 쓴다.
- 이 원칙을 적용하면 파일이 생긴다. 이 원칙을 들었는데 diff 에 codemod·스크립트·생성기·위임 스킬이 없다면 적용하지 않은 것이다.
- 작업이 세션보다 오래 남으면 지렛대를 커밋한다(커밋 시점은 하네스 규칙: 검증 통과 후, 지시가 있을 때).

기준은 반복 횟수가 아니라 **사소함**이다. 한 번뿐인 일도 지렛대가 있어야 검증 가능해진다면 지렛대를 만든다. [게으름 규약](laziness-protocol.md)에 따라 일을 하거나 증명하는 가장 작은 스크립트를 만들고, 프레임워크는 만들지 않는다.

[교훈을 구조에 새긴다](encode-lessons-in-structure.md)와 다르다 — 그쪽은 반복되는 지시를 오래가는 가드레일로 만드는 것이고, 이쪽은 눈앞의 작업의 처리량과 검수 가능성이다. 검증 자체를 스크립트로 만드는 것은 [증명한다](prove-it-works.md) 참고.

---

## 영어 원문 (open-pstack `principle-build-the-lever`, 그대로)

원문의 상대 링크(`../principle-*/SKILL.md`)는 이 스킬에서 `references/<원칙이름>.md` 에 해당한다.

````markdown
---
name: principle-build-the-lever
description: "Apply to any non-trivial work, not just bulk work: edits, migrations, analyses, checks. Build the tool that does it or proves it (codemod, script, generator, or a skill your subagents follow) instead of working by hand. The tool is the artifact a reviewer can rerun."
user-invocable: false
---
# Build the Lever

When the work isn't trivial, build the tool that does it instead of doing it by hand.

A codemod, generator, or script does the work the same way every time and reruns for free. The tool is one artifact a reviewer can read and rerun to check the work. Hand-done changes can only be re-verified by redoing them. A deterministic script turns "trust me" into "run this".

Default to building the lever. Skip it only when the task is trivial, a couple of obvious edits you can see at a glance.

- Do the first unit by hand to learn the recipe, then build the tool. Prove it by rerunning it on that unit and diffing against your hand-done version. Make the lever safe to rerun.
- Codemod or script for edits, generator for repetitive files, a dump-to-sqlite query for analysis, a rerunnable check for verification.
- A deterministic lever beats fan-out. If the tool can process every unit in one pass, run it yourself. Don't fan out delegates to hand-apply what a script can do.
- When you fan work out to subagents, write the lever as a skill they all read: the recipe, the verification contract, and the do-not-touch fences in one artifact. Keep it outside the delegates' write scope so they can't quietly edit the contract.
- Applying this principle produces a file. If you cited it and there is no codemod, script, generator, or delegate skill in the diff, you didn't apply it.
- Commit the lever when the work outlives the session.

The bar is triviality, not repetition. A one-off still earns a lever when the lever is what makes the work checkable. Per the [Laziness Protocol](../principle-laziness-protocol/SKILL.md), build the smallest script that does or proves the job, never a framework.

Distinct from [Encode Lessons in Structure](../principle-encode-lessons-in-structure/SKILL.md), which makes a recurring instruction a durable guardrail. This is throughput and reviewability on the work in front of you. For scripting the verification itself, see [Prove It Works](../principle-prove-it-works/SKILL.md).
````
