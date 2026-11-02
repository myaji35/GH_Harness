# 근본 원인을 고친다 (Fix Root Causes)

> 언제: 디버깅할 때.

증상이 드러난 곳이 아니라 결함을 고친다. 증상은 잘못된 상태가 눈에 보이게 된 곳이다. 근본 원인은 시스템이 하지 말아야 할 일을 처음 한 곳, 또는 다뤄야 할 상태를 처음 못 다룬 곳이다.

**왜:** 증상 수정은 증거를 감추고 결함이 다른 곳에서 다시 튀어나오게 둔다. 그럴 때마다 시스템은 이해하기 어려워진다. 아무도 이름 붙이지 않은 버그를 위한 우회 코드를 안고 가기 때문이다.

**패턴:**
- 먼저 재현한다.
- 답이 "앞 단계의 결과"가 아니라 "코드의 잘못된 결정"이 될 때까지 단계마다 "왜"를 묻는다.
- 막히면 계측한다. 실제 에러와 실제 상태를 읽는다. 짐작하지 않는다.
- 증상을 일으킨 상태가 **정당한지** 묻는다. 시스템이 그 상태에 있을 수 있다면, 그 상태에서 깨진 코드가 근본 원인이고 거기서 그 상태를 처리하는 것이 수정이다. 그 상태가 절대 존재하면 안 된다면, 깨진 곳에 검사를 넣는 것은 버그를 숨기는 것이다. 그 상태를 만든 곳을 찾는다. 가드, 재시도, 삼킨 에러, 값 고정(clamp), 버린 상태가 버그를 숨기는 흔한 방법이다.
- 재시작 후에만 실패하면 영속 상태부터 의심한다: 설정 파일, 캐시, 락 파일, 직렬화된 상태.
- 하나가 아니라 패턴을 확인한다. 같은 결함이 있는 곳을 모두 찾아 전부 고친다.
- 우회 코드를 정당화하는 데 한 문단짜리 주석이 필요하다면 코드가 틀린 것이다. 주석이 아니라 코드를 고친다.
- 결정적 사실을 찾는 데 깊이 파야 했다면, 처음부터 그걸 보여 줬을 값싼 상시 신호(로그·지표)를 제안한다.

하네스 연결: 수정 자체는 Codex 에 위임한다. 위임 전에 "근본 원인 위치"를 진단해 지시에 넣는 것이 내 몫이다(위임 전 검수). 같은 수정이 두 번 실패하면 T1(hermes-escalate.sh)로 올린다.

---

## 영어 원문 (open-pstack `principle-fix-root-causes`, 그대로)

원문의 상대 링크(`../principle-*/SKILL.md`)는 이 스킬에서 `references/<원칙이름>.md` 에 해당한다.

````markdown
---
name: principle-fix-root-causes
description: "Apply when debugging. Trace each symptom back to the first place the system went wrong and fix it there. A guard is a fix only when the state it handles is legitimate."
user-invocable: false
---

# Fix Root Causes

When debugging, fix the fault, not the place where it surfaced. The symptom is where a wrong state became visible. The root cause is the first place the system did something it should not do, or failed to handle a state it should handle.

**Why:** A symptom fix hides the evidence and leaves the fault free to surface somewhere else. Each one makes the system harder to reason about, because the code now carries a workaround for a bug that nobody named.

**Pattern:**
- Reproduce first.
- Ask "why" at each step until the answer is a wrong decision in the code, not a consequence of an earlier one.
- When stuck, instrument. Read the actual error and the actual state. Do not guess.
- Ask whether the state that triggered the symptom is legitimate. If the system may be in that state, the code that broke on it is the root cause, and handling the state there is the fix. If the state should never exist, a check where it broke hides the bug. Find what produced the state. Guards, retries, swallowed errors, clamped values, and discarded state are the usual ways to hide a bug.
- When something fails only after a restart, suspect persisted state first: config files, caches, lock files, serialized state.
- Check for the pattern, not just the instance. Find every place with the same fault and fix them all.
- If a workaround needs a paragraph-long comment to justify it, the code is wrong. Fix the code, not the comment.
- If the deciding fact took a deep dig to find, propose the cheap, always-on signal that would have shown it at first look.
````
