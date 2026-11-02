# 컨텍스트 창을 지킨다 (Guard the Context Window)

> 언제: 컨텍스트가 차오를 때 — 큰 출력, 긴 파일, 같은 파일 반복 읽기, 팬아웃 계획.

**왜:** 컨텍스트가 넘치면 추론 품질이 떨어지고, 압축 과정에서 정보가 뭉개지며, 진행이 멈춘다.

**패턴 (하네스 규칙에 맞춤):**
- **먼저 덜 읽는다.** 하네스의 `progressive-disclosure` 스킬 순서대로 필요한 파일·지식만 단계적으로 읽는다. 이 스킬 자체도 상황에 맞는 원칙 파일 하나만 읽게 만든 것이다.
- **대량 탐색은 서브에이전트로, 본 스레드엔 결론만.** 여러 파일을 훑어야 답이 나올 때만 서브에이전트(Explore 등)에 넘기고 요약만 받는다. 도구 호출 몇 번으로 끝날 일은 직접 한다 — 위임에는 인계 손실과 비용이 있다.
- **코드 작성은 Codex 가 한다.** 컨텍스트를 아끼려고 내가 직접 짜거나, 반대로 Codex 출력 로그 전체를 본 스레드에 붙이지 않는다. 검수는 `git diff --stat` → 필요한 파일의 diff 만 읽고, 판정은 내가 실행한 결과로 한다.
- **단계 크기를 정하고 범위를 묶는다.** 단계당 파일 수를 제한하고, 턴 예산을 정하고, 메커니즘 자체의 비용(서브에이전트 기동, 긴 로그)도 계산에 넣는다.
- 성공 출력은 핵심 수치만, 실패 출력은 전체 상세(하네스 운영 원칙).

> 참고: 원문 본문은 "왜"와 패턴 한 줄뿐이다. 바뀐 문장: 원문 frontmatter 의 "Route bulk to subagents" 를 그대로 기본값으로 두지 않고, progressive-disclosure 우선 + "몇 번의 호출이면 직접" + Codex 위임 규칙에 맞게 고쳤다.

---

## 영어 원문 (open-pstack `principle-guard-the-context-window`, 그대로)

원문의 상대 링크(`../principle-*/SKILL.md`)는 이 스킬에서 `references/<원칙이름>.md` 에 해당한다.

````markdown
---
name: principle-guard-the-context-window
description: "Apply when context is filling up: large outputs, long files, repeated reads, fan-out planning. Route bulk to subagents; keep summaries in the main thread, not raw payloads."
user-invocable: false
---

# Guard the Context Window

**Why:** Context overflow degrades reasoning quality, creates compression artifacts, and halts progress.

**Pattern:**
- **Size phases and cap scope.** Limit files per phase, set turn budgets, account for mechanism costs.
````
