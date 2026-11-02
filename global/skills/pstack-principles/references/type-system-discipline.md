# 타입 시스템 규율 (Type System Discipline)

> 언제: 타입을 설계하거나, 함수 시그니처를 검토하거나, 정적 타입 언어로 코드를 쓸 때.

불가능한 상태, 어긋난 원시 타입, 처리 안 된 변형을 컴파일러가 거부하게 만든다. 처리기를 늘리기보다 에러와 특수 사례가 애초에 존재하지 않게 정의한다. (TypeScript 문법은 `typescript-best-practices` 스킬.)

- **의미 있는 원시 타입에 상표를 붙인다.** `UserId` 와 `OrderId` 는 둘 다 문자열이지만 서로 바꿔 쓰면 안 된다. 각자 타입을 준다(TypeScript 는 branded intersection, 다른 언어는 newtype). 생성 시 한 번 검증하고 이후엔 타입을 믿는다. 두 인자가 같은 원시 타입인데 뜻이 다르면 상표를 붙인다.
- **외부 데이터는 파싱 전까지 타입이 없다.** RPC 페이로드, JSON, IPC 메시지, CLI 인자, 설정 파일, 환경변수, DB 행. 모든 경계에 비정형 입력을 타입 모델로 바꾸는 파싱 함수를 둔다. 검증 위치는 [경계 규율](boundary-discipline.md).
- **권위 있는 스키마에서 타입을 도출한다.** protobuf, OpenAPI, GraphQL 스키마, DB 마이그레이션, 디자인 토큰 파일 등 어떤 파일이 모양을 소유하면, 평행한 타입을 손으로 만들지 말고 거기서 도출한다. [교훈을 구조에 새긴다](encode-lessons-in-structure.md) 참고.

---

## 영어 원문 (open-pstack `principle-type-system-discipline`, 그대로)

원문의 상대 링크(`../principle-*/SKILL.md`)는 이 스킬에서 `references/<원칙이름>.md` 에 해당한다.

````markdown
---
name: principle-type-system-discipline
description: "Apply when designing types, reviewing a function signature, or writing code in any statically-typed language. Make illegal states unrepresentable, brand semantic primitives, parse external data at boundaries, exhaust variants, derive from authoritative schemas."
user-invocable: false
---

# Type System Discipline

Make the compiler reject impossible states, mismatched primitives, and unhandled variants. Prefer defining errors and special cases out of existence over proliferating handlers. For TypeScript syntax, see the `typescript-best-practices` skill.

- **Brand semantic primitives.** `UserId` and `OrderId` are strings underneath but should not be interchangeable. Give each its own type, such as a branded intersection in TypeScript or a newtype elsewhere. Validate once at creation, trust the type downstream. If two arguments share a primitive type but mean different things, brand them.
- **External data is untyped until parsed.** RPC payloads, JSON, IPC messages, CLI args, config files, environment variables, database rows. Have a parse function at every boundary that turns unstructured input into the typed model. The **boundary-discipline** principle skill says where to put validation.
- **Derive types from authoritative schemas.** When a protocol buffer, OpenAPI spec, GraphQL schema, database migration, design-token file, or another file owns a shape, derive from it instead of hand-rolling a parallel type. See the **encode-lessons-in-structure** principle skill.
````
