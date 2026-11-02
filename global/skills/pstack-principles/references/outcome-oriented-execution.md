# 결과 중심으로 실행한다 (Outcome-Oriented Execution)

> 언제: 단계 경계가 명시된 계획된 재작성·마이그레이션 중.

매끄러운 중간 상태를 지키기보다 **의도한, 검증 가능한 최종 상태**에 최적화한다.

**왜:** 모든 중간 단계를 완전히 안정되게 유지하려다 보면 임시 호환 코드가 생기고, 그것이 오래가는 빚이 된다. 목표 아키텍처로 수렴하고, 명시적 검증 경계에서 정확성을 증명한다.

**핵심 규칙:**
- 전환기 안정성보다 최종 상태의 완결성을 우선한다.
- 중간 깨짐은 계획되고, 범위가 정해지고, 되돌릴 수 있을 때 허용된다.

**가드레일:**
- 단계 경계가 명시된 계획된 재작성·마이그레이션에만 쓴다.
- 일시적 깨짐이 허용되는 곳을 선언한다.
- 마이그레이션 중에도 직접 손대는 영역의 신호 강한 검사는 유지한다.
- 계획 완료 시점에 정적·런타임 검증을 전부 요구한다.

하네스 연결: 운영 중인 서비스의 깨짐이 외부에 보이면(프로덕션 배포·DB 변경) T2 EXTERNAL 이다.

---

## 영어 원문 (open-pstack `principle-outcome-oriented-execution`, 그대로)

원문의 상대 링크(`../principle-*/SKILL.md`)는 이 스킬에서 `references/<원칙이름>.md` 에 해당한다.

````markdown
---
name: principle-outcome-oriented-execution
description: "Apply during planned rewrites and migrations with explicit phase boundaries. Converge on the target architecture; don't preserve smooth intermediate states with throwaway compatibility code."
user-invocable: false
---

# Outcome-Oriented Execution

Optimize for the intended, verifiable end state rather than preserving smooth intermediate states.

**Why:** Keeping every intermediate step fully stable often creates temporary compatibility code that becomes long-lived debt. Converge on the target architecture and prove correctness at explicit verification boundaries.

**Core rule:**
- Prioritize end-state integrity over transitional stability
- Intermediate breakage is acceptable when it is planned, scoped, and reversible

**Guardrails:**
- Use this for planned rewrites and migrations with explicit phase boundaries
- Declare where temporary breakage is acceptable
- Keep high-signal checks for actively touched areas while migrating
- Require full static and runtime verification at plan completion
````
