---
name: slds-ui-readability
description: Use when creating or modifying UI components — Salesforce Lightning Design System (SLDS) layout/tokens + 가독성 절대 규칙 (form fields, badges, card borders, dark-bg text). Activate when touching files like *.tsx, *.jsx, *.vue, *.svelte, *.erb under views/ or components/, or when user mentions "UI", "컴포넌트", "디자인", "form", "badge", "card", "버튼". Pair with `harness-ui-trends-2026` (loaded first) and project `brand-dna.json` (overrides this skill).
trigger: slds-ui
---

# UI/UX 원칙: Salesforce Lightning Design System (SLDS) + 가독성 절대 규칙

> **로드 우선순위**: 프로젝트 `brand-dna.json` > `harness-ui-trends-2026` skill > **이 skill (SLDS 기본값)**.

## 1. 레이아웃 구조

- **3-Column Layout**: 좌측(Navigation), 중앙(Main Workspace), 우측(Contextual Sidebar/Activity) 구조를 기본
- **Card 기반 설계**: 모든 독립된 데이터 단위는 `Card` 컴포넌트로 그룹화. 상단에 명확한 Header + Action 버튼
- **Compact Header**: 핵심 정보(KPI, 요약 데이터)는 항상 상단에 고정

## 2. 디자인 토큰 및 스타일 (기본값)

- **Color Palette**: Salesforce Blue(`#00A1E0`), 중립 배경(`#F3F2F2`), 텍스트 강조(`#16325C`)
- **Spacing & Radius**: padding `1rem`, border-radius `0.25rem`(4px) — 기업용 신뢰감
- **Typography**: 위계 명확. 제목 Bold, 본문 Regular. 가독성 최우선

## 3. Action-Oriented UX

사용자가 데이터 조회 후 다음 행동(보험 분석/일정 추가 등)을 즉시 수행할 수 있도록 상단 또는 카드 우측 상단에 **Global Actions** 배치.

## 4. Icon System

**모든 시스템의 아이콘은 Feather Icons 스타일(Line/Outline)** — 강제 (사용자 글로벌 결정 2026-05-04).

> **사용자 발화**: *"내가 개발하는 프로젝트의 모든 icon이 line icons style 였으면 좋겠어"*

이모지 대신 SVG 라인 아이콘 사용 — 전문성 + 일관성 확보.

기본 속성:
- `stroke-width`: 2px (작은 사이즈 <16px 시 1.5px)
- `stroke-linecap`: round
- `stroke-linejoin`: round
- `fill`: none
- 색상: `stroke="currentColor"`로 텍스트 색상과 자동 연동
- viewBox: `0 0 24 24` 표준
- 라이브러리: Feather Icons (MIT) / Lucide / Tabler / Heroicons outline

**금지 패턴 (위반 시 BRAND_GUARD 이슈 자동 생성)**
- ❌ 이모지를 UI 아이콘 자리에 사용 (`🎨`, `📊`, `🎯` 등) — 헤더/메뉴/버튼/카드 일체 금지
- ❌ duotone / solid fill / gradient stroke / glow / neon
- ❌ AI generated 풍 일러스트 아이콘
- ❌ 외부 CDN 의존 (inline SVG로 1회 정의 + 재사용)

**구현 패턴 (참조 구현: TowninAlpafold `components/icons.js`)**
```js
const FEATHER_PATHS = { 'grid': '<rect.../>', 'compass': '<circle.../>', /* ... */ };
window.getIcon = function(name, opts = {}) {
  const { size = 18, stroke = 2 } = opts;
  return `<svg width="${size}" height="${size}" viewBox="0 0 24 24"
    fill="none" stroke="currentColor" stroke-width="${stroke}"
    stroke-linecap="round" stroke-linejoin="round">${FEATHER_PATHS[name]}</svg>`;
};
// HTML: <button data-icon="grid">갤러리</button>
// JS: bootstrapIcons() — 페이지 로드 시 [data-icon] 자동 SVG 주입
```

**brand-dna.json 토큰**
- `personality.icon_style: "feather-outline"` — 모든 신규 brand-dna 기본값.
- brand-guardian이 BRAND_DEFINE 시 강제 + 기존 프로젝트 audit 시 위반 감지.

**예외**
- 인포그래픽/배지 일러스트 (UI 아이콘이 아닌 콘텐츠 자산)
- 외부 서비스 로고 (Brand SVG 그대로)
- 스크린샷/차트 내부 이모지 인용

---

## 5. 가독성 절대 규칙 (위반 금지) — 모든 프로젝트 공통 ⭐

### Form 입력 필드

```
// ❌ 금지
border-gray-200 / text-xs / py-2 / uppercase tracking-wider / text-gray-500 (label)

// ✅ 필수
input/textarea: w-full px-3 py-2.5 border border-gray-300 rounded-lg text-sm text-gray-900
                placeholder-gray-400 focus:outline-none focus:border-[#00A1E0] focus:ring-1 focus:ring-[#00A1E0]
select:         위와 동일 + bg-white 명시
label:          block text-xs font-semibold text-gray-600 mb-1.5
```

### 배지 (Badge)

```
// ❌ 금지 — 투명도/연한 배경
background: `${color}28` / bg-blue-100 text-blue-700

// ✅ 필수 — solid 배경 + white 텍스트
style={{ background: color, color: "white" }}
```

### 카드 테두리

```
// ❌ 금지
border-gray-100  (거의 안 보임)

// ✅ 필수
border-gray-200  (카드 최소값)
```

### 다크 배경 (#16325C) 위 텍스트

```
// ❌ 금지
text-white/50 이하

// ✅ 필수
text-white/60 이상 (보조: /70, 메타: /65)
```

### 새 컴포넌트 작성 후 자가 체크리스트

- [ ] input/select `border-gray-200` → `border-gray-300`
- [ ] input/select `text-xs` → `text-sm`
- [ ] input/select `py-2` → `py-2.5`
- [ ] label `uppercase tracking-wider` 제거, `text-gray-600 mb-1.5` 적용
- [ ] select `bg-white` 명시
- [ ] 배지 투명도(`28`, `bg-*-100`) → solid 변경
- [ ] 카드 `border-gray-100` → `border-gray-200`
- [ ] 다크 배경 위 `text-white/50` 이하 → `/60` 이상
