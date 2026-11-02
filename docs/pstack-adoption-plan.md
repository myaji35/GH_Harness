# pstack 확대 도입 계획 (ISS-345, 2026-11-03)

원본: open-pstack (https://github.com/ericlitman/open-pstack, b4c5e3d 2026-10-22, MIT). Lauren Tan pstack 포트.

## 지금까지 (2026-10-18 ~ 11-02)
- 원칙 `prove-it-works` 1개를 on_complete 게이트로 강제(c032151).
- 스킬 6개 이식(0b6a18d): create-verification-skill, maintain-verification-skill, interrogate, how, why, teach.
- 2주 측정(proof-metrics.jsonl, 11개 프로젝트): 판정 555건 중 거부 31건 ≈ **5.6%**. 기준(거부율 < 20%) 통과 → 유지 + 다음 원칙 도입 조건 충족.

## 대표님 지시 (2026-11-03)
"pstack(개발스킬)을 적극적으로 도입하고 싶어." → 하나씩 넣던 방식을 바꿔 한 번에 넓게 넣는다. 단, 효과 측정 장치는 유지한다.

## 도입 방식
플러그인을 통째로 설치하지 않고 하네스 스킬로 옮긴다. 이유:
1. `poteto-mode`·`setup-pstack`·모델 레지스트리는 하네스의 오케스트레이터·모델 티어·Codex 위임 규칙과 역할이 겹친다. 같이 두면 어느 규칙을 따를지 충돌한다.
2. 스킬 63개 설명이 매 턴 컨텍스트에 실린다(하네스 토큰 최적화 방침과 충돌).
3. 한국어 보고·대표님 호칭·T0/T2 컨펌·proof 형식 같은 하네스 규칙에 맞게 고쳐야 실제로 쓰인다.

## 1차 (이번) — 스킬 이식
| 묶음 | 스킬 | 하네스와의 관계 |
|---|---|---|
| A 일 이어받기·보고 | ketchup, recall, what-did-i-get-done, show-me-your-work | recall 은 세컨드브레인 `scripts/brain/recall.py` 와 합친다. show-me-your-work 는 decision-trace 와 연결 |
| A 변경 안전 | blast-radius, correct, sharpen, benchmark-checklist | correct = encode-lessons-in-structure 실행판. meta-agent 와 연결 |
| B 큰 작업 | figure-it-out, architect, swarm, arena | arena 는 RACE_MODE 와, swarm 은 Workflow 와 역할 구분 명시 |
| B 코드 | tdd, fix-ci, babysit, deslop, unslop, typescript-best-practices, reflect | 코드 수정은 Codex 위임 규칙을 따른다 |
| C 원칙 | `pstack-principles` 한 스킬로 묶음(원칙 21개 → references/) | attack-the-premise 는 제외(2026-10-18 결정: 사용자 명시값 우선과 충돌) |

## 넣지 않는 것
- poteto-mode, poteto-help, setup-pstack, automate-me — 하네스 오케스트레이터·update-claudemd 와 중복.
- get-pr-comments, make-pr-easy-to-review, fix-merge-conflicts — 대부분 main 직접 커밋이라 PR 흐름이 적다. 필요해지면 2차.
- create/maintain-formal-verification-skill, thermo-nuclear-code-quality-review, no-comments — 비용 대비 쓰임이 적다. 2차 후보.
- technical-writing — 영어 문장 규칙. 한국어 보고 원칙과 맞지 않는다.
- bro, in-your-own-words — 한 줄짜리라 전역 규칙으로 충분.

## 2차 — 원칙을 장치로 (Codex 위임)
1. **explain-the-number 게이트**: on_complete result 에 수치(score, coverage, 속도 등)가 있으면 `source`(측정 명령·파일) 가 있어야 통과. 처음 2주는 `warn` 모드로 측정 후 강제 전환.
2. **encode-lessons-in-structure**: meta-review 가 같은 교정이 2회 나오면 문장 대신 lint·hook·테스트 이슈를 만든다.

## 측정
- 이식 스킬 사용 횟수: 세션 로그에서 스킬 호출 집계(2주 뒤 2026-11-17). 0회 스킬은 트리거 문구 보강 또는 제거.
- proof 거부율·되돌아옴 비율 계속 추적.
