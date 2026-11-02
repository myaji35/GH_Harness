---
name: babysit
description: |
  열린 PR 하나를 지켜보며 실패한 CI 를 고치고, 단순한 리뷰 코멘트를 처리하고, 충돌을 풀어 머지 가능한 상태까지 끌고 간다.
  대표님이 다시 지시하지 않아도 PR 을 돌보게 할 때 쓴다. 수정은 Codex 에 위임하고 내가 검수·검증한다.
  대표님이 "PR 봐 줘", "PR 지켜보다가 초록불 만들어", "리뷰 코멘트 처리해", "머지 가능하게 만들어", "babysit", "/babysit" 라고 할 때 사용한다.
triggers:
  - babysit
  - PR 봐 줘
  - PR 지켜봐
  - 리뷰 코멘트 처리해
  - 머지 가능하게 만들어
---

# Babysit (PR 돌보기)

> 출처: open-pstack `babysit` (MIT, NOTICE.md — open-pstack 포트에서 독자 작성한 스킬). GH_Harness 규칙에 맞게 옮김.

`gh` CLI 를 반복 호출하고, 간격 조절은 Claude Code `loop` 스킬(또는 `Monitor` 로 조건 대기)로 한다. 원본의 poteto-mode Babysit 플레이북·`watch-pr` 감시 스크립트는 하네스에 없으므로 이 스킬이 단독 진입점이다.

## 언제

- 열린 PR 이 있고 대표님이 그걸 초록불로 유지하라고 명시했을 때, 또는 `/babysit` 을 직접 불렀을 때.
- PR 을 연 **서브에이전트는 babysit 하지 않는다** — 부모로 돌아가 부모가 정한다.
- PR 없이 main 에 직접 커밋하는 흐름의 CI 실패는 `fix-ci` 를 쓴다.

## 절차

1. **PR 상태 가져오기**

   ```bash
   gh pr view <번호> --json number,title,state,mergeable,reviewDecision,statusCheckRollup,mergeStateStatus,comments,reviews
   ```

2. **우선순위대로 분류**
   - **머지 충돌**(`mergeStateStatus == DIRTY`): `main` 을 merge 하거나 rebase 해서 푼다. 충돌 해결이 코드 판단을 요구하면 해결 지시를 Codex 에 위임한다. **force push 는 T2** — 내 브랜치이고 공유되지 않았어도 대표님 확인을 받는다(`request-user-confirm.sh <ISS> EXTERNAL`). 가능하면 rebase 대신 merge 커밋으로 force push 자체를 피한다.
   - **실패한 체크**(`statusCheckRollup` 의 `conclusion: FAILURE`): `gh run view <run-id> --log-failed` 로 로그를 받아 근본 원인을 진단하고, 수정은 아래 "수정 위임" 절차로 한다.
   - **사람 리뷰어 코멘트**: 내가 실제로 동의하는 피드백만 반영한다. 답이 기계적으로 하나인 것(이름 바꾸기, guard 절, 포맷 지적)은 수정하고 커밋 메시지에 코멘트를 인용한다. 판단이 갈리거나 무엇을 요구하는지 모르겠으면 추측하지 않는다 — 고치지 말고 "나라면 이렇게 하겠다"를 답글로 남긴다.
   - **리뷰 봇 코멘트**(Bugbot 등 자동화): 고침 / 기각 / 확인 필요로 분류한 뒤 움직인다. **보안·데이터·고심각도 지적은 기본이 '확인 필요'** — 근거를 붙여 대표님께 보고한다(보안이면 T2 SECURITY).

3. **수정 위임** (코드가 바뀌는 모든 경우)
   `codex e --skip-git-repo-check -s workspace-write "<정확한 파일 경로 + 실패 원문/코멘트 인용 + 구체 변경 지시>" < /dev/null`
   → `git diff` 검수(정확성·범위·회귀·규칙 위반·과잉 변경) → 실패한 명령을 내가 로컬에서 다시 실행 → 결함은 직접 고치지 않고 구체 지시로 재위임 → 검증되면 커밋 후 push(커밋 후 push 는 자동 후속 작업). 같은 저장소에서 Codex 는 한 번에 하나. 상세: `opus-codes`.

4. **반복** — 무엇을 기다리느냐로 간격을 정한다.
   - CI 실행 중: `gh pr checks <번호> --watch` (끝날 때까지 막고 기다리므로 별도 간격 불필요. 60초 넘으면 `run_in_background` 로 돌리고 끝나면 알림을 받는다).
   - 리뷰어 대기: `loop` 스킬로 20~30분 간격.
   - 할 일 없이 새 코멘트만 기다림: 1시간 간격.

5. **멈출 때**
   - 빌드 초록, 코멘트 전부 해결, 깨끗하게 머지 가능 → 준비 완료로 보고.
   - 고침 → push → 재확인을 세 바퀴 돌았는데도 완전히 초록이 아니면 멈추고, 남은 문제를 요약해 넘긴다(`hermes-escalate.sh` REPEAT_FAIL).
   - 다음 수정이 설계 선택을 강요하면: 동급 선택지·이름·기본값 수준이면 T0 로 최선을 골라 실행하고 한 줄 기록. 아키텍처 방향 전환·핵심 기능 삭제급이면 T2 DIRECTION.

6. **보고** (한국어) — 반영한 수정, 처리한 코멘트, 미룬 코멘트(이유), 현재 PR 상태. 커밋마다 SHA 를 단다.

## 절대 규칙

- 다른 사람이 받아 갔을 수 있는 브랜치의 이력을 다시 쓰지 않는다. rebase·force push 는 T2.
- 통과시키려고 테스트 기대값을 바꾸지 않는다. 동작이 진짜 바뀌었고 단언이 옛 동작에 묶여 있을 때만 바꾼다.
- hook 을 건너뛰지 않는다(`--no-verify` 금지).
- 실패한 체크를 필수에서 빼서 우회하지 않는다.
- `gh pr ready` 는 모든 체크가 초록이고 미해결 리뷰 코멘트가 없을 때만.
- **머지**는 대표님이 머지까지 지시했을 때만 한다. 머지가 프로덕션 배포를 일으키는 저장소면 T2 EXTERNAL.

## 완료 증거

on_complete result 의 `proof[{cmd,exit_code,output}]` 에 로컬 재현 명령과 최종 `gh pr checks <번호>` / `gh pr view <번호> --json mergeStateStatus,reviewDecision` 출력을 넣는다.

## 함께 쓰는 스킬

- PR 을 열기 전 diff 에 이견이 많으면(대표님 요청 시) `interrogate`. 열린 뒤에는 babysit 이 맡는다.
- PR 코멘트·커밋 메시지·상태 보고 같은 글에는 `unslop`.
