---
name: react-bits
description: React Bits(reactbits.dev) 애니메이션 UI 컴포넌트를 React 프로젝트에 넣는다 — 텍스트 애니메이션, 커서·호버 효과, WebGL·캔버스 배경, 마이크로 인터랙션, 효과음. 컴포넌트 소스·props·의존성은 기억으로 쓰지 않고 항상 공식 registry 에서 받는다. 대표님이 "react bits", "리액트빗츠", "reactbits 컴포넌트 넣어줘", "BlurText/SplitText/Aurora 같은 효과", "히어로에 움직이는 배경", "/react-bits" 라고 하거나, React 화면에 눈에 띄는 애니메이션·배경 효과가 필요할 때 사용한다.
---

# React Bits

React Bits 는 DavidHDev 가 만든 애니메이션 UI 컴포넌트 모음이다(약 220개 + 효과음 200개). 컴포넌트마다 변형 4개가 있다: `JS-CSS`, `JS-TW`, `TS-CSS`, `TS-TW`.

**원칙: 컴포넌트 코드·props 이름·기본값·의존성을 기억으로 쓰지 않는다.** 매번 공식 registry(`https://reactbits.dev/r/`)에서 받고, 받은 파일을 읽은 뒤 쓴다. registry 에 닿지 못하면 실패라고 말하고, 기억한 코드로 대신하지 않는다.

## 1. 고르기

- 후보 찾기: [references/catalog.md](references/catalog.md) 에서 분류(Animations / Backgrounds / Components / Micro / Text Animations / Sounds)·설명·의존성을 검색한다.
- 목록이 오래됐을 수 있다. 이름이 목록에 없거나 확신이 없으면 실시간 확인:
  `curl -fsS https://reactbits.dev/r/registry.json | jq -r '.items[].name' | grep -i <키워드>`
- 모양 확인이 필요하면 catalog 의 링크(데모 페이지)를 브라우저로 연다.
- 하네스 디자인 우선순위는 그대로다: `brand-dna.json` > harness-ui-trends-2026 > 나머지. React Bits 는 **효과 부품**이다. 색·폰트는 컴포넌트 props 로 brand-dna 값에 맞추고, `anti_patterns` 에 걸리는 과한 효과(화면 전체 번쩍임, 읽기 방해하는 텍스트 애니메이션)는 쓰지 않는다. 화면당 눈에 띄는 효과는 1~2개로 제한한다.

## 2. 변형 정하기

대상 프로젝트를 보고 정한다. 묻지 않는다.
- `tsconfig.json` 있음 → `TS`, 없으면 `JS`
- Tailwind 사용(`tailwind.config.*`, 또는 CSS 에 `@import "tailwindcss"`) → `TW`, 아니면 `CSS`

## 3. 설치

대상 React 프로젝트 루트(`package.json` 있는 곳)에서:

```bash
# shadcn 설정(components.json)이 있는 프로젝트 — 공식 권장
npx shadcn@latest add https://reactbits.dev/r/BlurText-TS-TW
# 그 외 — jsrepo
npx jsrepo@latest add https://reactbits.dev/r/BlurText-TS-TW
```

CLI 를 쓸 수 없거나(대화형 프롬프트가 막히는 경우 등) 경로를 직접 정하고 싶으면 JSON 을 받아 손으로 저장한다:

```bash
curl -fsS https://reactbits.dev/r/BlurText-TS-TW.json -o /tmp/rb.json
jq -r '.dependencies[]?' /tmp/rb.json          # 설치할 npm 패키지(버전 범위 포함)
jq -r '.registryDependencies[]?' /tmp/rb.json  # 먼저 받아야 할 다른 registry 항목
jq -r '.files[].path' /tmp/rb.json             # 저장할 파일들 — 전부 저장한다
```

`files[].content` 를 `src/components/<path>` 에 그대로 쓴다(`BlurText/BlurText.tsx` 처럼 하위 폴더 유지). 의존성은 프로젝트가 쓰는 패키지 매니저(npm/pnpm/yarn/bun — lock 파일로 판단)로 설치한다.

## 4. 함정

- **HTTP 200 이어도 실패일 수 있다**: 없는 이름은 사이트 HTML 이 200 으로 온다. 응답이 `{` 로 시작하는 JSON 이고 `files` 가 있는지 확인한다.
- **파일이 여러 개일 수 있다**: CSS 변형은 컴포넌트와 같은 폴더의 `.css` 가 함께 오는 경우가 많다. `files` 를 전부 저장한다 — 하나만 저장하면 깨진다.
- **scoped 패키지**: `@react-three/fiber@^9.3.0` 을 `@` 로 자르지 말 것. 버전 범위를 붙인 채로 설치하면 된다.
- **효과음**: `Sound*` 항목은 변형이 `-JS`/`-TS` 둘뿐이고 `registryDependencies` 로 `SoundEngine` 을 끌어온다. 수동 설치 시 SoundEngine 도 같이 받는다.
- **같은 이름 파일 덮어쓰기**: 이미 받은 컴포넌트를 고쳐 쓰고 있었으면 덮어쓰기 전에 `git diff` 로 확인한다.
- **Next.js App Router**: 브라우저 API·훅을 쓰는 컴포넌트는 파일 맨 위에 `'use client'` 가 있는지 보고 없으면 넣는다. WebGL(three/ogl) 배경은 `dynamic(() => import(...), { ssr: false })` 를 검토한다.
- **TypeScript `verbatimModuleSyntax`**: 타입 import 에러가 나면 `import type` 으로만 고친다. 컴포넌트를 다시 쓰지 않는다.

## 5. 쓰기와 검증

1. 받은 파일의 props 타입·기본값을 읽고 그 이름 그대로 쓴다. 추측한 prop 은 조용히 무시되거나 타입 에러가 난다.
2. 빌드/타입 검사(`npx tsc --noEmit` 또는 프로젝트 빌드)를 통과시킨다.
3. 화면에서 실제로 움직이는지 확인한다(run 스킬 또는 브라우저 스크린샷). 콘솔 WebGL 에러, 모바일 폭, `prefers-reduced-motion` 대응 여부를 본다.

## 라이선스 (MIT + Commons Clause)

앱·웹사이트·제품 안에 넣어 쓰는 건 상업용도 자유. **컴포넌트 자체를 팔거나 재배포(묶음·템플릿 팩·포팅판)하는 건 금지**다. 그래서 이 스킬에는 컴포넌트 소스를 넣지 않고, 쓸 때마다 공식 registry 에서 받는다. React Bits Pro(블록·템플릿·agent kit)는 별도 유료라 이 스킬 범위 밖이다.

## 목록 갱신

```bash
node ~/.claude/skills/react-bits/scripts/gen-catalog.mjs
```

공식 `llms.txt`(분류·설명) + `r/registry.json`(이름·변형·의존성)으로 `references/catalog.md` 를 다시 쓴다. Node 18+, 추가 패키지 없음. 갱신분은 GH_Harness 저장소의 `global/skills/react-bits/` 에 커밋해야 다음 `harness 업데이트` 때 유지된다.
