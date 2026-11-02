# 연산을 멱등하게 만든다 (Make Operations Idempotent)

> 언제: 충돌·재시작·재시도가 일상인 환경에서 돌 명령, 생명주기 단계, 처리 루프를 설계할 때.

몇 번 돌든, 이전 실행이 어디서 멈췄든 올바른 상태로 수렴하게 설계한다. 상태를 바꾸는 모든 연산은 이 질문에 답해야 한다: "이게 두 번 돌면? 이전 실행이 중간에 죽었으면?"

**왜:** 명령, 생명주기 작업, 처리 루프는 충돌·재시작·재시도가 정상인 곳에서 돈다. 남겨진 부분 상태가 다음 실행 결과를 바꾼다면 재시작할 때마다 디버깅이 된다.

**핵심 생각:** 각 단계를 이전 실행이 *하려던 것*이 아니라 *지금 있는 상태*에서 도출한다. 현재 상태를 읽고, 목표와 비교하고, 차이만 적용한다. 이렇게 쓴 단계는 반복해도 안전하다 — 반복하면 할 일이 남아 있지 않기 때문이다.

실행이 남기는 것(락, 임시 파일, 반쯤 쓴 레코드, 점유한 작업)은 다음 실행이 **낡았다고 알아볼 수 있어야** 한다. 낡음은 흔한 경우만이 아니라 이전 실행이 멈췄을 수 있는 모든 지점에서 참인 증거로 판단한다. 다음 실행이 판단할 수 없는 표식은 충돌이 날 때마다 수작업 정리를 만든다. 예: 임시 경로에 쓴 뒤 rename 으로 제자리에 놓기, 생성 순서가 아니라 내용으로 산출물 비교하기.

**판별 질문:**
1. 연달아 두 번 돌면 어떻게 되나?
2. 이전 실행이 가능한 모든 지점에서 죽었다면?
3. 다시 실행하면 같은 최종 상태로 수렴하나?

하나라도 "남은 상태에 따라 다르다"면 그 연산에는 조정(reconciliation) 단계가 필요하다.

하네스 연결: hook·디스패치(dispatch-ready, background-track claim/release, registry 갱신)가 대표적 적용 대상이다.

---

## 영어 원문 (open-pstack `principle-make-operations-idempotent`, 그대로)

원문의 상대 링크(`../principle-*/SKILL.md`)는 이 스킬에서 `references/<원칙이름>.md` 에 해당한다.

````markdown
---
name: principle-make-operations-idempotent
description: "Apply when designing commands, lifecycle steps, or processing loops that run amid crashes, restarts, and retries. Converge to the same end state regardless of partial prior runs."
user-invocable: false
---

# Make Operations Idempotent

Design operations so they converge to the correct state regardless of how many times they run or where the previous run stopped. Every state-mutating operation should answer: "What happens if this runs twice? What happens if the previous run crashed halfway?"

**Why:** Commands, lifecycle operations, and processing loops run where crashes, restarts, and retries are normal. If partial state changes the next run's outcome, every restart becomes a debugging session.

**The idea:** derive each step from the state that exists, not from what the previous run meant to do. Read the current state, compare it to the goal, and apply only the difference. A step written this way is safe to repeat, because a repeat finds nothing left to do.

Anything a run leaves behind, such as a lock, a temporary file, a half-written record, or a claimed job, must be recognizable as stale by the next run. Judge staleness by evidence that stays true wherever the previous run could have stopped, not only in the common case. A marker that the next run cannot judge turns every crash into manual cleanup. For example, write to a temporary path and rename it into place, or compare artifacts by content instead of by creation order.

**The test:**
1. What happens if this runs twice in a row?
2. What happens if the previous run crashed at every possible point?
3. Does re-execution converge to the same end state?

If any answer is "it depends on what state was left behind," the operation needs a reconciliation step.
````
