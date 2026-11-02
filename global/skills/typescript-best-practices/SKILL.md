---
name: typescript-best-practices
description: |
  TypeScript 작성·검수 기준 — 판별 유니온, 브랜드 타입, 구성으로 불가능한 상태 막기, any 대신 unknown, as 캐스트 금지,
  경계에서 한 번 검증, 완전성 검사, satisfies 등. .ts/.tsx 파일을 읽거나 고칠 때, Codex 에 TS 작업을 지시하거나
  그 diff 를 검수할 때 기준으로 쓴다. 대표님이 "타입스크립트 제대로 짜", "타입 안전하게", "as 캐스트 빼", "any 없애",
  "TS 베스트 프랙티스", "/typescript-best-practices" 라고 할 때도 사용한다.
triggers:
  - typescript-best-practices
  - 타입스크립트 제대로 짜
  - 타입 안전하게
  - as 캐스트 빼
  - any 없애
paths: ["**/*.ts", "**/*.tsx"]
---

# TypeScript best practices

> 출처: open-pstack `typescript-best-practices` (MIT, NOTICE.md). GH_Harness 규칙에 맞게 옮김.

원칙 참고: `pstack-principles` 스킬(이식돼 있으면)의 type-system-discipline, boundary-discipline.

**하네스에서 쓰는 법.** TS 코드 작성·수정은 Codex 에 위임한다. 이 표는 (1) Codex 지시문에 "지켜야 할 규칙"으로 해당 행을 붙이고, (2) `git diff` 검수 때 위반을 찾는 체크리스트로 쓴다. 위반은 직접 고치지 않고 구체 지시로 재위임한다(`opus-codes`). 프로젝트 CLAUDE.md·`brand-dna.json` 규칙과 충돌하면 프로젝트 규칙이 우선한다.

| 규칙 | 요약 |
|------|------|
| 판별 유니온 | 변형은 `kind` 리터럴 판별자로 모델링해 불가능한 상태를 표현할 수 없게 한다. optional 필드 묶음 금지. |
| 브랜드 타입 | 원시값에 `& { readonly __brand: "X" }` 로 브랜드를 달아 섞이지 않게 한다. 경계에서 한 번 검증. 브랜드는 검증하는 타입 가드(`input is AgentId`)에서만 나오고 `as` 로 만들지 않는다. |
| 구성으로 막기 | 잘못된 값을 아예 만들 수 없는 모양으로 짓는다. 비어 있지 않음은 `[T, ...T[]]`, 짝수 길이는 `[T, T][]`, 구간은 `start` + `duration`. 런타임 가드나 정제 타입 희망이 아니다. |
| 가장 단순한 전함수 타입 | 모든 연산이 전함수(total)로 남는 동안은 `T[]` 를 유지한다. 느슨한 타입 때문에 `!`·캐스트·"절대 안 일어남" throw 가 필요해지는 곳에서만 `NonEmpty<T>` 로 강화. |
| `any` 대신 `unknown` | 외부 데이터는 `unknown`. |
| 가드보다 스키마 먼저 | 속성별 타입 가드를 손으로 쓰기 전에 저장소의 런타임 스키마 라이브러리를 쓰고 타입은 스키마에서 끌어낸다(`z.infer` 등). |
| `as` 캐스트 금지 | 모든 `as` 는 언젠가 터질 런타임 오류다. 검증한 뒤에만 캐스트. |
| 좁히기 순서 | 판별자 switch > `in` 연산자 > `typeof`/`instanceof` > 사용자 정의 타입 가드 > `as`. |
| 타입 가드 | 주장을 실제로 검증해야 한다. 거짓말하는 가드는 `as` 보다 나쁘다 — 안전하다는 이름 뒤에 버그가 숨는다. 이름은 `isX`/`hasX`. |
| 완전성 검사 | default 분기에 `const _exhaustive: never = x;` 를 넣어 새 변형이 추가되면 컴파일러가 잡게 한다. |
| `as` 대신 `satisfies` | 리터럴 타입을 넓히지 않고 값을 검증한다. |
| 경계 검증 | 데이터가 들어오는 곳에서 이름 있는 도메인 타입으로 파싱한다. `Record<string, unknown>` 은 그 파싱에서 끝난다. 안쪽에서는 타입을 믿는다. |
| 기존 타입에서 끌어내기 | 새 interface 를 선언하기 전에 `Pick`/`Omit`/`Parameters`/`ReturnType`/`Awaited`/`typeof` 를 먼저 쓴다. |
| 객체 인자 | 위치 인자 대신 객체를 넘겨 인자 순서가 스스로 설명되게 한다. 핫 패스(프레임마다 렌더, 토크나이저, 파서)는 예외. |
| 진짜 테스트 | 돌릴 수 있는 건 mock 하지 않는다. 프레임워크의 실제 테스트 기능과 누수·dispose 검사를 쓰고 UI 는 실행 중인 빌드에서 확인한다. 로컬에서 못 돌리는 것만 mock. |
| 구조화 로그 | id 하나로 디버깅할 수 있을 만큼 맥락을 담은 구조화 로거를 쓴다. 배포 코드에 `console.log` 금지. |

예시 코드: `references/patterns.md`(원문).

검증 증거(`proof`)는 보통 `npx tsc --noEmit` 와 관련 테스트 실행 출력이다.
