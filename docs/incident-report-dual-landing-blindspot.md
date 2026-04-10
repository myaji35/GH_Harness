# Incident Report: 듀얼 랜딩 페이지 가독성 맹점

**일시**: 2026-04-10
**프로젝트**: choi-pd (imPD)
**심각도**: High
**영향**: 10라운드 UI/UX 개선 + gstack QA + design-critic 모두 가독성 문제를 놓침

---

## 사건 요약

imPD 프로젝트에서 10라운드 UI/UX + 비즈니스 로직 대규모 개선을 실행했다.
Harness 에이전트(Explore, design-critic 차원 분석)와 gstack /qa 브라우저 QA 모두 실행했으나,
**루트 랜딩 페이지(`/`)의 다크 히어로 가독성 문제 5건을 모두 놓쳤다.**

대표님이 직접 스크린샷을 제공한 후에야 발견.

---

## 근본 원인 (5-Why)

### Why 1: 왜 가독성 문제를 못 찾았나?
→ 테스트 대상이 `/chopd` 페이지(밝은 히어로)였고, `/` 페이지(다크 히어로)를 테스트하지 않았다.

### Why 2: 왜 `/` 페이지를 테스트하지 않았나?
→ 두 가지 원인:
  - **코드 분석 단계**: Explore 에이전트가 `src/app/chopd/page.tsx` + `src/components/home/HeroSection.tsx`만 분석. `src/app/page.tsx`(루트)는 별개 파일로 분석 범위에 미포함.
  - **브라우저 QA 단계**: gstack browse가 `http://localhost:3008`에 접속 → middleware의 subdomain rewrite 또는 redirect 로직에 의해 `/chopd`로 이동 → 루트 `/` 다크 히어로를 건너뜀.

### Why 3: 왜 Explore 에이전트가 `src/app/page.tsx`를 빠뜨렸나?
→ 분석 프롬프트에서 "랜딩 페이지"를 `src/app/chopd/page.tsx`로 특정했고, App Router의 라우트 구조를 전수 스캔하지 않았다.

### Why 4: 왜 proactive-scan.sh가 이 문제를 감지하지 못했나?
→ proactive-scan은 **정적 코드 분석**(타입 에러, lint, TODO, 보안)만 수행. **시각적 가독성**(색상 대비, 텍스트 opacity)은 스캔 범위에 포함되지 않음.

### Why 5: 왜 design-critic이 실행되지 않았나?
→ 10라운드 이슈 파이프라인에서 `on_complete.sh`의 표준 흐름(GENERATE_CODE → RUN_TESTS → SCORE)을 따랐으나, UI 파일 변경 시 자동 트리거되는 `UI_REVIEW → DESIGN_REVIEW` 체인이 10라운드 이슈에는 적용되지 않았다. 10라운드는 직접 ISS-061~070으로 생성했기 때문에 on_complete 파생 이슈 체인을 우회함.

---

## 영향받은 에이전트/시스템

| 컴포넌트 | 문제점 | 상태 |
|---------|--------|------|
| **Explore 에이전트** | 라우트 전수 스캔 없이 지정 파일만 분석 | 프롬프트 개선 필요 |
| **proactive-scan.sh** | 시각적 가독성 검증 없음 (정적 코드만) | 기능 추가 필요 |
| **design-critic** | 10라운드 직접 이슈에서 자동 트리거 안 됨 | 파이프라인 수정 필요 |
| **gstack /qa** | middleware redirect로 루트 페이지 건너뜀 | 라우트 전수 테스트 필요 |
| **on_complete.sh** | 수동 생성 이슈에서 UI_REVIEW 파생 안 됨 | 조건 추가 필요 |

---

## 수정 제안 (Harness 엔지니어링)

### 1. proactive-scan.sh에 "라우트 전수 발견" 단계 추가

```bash
# 제안: App Router 라우트 전수 스캔
find src/app -name "page.tsx" -o -name "page.ts" | sort
# → 모든 라우트 파일을 나열하여 분석 대상 누락 방지
```

**적용 위치**: `project/hooks/proactive-scan.sh`
**효과**: 듀얼 랜딩, 숨겨진 라우트 등 구조적 맹점 제거

### 2. design-critic 자동 트리거 조건 확대

현재: `UI_REVIEW 통과 후 → DESIGN_REVIEW`
추가: **모든 GENERATE_CODE/FIX_BUG 이슈에서 UI 파일(.tsx) 변경 감지 시 → DESIGN_REVIEW 자동 생성**

```
# on_complete.sh 수정 제안
if result.files_modified contains *.tsx:
  create DESIGN_REVIEW issue → design-critic
```

**적용 위치**: `project/hooks/on_complete.sh`

### 3. design-critic에 "다크 배경 가독성 체크리스트" 추가

현재 검증 8차원 중 "색상 조화"에 다크 모드/다크 배경 전용 체크가 없다.

```markdown
### 3-1. 다크 배경 가독성 (Dark Surface Readability)
- 다크 배경(#0f172a, #16325C 등) 위 텍스트가 white/60 이상인가
- nav 링크가 text-gray-300 이하로 안 보이지 않는가
- ghost 버튼(border-only)의 border opacity가 /30 이상인가
- 배지/라벨의 배경 대비가 충분한가
- 지표 라벨 등 보조 텍스트가 text-gray-500 이하가 아닌가
```

**적용 위치**: `global/agents/design-critic.md` > 검증 8가지 차원 > 3번 색상 조화 하위 추가

### 4. Explore 에이전트 프롬프트 가이드라인

코드베이스 분석 시 **반드시 `src/app/` 하위 모든 page.tsx를 먼저 나열**한 후 분석 대상을 결정하도록 가이드라인 추가.

```
[분석 전 필수]
1. find src/app -name "page.tsx" | sort → 전체 라우트 목록 확인
2. middleware.ts 읽기 → redirect/rewrite 규칙 파악
3. next.config.js 읽기 → rewrites/redirects 파악
→ 이를 기반으로 실제 사용자가 접근하는 모든 페이지를 분석 대상에 포함
```

**적용 위치**: `global/agents/agent-harness.md` 또는 별도 `exploration-guidelines.md`

### 5. gstack /qa에서 middleware-aware 라우트 테스트

QA 시작 전 `src/middleware.ts`를 읽고, redirect/rewrite 규칙으로 인해 건너뛰는 라우트를 명시적으로 테스트 목록에 추가.

```
# QA Phase 3 (Orient) 개선
1. middleware.ts 읽기
2. redirect 대상 = 원본 URL도 별도 테스트
3. / 와 /chopd 가 다른 페이지면 둘 다 테스트
```

**적용 위치**: gstack 외부 → Harness의 browser-qa 관련 hook에서 라우트 목록 제공

---

## 실제 발견된 가독성 문제 (참고)

| # | 요소 | Before | After |
|---|------|--------|-------|
| 1 | Nav 링크 | `text-gray-300 font-medium` | `text-white/80 font-semibold` |
| 2 | Hero 서브텍스트 | `text-gray-400` | `text-gray-300` |
| 3 | 배지 텍스트 | `text-gray-300` | `text-white/80` |
| 4 | 배지 배경 | `bg-white/10 border-white/10` | `bg-white/15 border-white/20` |
| 5 | Ghost CTA 버튼 | `border border-white/20` | `border-2 border-white/40` |
| 6 | 지표 라벨 | `text-gray-500` | `text-gray-400` |

**수정 커밋**: `28e9525`

---

## 재발 방지 체크리스트

- [ ] proactive-scan.sh에 라우트 전수 발견 추가
- [ ] on_complete.sh에 .tsx 변경 시 DESIGN_REVIEW 자동 생성 추가
- [ ] design-critic.md에 다크 배경 가독성 체크리스트 추가
- [ ] agent-harness 분석 가이드라인에 page.tsx 전수 스캔 필수 추가
- [ ] browser-qa hook에 middleware-aware 라우트 목록 제공

---

*보고자: Claude Harness System*
*일시: 2026-04-10*
