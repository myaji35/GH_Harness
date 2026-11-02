---
name: fix-ci
description: |
  실패한 CI(PR 체크 또는 브랜치의 GitHub Actions 실행)를 찾아 로그·외부 체크 링크에서 첫 번째 원인을 뽑고,
  작은 수정을 하나씩 반영해 초록불이 될 때까지 반복한다. 수정은 Codex 에 위임하고 내가 검수·검증한다.
  대표님이 "CI 고쳐", "CI 깨졌어", "빌드 빨간불", "액션 실패", "체크 통과시켜", "fix ci", "/fix-ci" 라고 할 때 사용한다.
triggers:
  - fix ci
  - CI 고쳐
  - CI 깨졌어
  - 빌드 빨간불
  - 액션 실패
---

# Fix CI

> 출처: open-pstack `fix-ci` (MIT, NOTICE.md — 원저작 cursor-team-kit, 라이선스 함께 보존). GH_Harness 규칙에 맞게 옮김.

## 언제

브랜치나 PR 의 CI 가 실패해서, 빠르게 반복하며 초록불로 만들어야 할 때.

## 절차

1. **실패 찾기** (직접)
   - PR 이 있으면: `gh pr checks --json name,bucket,state,workflow,link`
   - PR 없이 main 에 직접 커밋하는 흐름이면: `gh run list --branch <브랜치> --limit 5 --json databaseId,status,conclusion,workflowName,headSha`
2. **첫 번째 원인 뽑기** (직접) — 실패한 잡에서 처음으로 손댈 수 있는 에러를 뽑는다. GitHub Actions 면 `gh run view <run-id> --log-failed`, 아니면 체크 링크에서 실패한 명령·서비스를 찾는다. 가능하면 같은 명령을 로컬에서 재현한다.
3. **가장 작고 안전한 수정 — Codex 위임**
   `codex e --skip-git-repo-check -s workspace-write "<정확한 파일 경로>에서 <CI 에러 원문 한 줄>의 원인 <진단>을 고쳐라. 다른 실패는 건드리지 마라." < /dev/null`
   → `git diff` 검수(정확성·범위·회귀·규칙 위반·과잉 변경) → 실패한 명령을 **내가 로컬에서 다시 실행**해 통과 확인 → 결함은 직접 고치지 않고 구체 지시로 재위임. 같은 저장소에서 Codex 는 한 번에 하나. 상세: `opus-codes`.
4. **커밋 → push → 재확인** — 검증이 끝나면 커밋하고 push 한다(프로젝트 규칙상 커밋 후 push 는 자동 후속 작업). 다시 `gh pr checks`(또는 `gh run watch <run-id>`)로 전체 상태를 보고, 초록불까지 1~4 를 반복한다.

## 가드레일

- 한 번에 손댈 수 있는 실패 하나만 고친다.
- 큰 리팩토링보다 작고 위험 낮은 변경을 먼저.
- 전체 CI 상태의 기준은 `gh pr checks`(PR 없으면 `gh run list`)다. 로컬 통과만으로 끝내지 않는다.
- 테스트 기대값을 통과시키려고 바꾸지 않는다. 체크를 필수에서 빼거나 `--no-verify` 로 hook 을 건너뛰지 않는다.
- **T2(대표님 확인)**: force push, 프로덕션 배포가 걸린 워크플로 재실행·변경, 외부 시크릿·키 추가가 필요한 실패. `request-user-confirm.sh <ISS> EXTERNAL|SECURITY "<질문>"` 로 그 건만 멈추고 나머지는 계속한다.
- 같은 실패가 세 번 고쳐도 남으면 멈추고 `hermes-escalate.sh` (REPEAT_FAIL)로 넘긴다.

## 완료 증거 · 보고 (한국어)

on_complete result 의 `proof[{cmd,exit_code,output}]` 에 로컬 재현 명령과 최종 CI 상태 조회를 넣는다:

```json
{"proof":[
  {"cmd":"npm run build","exit_code":0,"output":"Compiled successfully"},
  {"cmd":"gh pr checks --json name,state","exit_code":0,"output":"[{\"name\":\"build\",\"state\":\"SUCCESS\"}, ...]"}
]}
```

보고: 주된 실패 잡과 근본 에러 / 반영한 수정(순서대로, 커밋 SHA) / 현재 CI 상태와 다음 행동.
