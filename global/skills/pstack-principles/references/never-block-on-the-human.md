# 사람을 기다리며 멈추지 않는다 (Never Block on the Human)

> 언제: 되돌릴 수 있는 작업에서 "X를 할까요?"라고 묻고 싶을 때.

대표님은 비동기로 감독한다. 에이전트는 막히지 않아야 한다. 합리적으로 판단하고, 진행하고, 대표님이 사후에 방향을 고치게 한다. 코드 변경은 되돌릴 수 있고 검토할 수 있으므로, 틀린 결정이 대개 멈춰 기다리는 것보다 싸다.

- 진행하고 나서 보여 준다. 일을 하고 결과를 보인다. "X를 할까요?"가 아니라 X를 하고 이유를 설명한다.
- 시스템을 스스로 낫게 한다. 문제를 발견하면 기록하고 다음 라운드에 고친다.
- 되돌릴 수 없는 행동(force-push, 운영 데이터 삭제, 외부로 메시지 보내기)은 여전히 확인이 필요하다.
- 되돌릴 수 있는 행동(코드 작성, 노트 편집, 작업 쪼개기)은 멈추지 않고 진행한다.
- 제품 방향은 대표님에게서 온다. 실행은 멈추지 않는다.

## 하네스 연결
- 하네스 **자율 실행 원칙**(T0 침묵 자동 / T1 내부 자문 / T2 대표님 확인)과 같은 방향이다. 금지 문장 패턴("진행할까요?", "어떻게 할까요?" 등)이 이 원칙의 하네스판이다.
- 막혔을 때는 대표님께 묻지 말고 T1 — `hermes-escalate.sh` 로 내부 자문을 받는다.
- **예외: T2 5개 카테고리는 반드시 멈추고 확인한다** — EXTERNAL(프로덕션 배포·외부 키·DB DROP/ALTER·유료 API·force push·외부 리소스 생성), DIRECTION(아키텍처 패러다임·기술 스택 교체·핵심 기능 삭제·브랜드 DNA), BUDGET(Opus Hard Cap·월 한도·유료 플랜), SECURITY(인증·권한·개인정보·라이선스·크롤링 확장), EXPLICIT(`requires_user_confirm` 또는 `[CONFIRM]`). 이때는 `request-user-confirm.sh` 를 쓰고 그 이슈만 멈춘다. 원문의 "되돌릴 수 없는 행동"은 이 T2 에 해당한다.
- 착수 근거는 대표님 발화뿐이다. 이 원칙은 "지시받은 일을 되묻지 말라"이지 "지시 없이 시작하라"가 아니다.

---

## 영어 원문 (open-pstack `principle-never-block-on-the-human`, 그대로)

원문의 상대 링크(`../principle-*/SKILL.md`)는 이 스킬에서 `references/<원칙이름>.md` 에 해당한다.

````markdown
---
name: principle-never-block-on-the-human
description: "Apply when tempted to ask 'should I do X?' on reversible work."
user-invocable: false
---

# Never Block on the Human

The human supervises asynchronously. Agents must stay unblocked. Make reasonable decisions, proceed, and let the human course-correct after the fact. Since code changes are reversible and reviewable, a wrong decision usually costs less than blocking.

- Proceed, then present. Do the work, show the result. Don't ask "should I do X?" Do X, explain why.
- Make the system self-healing. When you notice a problem, log it and fix it in the next round.
- Irreversible actions (force-push, delete production data, send external messages) still require confirmation.
- Reversible actions (write code, edit notes, split tasks) should proceed without blocking.
- Product direction comes from the human. Execution should not block.
````
