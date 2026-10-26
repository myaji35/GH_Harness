---
name: harness-modes
description: plan-harness·check-harness 가 이슈를 처리할 때 불러 쓰는 모드 지침 모음(기획·CEO/엔지니어링 검토·기회·도메인·고객 언어·구현·배포 / 코드 품질·테스트·평가·비즈·여정·시나리오·디자인·브랜드·UX·교차검증·메타). 하네스 이슈의 plan_mode/check_mode 를 처리하거나 "~모드로 검토해" 같은 요청이 올 때 해당 모드 파일 하나만 읽는다.
---

# Harness Modes — 접힌 세부 에이전트의 지침

2026-10-26 GH_Harness 는 세부 에이전트 20개를 **별도 서브에이전트에서 모드 파일로 접었다**
(근거: Anthropic, "Building agents: When to fold subagents into your main agent loop", 2026-10-22 —
역할별 에이전트를 조직도처럼 나누면 넘길 때마다 정보가 빠지고, 도구·에이전트 목록이 길수록 선택이 흐려진다).

- 남은 에이전트: `plan-harness`(만드는 쪽), `check-harness`(검증 쪽), `hermes`·`advisor`(자문), `review-triage`.
- 세부 역할은 아래 모드 파일이다. **처리 중인 모드의 파일 하나만** 읽는다(점진적 로딩).
- `dispatch-ready.sh` 는 옛 `assign_to`(예: `code-quality`)가 와도 `check-harness` + `check_mode=code` 로 바꿔 스폰한다.
  되돌리려면 `HARNESS_AXIS_MODE=legacy`.

## PLAN 축 (`payload.plan_mode`)
| 모드 | 파일 | 권장 모델 |
|---|---|---|
| product | `modes/product-manager.md` | opus |
| ceo-review | `modes/plan-ceo-reviewer.md` | fable |
| eng-review | `modes/plan-eng-reviewer.md` | opus |
| opportunity | `modes/opportunity-scout.md` | opus |
| domain | `modes/domain-analyst.md` | opus |
| audience | `modes/audience-researcher.md` | sonnet |
| ux-design | `modes/ux-harness.md` | sonnet |
| code | `modes/agent-harness.md` | sonnet |
| deploy | `modes/cicd-harness.md` | sonnet |

## CHECK 축 (`payload.check_mode`)
| 모드 | 파일 | 권장 모델 |
|---|---|---|
| code | `modes/code-quality.md` | sonnet |
| test | `modes/test-harness.md` | sonnet |
| eval | `modes/eval-harness.md` | sonnet |
| biz | `modes/biz-validator.md` | sonnet |
| journey | `modes/journey-validator.md` | sonnet |
| scenario | `modes/scenario-player.md` | sonnet |
| design | `modes/design-critic.md` | opus |
| brand | `modes/brand-guardian.md` | opus |
| ux-review | `modes/ux-harness.md` (UI_REVIEW 절) | sonnet |
| qa | `modes/qa-reviewer.md` | sonnet |
| meta | `modes/meta-agent.md` | sonnet |
| (라우팅) | `modes/hook-router.md` — 참고용. 라우팅은 `axis-router.sh` 가 결정적으로 한다 | — |

모드 파일 맨 위의 frontmatter(name·model 등)는 옛 에이전트 정의의 흔적이다. 지침 본문만 따른다.
