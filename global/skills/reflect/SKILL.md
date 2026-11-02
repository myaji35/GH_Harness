---
name: reflect
description: |
  지금 대화(세션 기록)를 읽기 전용 검토자 3명(판단·도구·반대 관점)이 병렬로 훑어 오래 쓸 교훈을 뽑고,
  종합자가 걸러 낸 교훈을 메모리 파일·CLAUDE.md·기존 스킬 수정으로 남긴다. 대표님이 "회고해", "이번 세션 돌아봐",
  "배운 거 정리해서 남겨", "다음엔 안 틀리게 반영해", "reflect", "/reflect" 라고 할 때 사용한다.
  이슈 데이터 기반 자동 개선은 meta-evolution, 확정 결정을 CLAUDE.md 에 넣는 건 update-claudemd.
triggers:
  - reflect
  - 회고해
  - 이번 세션 돌아봐
  - 배운 거 정리해서 남겨
  - 다음엔 안 틀리게 반영해
---

# Reflect (세션 회고 → 교훈을 장치로 남기기)

> 출처: open-pstack `reflect` (MIT, NOTICE.md). GH_Harness 규칙에 맞게 옮김.

지금 대화에서 오래 쓸 교훈을 캐내고, 그걸 실제 파일 수정으로 보낸다. 대화가 사소하거나 주제와 무관하거나, 이미 있는 스킬을 제대로 따른 경우면 쓰지 않는다. 한 번뿐인 일은 교훈이 아니다.

## 비슷한 스킬과의 구분

| 스킬 | 입력 | 산출 | 언제 |
|---|---|---|---|
| **reflect** | **이번 대화 기록**(무엇을 틀렸고 대표님이 무엇을 교정했나) | 메모리 파일·CLAUDE.md·기존 스킬 수정, 백로그 이슈 | 대표님이 회고를 요청할 때 |
| `meta-evolution` | registry 의 완료·실패 **이슈 데이터**(반복 실패·점수 하락·병목) | 개선 이슈(REFACTOR 등) 자동 생성 | 주기 실행, on_fail 3회, on_learn |
| `update-claudemd` | 대화에서 **확정된 결정**·구조 변경 | CLAUDE.md 해당 섹션 반영 + docs 커밋 | "CLAUDE.md 업데이트하자" |

reflect 가 CLAUDE.md 로 보낼 항목은 `update-claudemd` 의 중복 확인·섹션 배치 절차를 그대로 따른다. 이슈 데이터 패턴이 보이면 meta-evolution 소관이므로 직접 개선 이슈를 만들지 않고 백로그로 넘긴다.

## 1. 대화 기록 찾기

Claude Code 세션 기록은 `~/.claude/projects/<작업 디렉터리 경로를 - 로 바꾼 이름>/<session-id>.jsonl` 이다. 가장 최근 수정된 파일이 지금 세션인지 첫 사용자 발화로 확인한다. 찾지 못하거나 너무 크면 대화 요약(교정 받은 순간·막힌 곳·쓴 스킬과 도구)을 직접 짧게 만들어 넘긴다. 세션 기록·요약에 시크릿이 있으면 가린다.

## 2. 검토자 3명 병렬

읽기 전용 검토자 3명을 한 응답에서 동시에 띄운다(`Agent`, `general-purpose`, 부모 모델, 동시 3개 상한). 프롬프트가 파일 쓰기를 금지한다 — 수정은 부모(나)가 한다. 검토자가 기록에 나온 이슈·문서를 찾아봐야 하므로 부모의 도구(MCP 포함)를 그대로 쓰게 둔다.

| 관점 | 프롬프트 |
|---|---|
| 판단(Judgment) | `references/judgment-reviewer.md` |
| 도구(Tooling) | `references/tooling-reviewer.md` |
| 반대(Divergent) | `references/divergent-reviewer.md` |

템플릿을 그대로 넘기고 표시된 곳에 기록 경로 또는 요약을 넣는다. 결과는 Agent 응답 본문으로 받는다.

## 3. 종합

종합자 1명을 띄워(`Agent`, 부모 모델) `references/synthesizer.md` 를 그대로 주고 검토자 세 명의 결과 전문을 표시된 곳에 넣는다. 종합자는 Accepted / Rejected / Backlog 목록을 돌려준다.

references 원문의 용어는 하네스에서 이렇게 읽는다:
- `plugin-dev:skill-development` → `anthropic-skills:skill-creator` 스킬.
- "devex or backlog tracker" → 하네스 이슈 저장소(`issue-registry` 스킬, `.claude/issue-db/registry.json`).
- 스킬 경로 → `GH_Harness/global/skills/<이름>/SKILL.md`(전역) 또는 프로젝트 `.claude/skills/<이름>/SKILL.md`.

## 4. 구조로 강제할 수 있는지

lint 규칙·hook·스크립트·테스트·메타데이터 플래그·런타임 검사로 더 확실히 강제할 수 있는 Accepted 항목은 Backlog 로 옮긴다(encode-lessons-in-structure). 문장은 장치가 강제할 수 없는 것만 맡는다. 장치 구현은 코드이므로 Codex 위임 이슈가 된다.

## 5. 반영 — 배운 것은 파일로 남긴다

Accepted 항목은 성격에 따라 아래 셋 중 한 곳에 남긴다.

| 남길 곳 | 무엇 | 반영 방식 |
|---|---|---|
| **메모리 파일** (`~/.claude/projects/<프로젝트>/memory/*.md` + `MEMORY.md` 색인) | 대표님 선호·교정·사실(계정 위치·경로·용어 뜻) | **바로 쓴다**(전역 규칙: 배우면 그 자리에서 저장. 세션 종료 시 `memory-sync.py` 가 볼트로 복사). 시크릿 값은 쓰지 않고 위치만 |
| **CLAUDE.md** (프로젝트 또는 전역) | 작업 방식 규칙·금지·운영 함정 | `update-claudemd` 절차(중복 grep → 맞는 섹션 → 날짜·근거) |
| **스킬 수정** (기존 SKILL.md) | 스킬 절차의 빈틈·잘못된 사실·안 불린 트리거 | 한 줄급은 직접 수정. 새 절·10줄 넘는 수정·설명(트리거) 조정·새 스킬은 `anthropic-skills:skill-creator` |

**승인 정책.** 메모리 파일과 프로젝트 스킬의 한 줄급 수정은 되돌릴 수 있으므로 묻지 않고 반영한 뒤 보고한다. **전역 CLAUDE.md·GH_Harness 전역 스킬 수정**은 모든 프로젝트의 이후 에이전트 행동을 바꾸므로 Accepted 목록 전체를 먼저 보여 주고 대표님이 고른 것만 반영한다(대표님이 경로를 바꿀 수 있다). Backlog 는 기다리지 않고 바로 이슈로 등록한다.

수정한 스킬마다 frontmatter(`name`, `description`, `triggers`)가 깨지지 않았는지 확인한다. 문서(.md)·메모리 수정은 직접 하고, hook·스크립트 같은 코드 변경은 Codex 위임 이슈로 넘긴다.

## 6. 보고 (한국어, 서두 없이)

- 반영한 수정: `<경로>` — 무엇이 바뀌었는지 한 줄씩.
- 새로 만든 스킬: `<경로>` — 한 줄씩(드묾).
- 승인 대기(전역): 항목 한 줄씩.
- 백로그 이슈: `ISS-NNN <제목>` — 한 줄씩.
- 버린 것: 종합자가 기각한 항목 + 이유 한 줄씩.

반영한 파일 목록은 on_complete result 의 `proof` 에 `git diff --stat` 등 실행 출력으로 남긴다.
