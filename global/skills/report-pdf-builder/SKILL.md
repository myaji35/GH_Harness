---
name: report-pdf-builder
description: Use when the user asks for a report ("보고서 만들어줘", "보고서로 만들어줘", "보고서 작성해줘", "리포트로", "PDF 보고서") — always produces a PDF as the final deliverable, not just markdown/HTML
trigger: report-pdf
---

# 보고서 생성 규칙 (PDF 최종 산출물 필수) ⭐

대표님이 "보고서 만들어줘 / 보고서로 만들어줘 / 보고서 작성해줘" 등 보고서를 요청하면 **반드시 PDF 파일까지 생성**한다. 마크다운/HTML만 만들고 끝내면 규칙 위반.

## 핵심 룰

- **최종 산출물은 PDF**. 중간 HTML/MD는 보조 산출물.
- **저장 위치**: `./docs/{주제}_{YYMMDD}.pdf` (별도 지정 없으면 기본값 — 프로젝트 docs 폴더, 없으면 생성). 프로젝트 밖(작업 디렉터리에 docs 부적합)일 때만 `~/Downloads/`로 폴백.
- **생성 완료 후**: `open {경로}` 로 자동 미리보기 열어 대표님께 보여드림
- **중간 산출물(HTML, 마크다운)**: `/tmp/` 또는 프로젝트 `docs/` 에 저장 (영구 위치 X)
- 대표님이 명시적으로 "PDF는 빼" 라고 할 때까지 이 규칙 유지

## ⚠️ 상하 여백 최소화 룰 (2026-05-03 추가) ⭐⭐

**대표님이 "쓸데없는 갭"을 싫어함. 모든 PDF 보고서는 다음 룰 엄수.**

### 1. wkhtmltopdf 마진 (필수)
```bash
--margin-top 12mm   # 18~20mm → 12mm 축소
--margin-bottom 12mm # 18~20mm → 12mm 축소
--margin-left 14mm  # 16mm → 14mm 약간 축소 (좌우는 가독성 위해 보존)
--margin-right 14mm
```
→ A4 1페이지에 들어가는 콘텐츠 면적 약 +25%

### 2. CSS 룰 (HTML 작성 시 필수)
```css
@page { size: A4; margin: 12mm 14mm; }  /* 상하 ↓↓ */
* { box-sizing: border-box; }
body { margin: 0; line-height: 1.45; }   /* line-height 1.55 → 1.45 */

h1 { font-size: 22px; margin: 0 0 6px; }       /* 26→22, 8→6 */
h2 { font-size: 16px; margin: 18px 0 8px;       /* 28→18, 12→8 */
     border-bottom: 2px solid #00A1E0; padding-bottom: 4px; }  /* 6→4 */
h3 { font-size: 13px; margin: 10px 0 5px; }    /* 16→10, 8→5 */
p, li { font-size: 11px; margin: 4px 0; }      /* 명시적으로 작게 */
table { margin: 6px 0; }                        /* 10→6 */
th, td { padding: 5px 7px; }                    /* 8→5/7 */
.callout { padding: 7px 12px; margin: 8px 0; } /* 10/14 → 7/12, 12→8 */
ul { padding-left: 16px; margin: 4px 0; }       /* 18→16, 명시 */
ul.tight li { margin-bottom: 2px; }             /* 3→2 */
.kpi-grid { gap: 6px; margin: 8px 0; }          /* 8→6, 12→8 */
.kpi-card { padding: 8px; }                     /* 10→8 */

/* ========================================================== */
/* 표지(.cover) — wkhtmltopdf 안정 렌더링 보장 룰                 */
/* ========================================================== */
/* ⚠️ 2026-05-14 발견 (CRITICAL): linear-gradient 배경 + 흰색 글자 */
/*    조합이 wkhtmltopdf(QtWebKit) 0.12.x에서 약 50% 확률로 백지로 */
/*    렌더링됨. 푸터만 보이고 표지 전체가 사라지는 현상.            */
/*                                                              */
/* 근본 원인:                                                    */
/*   1) linear-gradient는 QtWebKit 구버전에서 불안정              */
/*   2) print-color-adjust 미설정 시 일부 배경이 인쇄 시 누락       */
/*   3) padding 100mm가 음수 margin과 조합되며 box model 깨짐      */
/*                                                              */
/* ✅ 해결: (a) 단색 배경 (b) print-color-adjust:exact 강제        */
/*         (c) 명시적 height (d) <html>·<body>까지 배경 상속        */
/* ========================================================== */

/* (a) 전역 — 인쇄 시 배경색 강제 표시 (모든 요소) */
*, *::before, *::after {
  -webkit-print-color-adjust: exact !important;
  print-color-adjust: exact !important;
  color-adjust: exact !important;
}

/* (b) 표지 — 단색 + 명시적 높이 + 컬러 강제 */
.cover {
  page-break-after: always;
  page-break-inside: avoid;
  background-color: #16325C !important;  /* 단색만 사용 (gradient 금지) */
  color: #ffffff !important;
  text-align: center;
  margin: -12mm -14mm 0 -14mm;
  padding: 90mm 40px 90mm 40px;
  box-sizing: border-box;
  min-height: 250mm;                      /* 명시적 높이 — 빈 페이지 방지 */
}

/* 표지 안 자식 요소도 흰색 명시 (상속이 wkhtmltopdf에서 가끔 끊김) */
.cover * { color: #ffffff !important; }

/* 표지 다음 콘텐츠 앞에 명시적 페이지 분리 div 필수
   HTML: <div style="page-break-before: always;"></div> */
```

### 🚨 표지 렌더링 안전 체크리스트 (PDF 생성 후 반드시 검증)
**모든 PDF 생성 후 sips로 표지를 PNG로 추출하여 시각 확인하라.** 학습 룰 (2026-05-14):
```bash
# 표지 진단 (필수)
sips -s format png "{생성된PDF}" --out /tmp/_cover_check.png 2>&1 | tail -1
# Read 도구로 /tmp/_cover_check.png 보고 백지 여부 확인
```
- [ ] 표지에 제목·부제·작성일이 보이는가? (백지면 즉시 재시도)
- [ ] 배경색이 #16325C 또는 의도한 색으로 채워져 있는가?
- [ ] 푸터만 보이는 빈 페이지가 아닌가?

### 표지에서 절대 쓰지 말 것 (학습된 금지 패턴)
| ❌ 금지 | ✅ 사용 |
|---|---|
| `background: linear-gradient(...)` | `background-color: #16325C` 단색 |
| `height: 100vh` | `min-height: 250mm` 명시 |
| 흰 글자만 (배경 없이) | 흰 글자 + 단색 배경 + `!important` |
| 표지 안에서 부모 색상 상속 의존 | 자식 요소 모두 `color:#fff !important` 명시 |

### 3. pagebreak 룰 (필수)
- `class="pagebreak"`는 **꼭 필요한 큰 챕터 구분에만**. 남발 금지.
- h2가 5개면 pagebreak는 1~2개로 충분. 콘텐츠가 짧은 섹션은 같은 페이지에 묶어라.
- 자가 점검: *"이 섹션이 1페이지의 1/3도 안 채우면서 다음 페이지로 넘어가는가?"* → Yes면 pagebreak 제거

### 4. 콘텐츠 밀도 룰
- 짧은 단락은 묶어서 표 하나로.
- callout 안에 `<br>` 줄바꿈 최소화.
- 테이블 행 5개 이상이면 `font-size: 10px`로 한 단계 축소.
- 두 컬럼 비교(.col2)로 좌우 배치하여 세로 공간 절약.

### 5. 검증 체크리스트
PDF 생성 후 다음 자가 점검:
- [ ] 첫 본문 페이지에서 h2 + h3 1개 + 표/단락 1개 이상 같이 보이는가?
- [ ] pagebreak 직후 절반도 안 채운 페이지 없는가?
- [ ] 표지 제외 페이지 수가 콘텐츠 분량 대비 합리적인가? (밀도 30~50%)
- [ ] 상하 여백이 좌우보다 작게 느껴지는가? (반대면 룰 위반)

## PDF 변환 도구 우선순위 (한글 렌더링 보장)

### ⚠️⚠️ 한글 본문 겹침 버그 — Chrome 우선 (2026-06-24 추가, CRITICAL)
**대표님 지적: wkhtmltopdf로 만든 보고서 본문 한글이 자간 0으로 뭉쳐 글자가 겹쳐 보임.**
- 원인: wkhtmltopdf(QtWebKit)의 고질적 한글 자간 렌더링 버그. 표지(큰 글자)·영문은 OK지만 **본문 11px 한글이 겹침**.
- **해결: 한글 본문이 많은 보고서는 Chrome headless로 렌더링**(겹침 없음, 자간 정확):
  ```bash
  CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
  "$CHROME" --headless --disable-gpu --no-pdf-header-footer \
    --print-to-pdf="./docs/{주제}_{YYMMDD}.pdf" "file://{절대경로 input.html}"
  ```
  - `--no-pdf-header-footer`: Chrome 기본 머리/꼬리말 제거. 페이지번호·푸터는 CSS `@page`/HTML로 넣을 것(wkhtmltopdf의 `--footer-center`는 Chrome에서 안 먹음).
  - 표지 단색배경(linear-gradient 금지) 룰은 Chrome에선 무관하나 유지해도 무방.
  - 보조: HTML에 `body { letter-spacing: 0.02em; word-spacing: 0.05em; }` 추가하면 더 안전.
- **검증 필수**: 생성 후 `"$CHROME" --headless --screenshot=/tmp/x.png "file://input.html"` 로 본문 캡처 → Read로 겹침 없는지 확인.

### 도구 우선순위
1. **Chrome headless `--print-to-pdf`** — 한글 본문 보고서 **1순위**(겹침 없음). 위 명령 사용.
2. `wkhtmltopdf` — 영문 위주 또는 Chrome 불가 시. 한글 본문 다량이면 겹침 위험(피할 것).
3. fallback: `pandoc + xelatex` / `weasyprint` / `reportlab`

## 디자인 (SLDS 스타일)

- **메인 컬러**: Salesforce Blue `#00A1E0`
- **중립 배경**: `#F3F2F2`
- **강조 텍스트**: `#16325C`
- **폰트**: 한글 — Apple SD Gothic Neo / 영문 — system-ui

### 검증된 디자인 패턴 (v0.7-alpha 보고서에서 효과 확인)

#### KPI 그리드 (4열)
```html
<div class="kpi-grid">
  <div class="kpi-card">
    <div class="kpi-label">레이블</div>
    <div class="kpi-value">값</div>
    <div class="kpi-sub">부가 설명</div>
  </div>
  ...
</div>
```

#### Callout 4종 (상하 7~12px padding 엄수)
- `.callout-info` (border-left: #00A1E0) — 정보
- `.callout-success` (border-left: #10B981) — 완료
- `.callout-warn` (border-left: #F59E0B) — 주의
- `.callout-danger` (border-left: #EF4444) — 위험

#### Badge 6종
- `.b-blue / .b-green / .b-yellow / .b-red / .b-gray / .b-purple`
- 표 안의 상태 표시에 활용

#### 두 컬럼 비교
```html
<div class="col2">
  <div>좌측 콘텐츠</div>
  <div>우측 콘텐츠</div>
</div>
```
→ 세로 공간 절약 + 비교 가독성 ↑

## 필수 페이지 구성

```
1. 표지 페이지 (제목 + 부제 + 작성일 + 작성자)
2. 목차 (TOC) — 짧으면 표지 다음 페이지 윗부분에 압축
3. 본문 (섹션별, pagebreak 남발 금지)
4. 푸터: 페이지 번호 (모든 페이지)
```

## 실행 순서

1. 사용자 요청에서 주제 추출 → 파일명 결정
2. HTML 또는 MD로 본문 초안 작성 (SLDS 톤 + 한글 가독성 + **상하 여백 최소화 CSS**)
3. wkhtmltopdf로 PDF 변환:
   ```bash
   wkhtmltopdf \
     --enable-local-file-access \
     --javascript-delay 800 \
     --no-stop-slow-scripts \
     --print-media-type \
     --background \
     --margin-top 12mm --margin-bottom 12mm \
     --margin-left 14mm --margin-right 14mm \
     --footer-center "{보고서명} · [page]/[topage]" \
     --footer-font-size 8 --footer-spacing 6 \
     --footer-font-name "Apple SD Gothic Neo" \
     --image-quality 90 --image-dpi 150 \
     --encoding utf-8 \
     {input.html} ./docs/{주제}_{YYMMDD}.pdf
   ```
   ⚠️ `--background` 플래그 누락 시 표지 배경색이 빠져 흰 종이에 흰 글자(=백지)로 보임. 필수.
   ⚠️ `./docs/`가 없으면 먼저 `mkdir -p docs` 실행. 프로젝트 밖(git 저장소 아님)일 때만 `~/Downloads/`로 폴백.
4. 변환 실패 시 → fallback 순서대로 자동 시도
5. 성공 시 → `open ./docs/{주제}_{YYMMDD}.pdf`
6. 대표님께 경로 + 페이지 수 + 미리보기 자동 오픈 보고
7. **자가 점검**: 페이지 수가 콘텐츠 대비 과다한지 확인 (밀도 < 30%면 갭 룰 위반)
8. **아카이빙 (대표님 확정 2026-07-02)**: PDF 완성·보고 후 실행. **PDF만 이동, HTML은 로컬 유지**.
   ```bash
   python3 ~/.claude/skills/report-pdf-builder/scripts/archive_report.py <pdf경로> [프로젝트명]
   ```
   - **HTML(편집 소스)은 로컬 `./docs/`에 그대로 둔다** — 수정 재생성의 원본이므로 절대 삭제·이동 X. 이 스크립트는 PDF만 받는다.
   - **PDF만** rclone moveto로 구글드라이브 **프로젝트별 폴더**(`Project/SMG/보고서`, `Project/XimTier/보고서`… 파일명 자동 라우팅, 미매칭 시 `Document/보고서`)로 이동. **같은 이름이면 덮어쓰기(최신본 1개만)**.
   - **옵시디언**: `📥아카이브/보고서/`에 메타+요약+링크 노트 (같은 이름이면 갱신).
   - 사전 요구: `rclone gdrive:` 인증. 프로젝트 추정 애매하면 프로젝트명 인자로.
   - 검증 실패 시 중단·보고. 로컬 PDF 삭제 전 원격 도착 확인.

### 보고서 수정 워크플로우 (재생성)
"이 보고서 수정해줘" 요청 시: **로컬 `./docs/`의 HTML을 편집** → PDF 재생성(3~5단계) → 8단계로 새 PDF만 이동(덮어씀). HTML이 로컬에 있으니 구글드라이브에서 되받을 필요 없음. PDF는 항상 최신본 1개로 갱신.

## 자가 점검 체크리스트

- [ ] PDF 파일이 실제로 `~/Downloads/`에 생성됐는가?
- [ ] 한글이 깨지지 않는가? (wkhtmltopdf로 변환 후 시각 확인)
- [ ] 표지/목차/본문/푸터 4요소 갖춰졌는가?
- [ ] `open` 명령으로 미리보기 자동 노출했는가?
- [ ] 중간 HTML/MD가 사용자 작업 디렉터리를 더럽히지 않는가? (/tmp 또는 docs/)
- [ ] **상하 여백이 12mm로 설정되어 첫 본문 페이지가 충분히 밀도 있는가?**
- [ ] **pagebreak가 남발되어 빈 공간 페이지가 생기지 않았는가?**
- [ ] **콘텐츠 밀도 30~50% 이상 (반페이지 이상)인가?**
- [ ] **아카이빙: PDF를 구글드라이브 프로젝트 폴더로 이동하고 옵시디언 노트를 생성했는가? (로컬 원본 삭제 확인)**

## 위반 사례 (피해야 할 패턴)

❌ 상하 마진 18~20mm — 한 페이지에 들어갈 콘텐츠가 다음 페이지로 넘어감
❌ h2마다 pagebreak — 9페이지짜리가 13페이지 됨
❌ p 사이 line-height 1.7+ — 줄 간격이 너무 넓어 정보 밀도 낮음
❌ ul li 사이 margin 8px+ — 리스트가 세로로 길어짐
❌ callout padding 16px+ — 박스 안 텍스트가 작은데 박스만 큼
❌ **표지에 `height: 100vh` 사용** — wkhtmltopdf에서 페이지 높이로 계산 안 됨, 표지가 찌그러져 다음 콘텐츠와 합쳐짐
   → 해결: padding-top/bottom 100mm + 표지 다음에 `<div style="page-break-before: always;"></div>` 명시

## 좋은 사례 (v0.7-alpha 보고서)

✅ 마진 12mm × 14mm — 콘텐츠 면적 +25%
✅ pagebreak 4개만 (9페이지 / 표지 1 + 본문 7챕터) — 적절
✅ KPI 8개를 4×2 그리드로 한 페이지에 — 공간 효율 ↑
✅ table padding 5px/7px — 정보 밀도 ↑
✅ ul.tight 클래스로 빠른 리스트
