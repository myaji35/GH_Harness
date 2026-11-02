# 직렬화하기 전에 분리한다 (Separate Before Serializing Shared State)

> 언제: 동시 행위자가 같은 파일·브랜치·키·상태 객체에 쓸 수 있을 때.

동시 행위자가 바뀌는 상태를 공유할 수 있다면 먼저 그들이 정말 같은 객체가 필요한지 묻는다. 아니라면 공유를 없앤다. 공유가 진짜라면 직렬화를 **구조로** 강제한다: 락 파일, 순차 단계, 배타적 소유. 지시와 관례는 동시성 제어가 아니다.

**왜:** 공유 상태에 대한 동시 쓰기는 간헐적이고, 재현하기 어렵고, 디버깅이 비싼 경쟁 조건을 만든다.

**패턴:**
1. **공유되는 가변 상태를 찾는다**(둘 다 읽고 쓰는 파일, 둘 다 push 하는 브랜치, 둘 다 정의하고 소비하는 API).
2. **기본값: 공유 쓰기 대상을 없앤다.** 이 행위자들에게 정본 객체 하나가 필요한가, 아니면 서로 독립된 사실을 발행하는가? 각자 소유한 파일·키·브랜치·상태 디렉터리를 주고, 읽기·보고 경계에서만 합친다. 두 작업자가 하나의 `state.json` 에 각자의 `lastX` 필드를 쓰는 것도 공유 변경이다. `indexer-state.json` + `metrics-state.json` 은 아니다.
3. **공유 쓰기 대상 하나가 진짜 불변식일 때만** 접근을 구조적으로 직렬화한다(락 파일, 순차 단계, 단일 작성자, 원자적 compare-and-swap). "락이 필요해"는 기본 답이 아니라 점검할 설계 냄새로 다룬다.

하네스 연결: 여러 에이전트가 같은 파일을 동시에 고칠 때만 `isolation: worktree`, 같은 저장소 Codex 동시 실행 금지, `registry.json` 은 hook 경유 단일 작성 — 모두 이 원칙의 구조적 강제다.

---

## 영어 원문 (open-pstack `principle-separate-before-serializing-shared-state`, 그대로)

원문의 상대 링크(`../principle-*/SKILL.md`)는 이 스킬에서 `references/<원칙이름>.md` 에 해당한다.

````markdown
---
name: principle-separate-before-serializing-shared-state
description: "Apply when concurrent actors might write to the same file, branch, key, or state object. Eliminate the sharing first; serialize structurally only when one shared writer is a real invariant."
user-invocable: false
---

# Separate Before Serializing Shared State

When concurrent actors might share mutable state, first ask whether they need the same mutable object. If not, eliminate the sharing. When sharing is real, enforce serialization structurally: lockfiles, sequential phases, exclusive ownership. Instructions and conventions are not concurrency control.

**Why:** Concurrent writes to shared state create race conditions that are intermittent, hard to reproduce, and expensive to debug.

**Pattern:**
1. **Identify shared mutable state** (files both read and write, branches both push to, APIs both define and consume).
2. **Default: eliminate the shared write target.** Ask: do these actors need one canonical object, or are they publishing independent facts? Give each actor its own owned file, key, branch, or state directory, and merge only at the read/reporting boundary. Two workers writing their own `lastX` field into one `state.json` is still shared mutation. `indexer-state.json` + `metrics-state.json` is not.
3. **Only when one shared write target is a real invariant, serialize access structurally** (lockfiles, sequential phases, single-writer actor, or atomic compare-and-swap). Treat "we need a lock" as a design smell to check, not as the default answer.
````
