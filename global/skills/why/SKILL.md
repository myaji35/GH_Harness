---
name: why
description: |
  "왜 이렇게 만들었어?"에 답한다 — 설계 근거, 왜 Y를 골랐나, 회귀 원인, 사후분석, 숫자/임계값의 출처.
  git 이력·이슈 DB(registry.json)·하네스 지식 DB·문서·연결된 MCP를 근거로 확신도를 구분해 인용 답변한다.
  대표님이 "왜 이렇게 했어", "왜 이렇게 돼있어", "이 값은 어디서 나왔어", "언제부터 이랬어", "/why" 라고 할 때 사용한다.
  동작 방식은 how 스킬.
triggers:
  - 왜 이렇게 했어
  - 왜 이렇게 돼있어
  - 이 값은 어디서 나왔어
  - 언제부터 이랬어
---

# Why

> 출처: open-pstack `why` (MIT, NOTICE.md). GH_Harness 규칙에 맞게 옮김.

코드의 동기와 의도를 조사한다. `how` 는 무엇을 어떻게 하는지, `why` 는 **어떤 힘이 지금 모양을 만들었는지** 답한다.

## 자세

신중하고 정확한 조사자로 일한다. 아는 것과 추론한 것을 구분한다. 확신도 체계와 표현은 `references/epistemics.md` 를 따른다(직접 / 뒷받침됨 / 추론 / 추측). 확신도 표현은 다듬지 않는다 — 그 단서 자체가 발견이다.

## 1단계 — 대상과 질문

대상은 보통 코드 덩어리·패턴·기능·결정이고, 질문은 설계 근거·트레이드오프·동기가 된 엣지 케이스·외부 제약·죽은 코드·전체 이력 중 하나다. 대상이 모호하면 대화 맥락(열린 파일·최근 수정·방금 논의)으로 최선의 추정을 하고 해석을 한 줄 밝힌 뒤 진행한다.

## 2단계 — 코드 앵커

조사 전에 직접 시드 맥락을 만든다:
- 파일 경로·줄 범위·핵심 심볼
- `git blame -L <s>,<e> <file>`, `git log --follow --oneline -- <file>`, `git log -S '<정확한 문자열>' -- <file>`
- 커밋 메시지의 **ISS-NNN** → `.claude/issue-db/registry.json` 에서 그 이슈의 title·payload·result 를 꺼낸다(이 하네스의 1차 "왜" 기록).
- PR 번호가 있으면 `gh pr view <n> --json title,body,comments,reviews`

## 3단계 — 근거 범주별 조사

이 환경에서 쓸 수 있는 근거 범주:

| 범주 | 근거 | 강한 질문 |
|---|---|---|
| 소스 이력 | git, `gh`, 코드 주석, 테스트 — `references/sources/code-archaeology.md` | 구현 시점의 근거 |
| 이슈 DB | `.claude/issue-db/registry.json`(title/payload/result), `progress-note` 기록 | 대표님 지시·비즈니스 동기 |
| 하네스 지식 | `.claude/knowledge-db/`(failure/success_patterns), `docs/incident-*.md`, `.claude/context-snapshots/` | 사고·실패에서 나온 방어 코드 |
| 장기 문서 | `docs/`, CLAUDE.md 의 "근거:" 줄, 메모리(`~/.claude/projects/*/memory/`), 연결된 Google Drive/Docs MCP | 사전 설계 근거 |
| 기타 MCP | 세션 도구 목록의 `mcp__*` 중 위에 안 맞는 것(메일 등) | 외부 요청·합의 |

- 대상이 **방어적 코드**(null 체크·재시도·타임아웃·rate limit·feature flag·가드 hook)면 `references/sources/incident-postmortem.md` 관점을 더한다. 이 하네스의 가드(secret-guard 등)는 CLAUDE.md·스크립트 헤더에 "근거: <사고>"가 적혀 있는 경우가 많다.
- **기본은 좁게.** 소스 이력 + 이슈 DB 는 항상, 나머지는 질문에 맞는 것만. 조사하지 않은 범주는 Sources Consulted 에 이유와 함께 적는다("Slack 없음 — 대화 기록 검색 불가").
- 위임: 범주가 3개 이상이고 각각 무거우면 범주당 서브에이전트 1개(`references/investigator-prompt.md`), 동시 3개 상한. MCP 를 써야 하는 범주는 MCP 접근이 유지되는 `general-purpose` 로. 그 외에는 직접 조사한다. 조사자는 파일을 쓰지 않는다.

## 4단계 — 종합

`references/synthesizer-prompt.md` 형식으로 직접 종합한다(서브에이전트를 띄웠다면 그 결과 + 코드 앵커 + 원 질문 + epistemics). 인용은 표본으로 직접 다시 확인한다.

## 5단계 — 제시 (한국어)

절: 질문 / 해당 코드 / 찾은 것(직접) / 합리적 추론 / 경쟁 가설 / 모르는 것 / 조사한 출처(범주당 1줄, 빈 결과·건너뜀 포함) / 확신도 요약.

이 "왜" 질문이 코드를 바꾸기 위한 사전 조사라면, 마지막에 **유지 / 변경 / 피할 것 / 위험** 제약 목록으로 바꿔 준다.

## 흔한 실패

- **최신 편향**: 가장 최근 커밋이 정답이라 가정. 지금 모양은 여러 이전 결정의 누적인 경우가 많다. 거슬러 올라간다.
- 근거 없는 확신: 코드가 X 를 하니 작성자가 X 를 원했다 — 이건 추론이지 직접 근거가 아니다.
