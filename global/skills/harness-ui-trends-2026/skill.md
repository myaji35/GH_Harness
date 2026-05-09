# Harness UI Trends 2026 — 공통 디자인 코드 (전역)

> **적용 범위**: GH_Harness 기반 모든 프로젝트의 **공통 UI/UX 규칙**.
> **우선순위**: 이 문서 < 프로젝트 `brand-dna.json` (프로젝트 값이 override).
> **로드 시점**: SessionStart 훅 + 모든 UI 작업 시작 전.

---

## 1. 2026 SaaS UI 7대 트렌드 (구현 매핑)

| 트렌드 | 핵심 규칙 | 구현 코드 힌트 |
|---|---|---|
| **Calm Design** | 기본 뷰는 필수만. 고급은 `<details>` / 토글 | `max-width: 800px`, `gap: 2rem`, `padding: 1.5rem` |
| **AI as Infrastructure** | "AI 배지" 과장 금지, 인라인 제안 | `aria-label="AI generated"`, 드래프트: `bg-purple-500/10` |
| **Command Palette** | ⌘K 전역 단축키 필수 | `cmdk` 라이브러리, `role="combobox"`, 최근 항목 우선 |
| **Role-Based View** | scale_mode/role에 따라 기본 탭 변경 | `localStorage` 또는 DB 저장 |
| **Progressive Disclosure** | 1 화면 1 CTA, 고급 옵션은 펼침 | 빈 상태 메시지: 1개 행동만 제시 |
| **Emotional Design** | 완료 마이크로 애니메이션, 인간다운 카피 | `animate-bounce` 0.3s, 성공 `#10B981` |
| **Spotlight UX** | 화면당 CTA 1개 + 중립색 | 주색 1 + 회색/검정, 8px 기반 스페이싱 |

---

## 2. 하네스 공통 컴포넌트 레시피

모든 하네스 UI(이슈 체인, 파이프라인, 대시보드)에서 **공통으로 쓰는** 컴포넌트. 프로젝트별 색상은 `brand-dna.json`의 `design_tokens.colors`로 override.

### 2-1. KPI Metric Card
```tsx
// 상단 고정, 최대 3~4개. 중요도: 파이프라인 진행률 > 이슈 현황 > 예산 > 학습
function KpiCard({ label, value, delta, sub }) {
  return (
    <div className="bg-white border border-gray-200 rounded-lg p-4">
      <div className="flex items-center justify-between mb-1.5">
        <span className="block text-xs font-semibold text-gray-600">{label}</span>
        {delta !== undefined && (
          <span className="text-[10px] font-bold px-1.5 py-0.5 rounded text-white"
                style={{ background: delta >= 0 ? "#10B981" : "#EF4444" }}>
            {delta >= 0 ? "▲" : "▼"} {Math.abs(delta)}%
          </span>
        )}
      </div>
      <div className="text-2xl font-bold" style={{ color: "var(--brand-text-primary, #16325C)" }}>
        {value}
      </div>
      {sub && <div className="text-[10px] text-gray-500 mt-1">{sub}</div>}
    </div>
  );
}
```

### 2-2. Pipeline Tracker Bar (Tremor Tracker 패턴)
```tsx
// 30~50개 이슈를 가로 bar 하나에 색상 조각으로 — 한눈에 상태 분포 파악
{issues.map(i => (
  <div key={i.id}
       className="flex-1 h-6 first:rounded-l-md last:rounded-r-md cursor-pointer
                  transition-all hover:scale-y-125"
       style={{ background: HARNESS_ISSUE_STATUS_CONFIG[i.status].color }}
       title={`${i.id} ${i.title}`} />
))}
```

### 2-3. DAG 시각화 (React Flow + Dagre)
`depends_on` 관계를 트리로 표현. 2단계 이상 자식 오독 문제 해결.
```tsx
import ReactFlow from "reactflow";
import dagre from "dagre";

const g = new dagre.graphlib.Graph();
g.setGraph({ rankdir: "LR", ranksep: 60, nodesep: 20 });
issues.forEach(i => g.setNode(i.id, { width: 180, height: 40 }));
issues.forEach(i => (i.depends_on ?? []).forEach(dep => g.setEdge(dep, i.id)));
dagre.layout(g);
```

### 2-4. T2 컨펌 Callout (최우선 표시)
```tsx
// AWAITING_USER 이슈가 있을 때 최상단 고정
<div className="border-l-4 border-[#F59E0B] bg-[#FEF3C7] rounded-r-lg p-4 mb-4">
  <div className="flex items-start justify-between">
    <div>
      <span className="text-xs font-semibold text-[#92400E]">T2 사용자 컨펌 대기</span>
      <p className="text-sm text-gray-900">{issue.title}</p>
    </div>
    <div className="flex gap-2">
      <button className="px-3 py-1.5 text-xs font-bold text-white rounded-lg"
              style={{ background: "#10B981" }}>승인</button>
      <button className="px-3 py-1.5 text-xs font-bold text-gray-700 bg-white
                         border border-gray-300 rounded-lg">거절</button>
    </div>
  </div>
</div>
```

### 2-5. Trace Timeline (Langfuse 스타일 계층 실행 시각화)
```tsx
// 루트 이슈 기준 자식 스폰의 시작/종료를 가로 막대로. 소요시간 비교 가능.
const total = new Date(root.completed_at).getTime() - new Date(root.created_at).getTime();
// 각 이슈를 start%~end% 구간의 막대로 표현
```

### 2-6. Command Palette (⌘K)
```tsx
<Command.Dialog>
  <Command.Input placeholder="이슈 제목, 에이전트, 타입…" />
  <Command.Group heading="생성">
    <Command.Item>FEATURE_PLAN 시작 <kbd>⌘N</kbd></Command.Item>
    <Command.Item>SCREEN_GAP 스캔</Command.Item>
    <Command.Item>비즈니스 로직 점검 (4개 병렬)</Command.Item>
  </Command.Group>
  <Command.Group heading="파이프라인">
    <Command.Item>다음 READY 디스패치</Command.Item>
    <Command.Item>FAILED 재큐</Command.Item>
  </Command.Group>
</Command.Dialog>
```

---

## 3. UI 가독성 절대 규칙 (위반 금지)

전역 CLAUDE.md와 동일. 다시 강조:

### 3-1. Form 입력
```tsx
// ✅ input/textarea
className="w-full px-3 py-2.5 border border-gray-300 rounded-lg text-sm text-gray-900
           placeholder-gray-400 focus:outline-none focus:border-[#00A1E0]
           focus:ring-1 focus:ring-[#00A1E0]"

// ✅ select
className="... bg-white ..."  // bg-white 명시 필수

// ✅ label
className="block text-xs font-semibold text-gray-600 mb-1.5"
// ❌ uppercase tracking-wider text-gray-500 금지
```

### 3-2. 배지(Badge) — solid 배경 필수
```tsx
// ❌ 금지
style={{ background: `${color}28` }}       // 투명도
className="bg-blue-100 text-blue-700"       // 연한 배경

// ✅ 필수
style={{ background: color, color: "white" }}
className="text-[10px] font-bold px-1.5 py-0.5 rounded text-white"
```

### 3-3. 카드 테두리 / 다크 배경 텍스트
- 카드: `border-gray-200` (최소값, `border-gray-100` 금지)
- 다크 헤더(#16325C) 위: `text-white/60` 이상 (`text-white/50` 이하 금지)

### 3-4. 아이콘 — Line icon 강제 (사용자 글로벌 결정 2026-05-04)

> **사용자 발화**: *"내가 개발하는 프로젝트의 모든 icon이 line icons style 였으면 좋겠어"* (TowninAlpafold ICON_LINE_HARNESS_GLOBAL-001)

**모든 하네스 프로젝트의 UI 아이콘은 line(stroke-only) 스타일을 사용한다. 이모지·duotone·solid·gradient 아이콘 금지.**

| 항목 | 규칙 |
|---|---|
| 기본 라이브러리 | **Feather Icons** (https://feathericons.com, MIT, ~25KB inline) |
| 대체 라이브러리 | Lucide (Feather fork) / Tabler / Heroicons outline |
| stroke 너비 | `2px` 기본, 작은 사이즈(<16px) 시 `1.5px` |
| viewBox | `0 0 24 24` 표준 |
| fill | `none` 필수 (stroke로만 그림) |
| stroke 색 | `currentColor` (부모 색 상속) |
| 코너/조인 | `stroke-linecap="round" stroke-linejoin="round"` |

**금지 패턴**
- ❌ 이모지 사용 (`🎨`, `📊`, `🎯` 등) — UI 아이콘 자리에 절대 금지. 단, 인포그래픽 일러스트/문서 인용은 허용.
- ❌ `fill="solid-color"` 아이콘 (stroke 없는 채움)
- ❌ duotone (`fill="..." opacity` 두 색)
- ❌ gradient stroke / glow / neon
- ❌ AI generated 풍 일러스트 아이콘

**구현 패턴 (참조: `0051_TowninAlpafold/components/icons.js`)**
```js
// FEATHER_PATHS 매핑 + getIcon(name, opts) 헬퍼
const FEATHER_PATHS = {
  'grid':         '<rect x="3" y="3" width="7" height="7"/>...',
  'compass':      '<circle cx="12" cy="12" r="10"/>...',
  'bar-chart-2':  '<line x1="18" y1="20" .../>',
  // ...
};
function getIcon(name, opts = {}) {
  const { size = 18, stroke = 2, className = 'feather-icon' } = opts;
  return `<svg class="${className}" width="${size}" height="${size}"
    viewBox="0 0 24 24" fill="none" stroke="currentColor"
    stroke-width="${stroke}" stroke-linecap="round" stroke-linejoin="round"
    aria-hidden="true">${FEATHER_PATHS[name]}</svg>`;
}
// HTML 측: <button data-icon="grid">갤러리</button>
// JS bootstrap: 페이지 로드 시 [data-icon] 자동 SVG 주입
```

**brand-dna.json 토큰 (자동 적용)**
- `personality.icon_style: "feather-outline"` — 기본값. 신규 프로젝트 brand-dna 생성 시 brand-guardian이 강제.
- 위반 감지 시 `BRAND_GUARD` 이슈 자동 생성 (각 프로젝트의 `proactive-scan.sh` 또는 `brand-guard.sh` hook).

**예외**
- 인포그래픽/배지 일러스트 (UI 아이콘이 아닌 콘텐츠 자산)
- 외부 서비스 로고 (Brand SVG 그대로 사용)
- 스크린샷/차트 내부 텍스트/이모지 인용

---

## 4. 상태 팔레트 (하네스 공통 컬러 토큰)

프로젝트 `brand-dna.json`에 override 없으면 이 기본값 사용.

| 용도 | HEX | 의미 |
|---|---|---|
| CREATED / READY (대기) | `#3B82F6` | 파란색 — 시작 준비 |
| IN_PROGRESS | `#F59E0B` | 주황 — 진행 중 |
| DONE | `#10B981` | 초록 — 완료 |
| FAILED | `#EF4444` | 빨강 — 실패 |
| ESCALATED | `#DC2626` | 진한 빨강 — 에스컬레이션 |
| LEARNED | `#8B5CF6` | 보라 — 학습됨 |
| SKIPPED | `#9CA3AF` | 회색 — 건너뜀 |
| AWAITING_USER | `#F59E0B` + 배경 `#FEF3C7` | 주황 Callout — T2 컨펌 |
| Accent (브랜드 기본) | `#00A1E0` | Salesforce Blue |
| Text primary | `#16325C` | 다크 네이비 |
| Surface alt | `#F3F2F2` | 중립 배경 |

---

## 5. 레이아웃 표준 (3-Column SLDS + 하네스 탭)

```
┌──────────────────────────────────────────────────────────┐
│ [T2 Callout — AWAITING_USER 있을 때 최상단 고정]          │
├───────┬──────────────────────────────────┬───────────────┤
│ Left  │ KPI 3 Cards (진행률/이슈/예산)   │ Right         │
│ Nav   ├──────────────────────────────────┤ Activity      │
│ Rail  │ Pipeline Tracker Bar             │ Timeline      │
│       ├──────────────────────────────────┤ (Hermes/      │
│       │ DAG Canvas (React Flow)          │  advisor/     │
│       │  + 선택 시 하단 payload/timeline │  meta obs)    │
└───────┴──────────────────────────────────┴───────────────┘
```

---

## 6. 프로젝트 `brand-dna.json` 연동 규칙

1. 이 문서의 기본값을 베이스로 둔다.
2. 프로젝트 루트의 `brand-dna.json`이 있으면 `design_tokens`를 읽어 다음을 override:
   - `colors.hero` → Accent 대체
   - `colors.text_primary` → 다크 배경 헤더 대체
   - `colors.surface` / `surface_alt` → 배경
   - `typography.font_heading` / `font_body` → 폰트 페어링
   - `shape.radius` → `rounded-lg` ↔ `rounded-md` ↔ `rounded-xl`
   - `motion.hover_effect` → lift ↔ glow ↔ none
3. `brand-dna.json`의 `agenda` 필드는 UI 빈 상태 메시지 / 히어로 문구에 인라인 반영.
4. `anti_patterns` 배열에 있는 항목은 디자인 리뷰 시 자동 감점.

---

## 7. 참조 라이브러리

- **Tremor** (`tremor/react`) — KPI 카드, Tracker, BarList
- **React Flow + Dagre** (`reactflow`, `@dagrejs/dagre`) — DAG 레이아웃
- **cmdk** — ⌘K 명령 팔레트
- **shadcn/ui** — 3-column 대시보드 베이스

레퍼런스 벤치마크: LangSmith, Langfuse, Linear, Temporal, Prefect, GitHub Actions Workflow Visualization.

---

## 8. 구현 우선순위 (하네스 공통)

| 순서 | 작업 | 적용 트렌드 |
|---|---|---|
| 1 | T2 Callout 컴포넌트 | Spotlight UX + Progressive Disclosure |
| 2 | KPI 3 Cards (예산 포함) | Calm Design + LangSmith KPI |
| 3 | React Flow DAG | Temporal activity view |
| 4 | Command Palette | Linear ⌘K |
| 5 | Timeline 뷰 | Langfuse hierarchical trace |

---

*이 파일은 전역 공통. 프로젝트별 개성은 `brand-dna.json`에.*
