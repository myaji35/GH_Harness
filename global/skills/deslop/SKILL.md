---
name: deslop
description: |
  브랜치(또는 미커밋) diff 에서 AI 가 만든 코드 군더더기 — 불필요한 주석, 신뢰 경로의 과한 방어 코드·try/catch,
  타입 회피용 any 캐스트, 깊은 중첩, 주변 코드와 안 맞는 스타일 — 를 동작을 바꾸지 않고 걷어낸다. 정리는 Codex 에 위임한다.
  대표님이 "AI 티 나는 코드 정리해", "코드 군더더기 빼", "슬롭 제거", "deslop", "/deslop" 이라고 할 때 사용한다.
  글(문서·보고)의 AI 티는 unslop, 재사용·효율 정리는 simplify.
triggers:
  - deslop
  - AI 티 나는 코드 정리해
  - 코드 군더더기 빼
  - 슬롭 제거
---

# Deslop (AI 코드 군더더기 제거)

> 출처: open-pstack `deslop` (MIT, NOTICE.md — 원저작 cursor-team-kit, 라이선스 함께 보존). GH_Harness 규칙에 맞게 옮김.

`main` 대비 diff(`git diff main...HEAD`, 미커밋이면 `git diff`)를 보고 이 브랜치에서 들어온 AI 군더더기를 걷어낸다.

## 찾을 것

- 불필요하거나 그 파일의 주석 스타일과 안 맞는 주석
- 믿을 수 있는 코드 경로에 비정상적인 방어 검사·try/catch
- 타입 문제를 덮으려고만 쓴 `any` 캐스트(`as any`, `as unknown as X`)
- early return 으로 펴야 할 깊은 중첩
- 그 밖에 파일·주변 코드베이스와 어긋나는 패턴(TS 면 `typescript-best-practices` 기준도 함께)

## 절차 (하네스 규칙)

1. **찾기** (직접) — diff 를 읽고 위 항목을 `파일:줄 — 무엇을 왜` 목록으로 만든다. 동작에 영향이 있을 수 있는 항목(방어 코드 제거 등)은 그 경로가 정말 신뢰 경로인지 호출부를 따라가 확인한다.
2. **정리 — Codex 위임**
   `codex e --skip-git-repo-check -s workspace-write "다음 위치의 군더더기만 제거하라. 동작은 바꾸지 마라: <파일:줄 — 지시> 목록" < /dev/null`
3. **검수** — `git diff` 로 목록 밖 변경·동작 변경·과잉 재작성이 없는지 본다.
4. **직접 검증** — 타입 체크·lint·관련 테스트를 내가 돌린다. 결함은 직접 고치지 않고 구체 지시로 Codex 재위임. 같은 저장소에서 Codex 는 한 번에 하나. 상세: `opus-codes`.

## 가드레일

- 명백한 버그 수정이 아니면 동작을 바꾸지 않는다.
- 넓은 재작성보다 작고 초점 있는 수정.
- 최종 요약은 1~3문장(한국어).

완료 증거는 on_complete result 의 `proof[{cmd,exit_code,output}]` — 예: `npx tsc --noEmit`, `npx eslint <파일>`, 관련 테스트 실행과 실제 출력.
