---
name: gov-form-html-builder
description: 정부·법원 양식 PDF를 가감 없이(포맷·서체·크기 그대로) HTML로 정밀 재현한다. 칸선 정렬·우측정렬·페이지분할·굴림체·셀폭 통일 등 검증된 규칙 라이브러리. 트리거 "양식 그대로 HTML로", "정부양식 재현", "등기/신청서 양식 만들어", "빈양식 HTML".
trigger: /gov-form-html-builder
---

# /gov-form-html-builder

정부·법원 공문서 양식을 **포맷·서체·크기를 가감 없이** HTML로 재현하는 규칙 모음.
한 번 만들고 끝이 아니라, 칸선 어긋남·정렬·페이지분할에서 반복 재작업이 발생하는 영역 → 아래 규칙으로 처음부터 정확히.

## 핵심 원칙

0. **⚠️ 무난한 양식을 건드리지 마라 (최우선·2026-07-08 사고)** — 이미 칸선·정렬·데이터가 멀쩡한 양식 HTML이 있으면, **CSS를 새로 짜지 말고 그 파일을 그대로 복제해 데이터만 교체**한다.
   - 실제 사고: 무난했던 `양식분리.html`(`.sheet` 구조)을 두고, "A4 꽉 채우기·여백 개선"한답시고 별도 신청서에 `.page{height:297mm}`·`min-height`·`flex space-between`·`행 mm높이`를 **매 작업마다 새로 도입 → 그때마다 칸선 누락/하단 공백/절림이 새로 터짐.** 3번 연속 깨뜨리고서야 원본 복제로 해결.
   - **판단 순서**: (1) 무난한 기존본이 있나? → 있으면 **복제 후 데이터만 수정**하고 CSS는 손대지 않는다. (2) "더 꽉 채우자/여백 균형 맞추자"는 요구가 와도, **기존이 무난하면 원본 특성(예: 마지막 항목 뒤 공백)으로 설명하고 CSS 개조는 최후수단**. Karpathy #3 Surgical Changes 위반 금지.
   - 굳이 개조해야 하면 **기존본 복사본에서** 실험하고, 매 변경마다 §육안검사로 칸선·정렬이 안 깨졌는지 확인한 뒤에만 반영.

1. **가감 없이** — 표 구조·테두리·항목번호·칸 병합을 원본 그대로. 임의 줄바꿈·컬럼폭 확대 금지.
2. **빈양식 ↔ 작성예시 분리** — 작성예시값은 토글로 숨길 수 있게(`display:none`, font-size:0 아님).
3. **PDF 출력 호환** — flex보다 table, page-break 제어. (`pdf-to-print-pipeline` 참고)
4. **육안검사 없이 완료 없음** — PDF 생성/업로드 후 반드시 `verify-visual.sh`로 페이지별 PNG를 뽑아 `Read`로 직접 보고, **상·하단 여백 균형**·칸선·정렬·공백을 눈으로 확인한다. (§육안검사) "페이지 수 맞음"·"렌더됨"은 완료가 아니다.

## 검증된 규칙 (각각이 실제 시행착오에서 도출됨)

### 1. 폰트 — 한국 공문서는 굴림체
```css
font-family: "Gulim", "굴림", "Dotum", "돋움", "Malgun Gothic", sans-serif;
```
> 바탕(명조/serif)으로 착각 주의. 원본 글자가 부리 없고 획 균일 = 고딕(굴림).

### 2. 표 칸선 정렬 — 별개 표를 합치거나 colgroup 고정
- **여러 `<table>`로 나뉘면 라벨 열 폭이 제각각** → 같은 표로 합치거나 `<colgroup>`으로 첫 열 폭 px 고정.
```html
<table class="form items">
  <colgroup><col style="width:160px"><col></colgroup>
  ...
</table>
```
> `table-layout: fixed`에서 **첫 행 셀이 열 폭 결정**. 첫 행이 colspan 헤더면 폭 기준이 없어 다음 행이 콘텐츠대로 벌어짐 → colgroup 필수.

### 3. 셀 폭은 px 고정 대신 % (합계 100%)
> px 합이 표 폭과 안 맞으면 마지막 칸이 오버행(삐져나옴). 비율 %로 합 100% 맞춤.
```html
<th style="width:14%">접수</th><td style="width:34%">...</td>...  <!-- 합 100 -->
```

### 4. 중앙선 정렬 — colspan으로 경계 일치
> "지방교육세 우측선 = 세액합계 우측선 = 첨부서면 중앙선(50%)" 같은 정렬 요구 시:
> colgroup 6열을 잡고 col1+col2+col3 = 50%가 되게 한 뒤, 병합 셀의 colspan으로 경계를 50%에 맞춤.

### 5. 라벨 칸 침범 방지 — 자간·글자크기 축소(전체 폰트 유지)
```css
table.fee .label { letter-spacing: 0; font-size: 12.5px; white-space: nowrap; }
table.fee th, table.fee td { padding: 6px 2px; }
```

### 6. 우측 정렬("통"만 우측) — flex 금지, table 사용
> flex `justify-content:space-between`은 wkhtmltopdf에서 깨짐. table 레이아웃이 모든 엔진 호환.
```css
table.doc-line { width:100%; table-layout:fixed; border:none !important; }
table.doc-line td { border:none !important; padding:0 !important; }
td.name { text-align:left; } td.cnt { text-align:right; width:36px; }
```
> 주의: `table.form td`의 테두리 규칙이 상속되면 항목마다 칸선 생김 → `border:none !important`로 차단.

### 7. 선 없는 영역(신청인란 등) — 한 셀 + 내부 div
> 원본에 내부 가로·세로선이 없으면, 행마다 th/td로 나누지 말고 **하나의 셀** 안에 flex/div로 배치.

### 8. 라벨 줄바꿈은 원본대로 명시
```css
.label { white-space: nowrap; }
.label.multiline { white-space: pre-line; }   /* 원본 줄바꿈 \n 보존 */
```

### 9. 제목 박스 자간 — nowrap으로 한 줄 보장
> letter-spacing 과하면 제목이 줄바꿈됨. 폭 넉넉히 + `white-space: nowrap`.

### 10. 빈양식 모드 — 예시값 완전 제거(자리 안 남김)
```css
body.hide-sample span.sample { display: none; }      /* 자리·줄바꿈 제거 */
body.hide-sample td.sample { font-size: 0; }          /* 셀=예시면 텍스트만 */
body.hide-sample .multiline { white-space: normal; }
body.hide-sample .tall td { height: auto; }           /* 인위적 칸높이 해제 */
```
> 투명(transparent) 처리는 자리가 남아 칸이 늘어남 → display:none.

### 11. 페이지 꽉 채우기 — 행 높이는 mm 실측(vh/% 금지)
> **먼저 판단: 정말 채워야 하나?** 관공서 신청서는 원본부터 마지막 항목(예 ⑯기타·⑩목적) 뒤 하단이 비는 게 정상이다. **기존 양식이 무난하면 하단 공백을 "원본 특성"으로 두고 CSS를 건드리지 않는다**(§핵심원칙 0). 억지로 채우려다 칸선/정렬을 깨뜨린 사고가 반복됨. 채움은 사용자가 "칸을 키워 꽉 채워라"고 명시했을 때만.
> 채우기로 했다면 — 한 페이지에 칸이 위쪽만 차고 아래 비면, 인쇄 시 각 행에 실측 높이(mm)를 직접 준다.
> **교훈(2026-07-08): `table{height:vh}` + `tr{height:%}`는 wkhtmltopdf에서 불안정하게 무시되어 하단 30~50%가 빈 채로 나온다.** 표 전체 vh/% 대신 각 `th/td`에 mm 높이를 직접 지정해야 확실히 채워진다. (A4 콘텐츠 영역 ≈ 269mm ÷ 행수로 산정, 마지막 행 여백은 정상)
```css
@media print {
  /* ✅ 안정: 각 셀에 mm 실측 (6행 → 약 41mm씩) */
  table.p2fill tr:not(.sec-row) th,
  table.p2fill tr:not(.sec-row) td { height: 41mm; }
  /* ❌ 불안정: table{height:88vh} / tr{height:16%} — wkhtmltopdf가 무시함 */
}
```
> page-break-before/after 중복은 빈 페이지 생성 → 한쪽만 사용.

> **⚠️ `.page`는 `height` 고정 금지 → `min-height`만.** `.page{height:297mm; overflow:hidden}`으로 물리 높이를 강제하면, 내용이 부족한 페이지는 하단이 통째로 공백이 되고 내용이 넘치면 잘린다(2026-07-08 설립등기신청서 2페이지 하단 절반 공백 사례). 화면용은 `min-height:269mm`(=297−상하14mm), 인쇄 시 `min-height:0`으로 풀고 여백은 `@page margin`이 담당한다.
```css
.page{ width:210mm; min-height:269mm; padding:14mm 15mm; }   /* height 고정·overflow:hidden 쓰지 말 것 */
@media print{ .page{ min-height:0; padding:0 15mm; } @page{ size:A4; margin:14mm 0; } }
```

### 12. wkhtmltopdf 페이지 분할 — CLI 마진 옵션 금지, 내장 @page 사용
> **교훈: HTML `@media print`에 이미 `@page { margin }` 규칙이 있는데 wkhtmltopdf CLI에도 `--margin-top/--margin-bottom`을 주면 마진이 이중 적용되어 내용이 밀려나고 페이지 분할이 깨진다** (10페이지 문서가 9페이지로 나오며 마지막 서식이 통째로 사라진 사례). CLI 마진 옵션을 빼고 내장 `@page`만 쓰고, `--print-media-type`으로 `@media print` CSS를 강제 적용한다.
```bash
# 마진 옵션 없음 + print-media-type 강제
wkhtmltopdf --enable-local-file-access --encoding UTF-8 --print-media-type input.html output.pdf
```
> 또한 `.page { min-height:1040px }`처럼 화면용 높이가 인쇄 시 `min-height:0`으로 풀리면, 내용 짧은 페이지 2개가 한 장으로 병합된다. 각 페이지 블록에 병합 방지 CSS를 강제한다.
```css
@media print {
  .page { margin:0; page-break-after: always; page-break-inside: avoid; break-after: page; }
  .page:last-child { page-break-after: auto; break-after: auto; }
  @page { size:A4; margin:14mm 0; }
}
```
> `display:flex`인 표지(.cover 등)는 인쇄 시 `display:block`으로 바꾼다(flex가 wkhtmltopdf 페이지 분할과 충돌).
> **⚠️ flex 세로중앙정렬(`justify-content:center`)은 wkhtmltopdf에서 통째로 무시된다(2026-07-08).** 콘텐츠가 페이지 위쪽에 몰리고 하단 40~55%가 빈 채로 나온다. 세로 위치를 잡아야 하면 flex가 아니라 `padding-top: Nmm`으로 직접 내린다(표지는 `padding-top:70mm`로 중앙 근처 배치가 안정적).
> **검증 필수**: `mdls -name kMDItemNumberOfPages -raw out.pdf`로 페이지 수 = `.page` 블록 수 확인 + `pdftoppm -png -r 60 out.pdf prefix`로 이미지 뽑아 페이지 경계 절림 육안 확인. "페이지 수만 맞음"으로 완료 보고 금지.

### 13. 폰트 크기 — 칸을 키우면 글자도 키워라 (밸런스 규칙·2026-07-08)
> **교훈: 규칙11로 칸 높이를 mm로 키워 90% 채웠는데 폰트를 그대로(13px≈9.75pt) 두면, 넓은 칸 안에 작은 글씨가 떠 있어 어색하다.** 대표님이 "양식에 비해 폰트가 너무 작지 않냐"고 직접 지적. 칸을 키우는 채움 작업을 하면 **본문 폰트도 함께 키워 밸런스를 맞춘다.**
> - **관공서 양식 본문 표준 = 15px(약 11pt)**. 13px는 다소 작고, 16px(12pt)는 긴 값(주소·목적)이 줄바꿈될 수 있어 칸 침범 재확인 필요.
> - **키울 대상**: 본문 표(`table.kv`/`table.form`), 리드 문단(`.lead`), 목록(`ol.items`), 서명란(`.sign-row`), 그리고 **인라인 `style="font-size:13px"`로 박힌 본문 단락**(의사록·조사보고서 등).
> - **유지 대상(위계용 보조 텍스트)**: 서식 부제(`.subttl`), 수신처(`.to` 귀중), 표지 메타(`.meta`), 날인란 안내(`.stamp-area` 12px), **compact(1페이지 압축) 페이지 12px** — 여기까지 키우면 위계가 무너지거나 압축이 풀린다.
> - **인라인 폰트 일괄 치환은 정밀하게**: CSS 셀렉터 `p[style*="font-size:13px"]`(매칭 조건)를 건드리면 안 되므로 `style="`로 시작하는 인라인만 대상. perl로 안전 치환:
```bash
# 인라인 style 속성 안의 13px만 15px로 (CSS 셀렉터 p[style*=...]는 style="로 시작 안하므로 보존됨)
perl -i -pe 's/(style="[^"]*?)font-size:13px/${1}font-size:15px/g' form.html
```
> **폰트 키운 뒤 반드시 §육안검사** — 칸 폭 고정된 관공서 표준 양식(등기신청서 등)은 폰트를 키우면 긴 값이 칸을 침범/줄바꿈할 수 있다. 침범 시 해당 서식만 14px로 낮추거나 자간 축소(규칙5)로 대응.

## 워크플로우
1. 원본 PDF를 `Read`(pages)로 정독 → 칸 구조·항목번호·줄바꿈·선 유무 파악
2. 위 규칙으로 HTML 작성 (표는 colgroup, 정렬은 table, 폰트는 굴림)
3. 빈양식/작성예시 토글 + 인쇄 CSS
4. 사용자에게 보여주고, 어긋난 칸은 **해당 항목번호 단위로** 정밀 수정
5. `pdf-to-print-pipeline`으로 PDF 출력 → 페이지 수·정렬 재확인
6. **육안검사(필수·생략금지)** — 아래 「육안검사」 절차 실행. 통과 전 "완료" 보고 금지.
7. **업로드 시**: 업로드 후 원격본을 다시 내려받아 6번 육안검사를 재실행(업로드가 최신본 맞는지 눈으로 확인)

## 육안검사 (VERIFY — 반드시 실행)
> **교훈(2026-07-08): "PDF를 렌더해서 봤다"면서 칸선 누락·정렬 어긋남을 놓치고 "완료"로 보고 → 대표님이 다시 보라 해서야 발각.** 페이지 수만 맞으면 통과로 착각하는 실수를 스크립트로 강제 차단한다.

**실행:**
```bash
# 렌더 + 체크리스트 출력 (SCRATCHPAD 환경변수 있으면 그쪽에, 없으면 PDF옆 .verify/에)
bash "$SKILL_DIR/verify-visual.sh" <생성한.pdf>
# 여러 장이면 각각 실행. 인자2=출력디렉토리, 인자3=dpi(기본100)
```
> `$SKILL_DIR` = 이 스킬 폴더(`~/.claude/skills/gov-form-html-builder`).

**절차 (건너뛰기 금지):**
1. `verify-visual.sh`를 돌려 페이지별 PNG 경로를 받는다.
2. **출력된 모든 PNG를 `Read` 도구로 하나씩 실제로 연다.** (렌더만 하고 안 보면 무의미 — 스크립트가 경고함)
3. 각 페이지에서 스크립트가 출력한 6개 항목 + 폰트 밸런스를 확인:
   칸선 유무 / 라벨·값 정렬 / 하단 공백 30%↑ / 페이지 경계 절림 / 데이터 실제 기입 / 굴림체 / **폰트 밸런스(칸을 mm로 키웠으면 글자도 15px로 커져 넓은 칸과 어울리는가)**
4. **하나라도 실패면** → 해당 원인 규칙(칸선=규칙2·6, 공백=규칙11, 폰트=규칙13, 절림=규칙12)으로 수정 → PDF 재생성 → **1번부터 재검사**.
5. 전 페이지 통과해야 "완료" 보고. 업로드했다면 원격본 재다운로드하여 재검사(§워크플로우 7).

> **금지**: `mdls`로 페이지 수만 확인하고 완료 / PNG를 Read 없이 "정상으로 보임" 보고 / 실패 항목을 "마지막 페이지라 정상"이라 자의적 통과(마지막 페이지 하단 공백만 예외).

## 자가 점검
- [ ] 굴림체 적용
- [ ] 모든 표 칸 폭 합 100% (오버행 없음)
- [ ] 라벨 열 폭이 모든 페이지에서 동일(colgroup)
- [ ] "통" 등 우측정렬은 table(flex 아님), 항목 칸선 없음
- [ ] 빈양식 모드에서 예시값 자리 안 남음
- [ ] 페이지 분할이 원본과 동일(빈 페이지 없음)
- [ ] **칸을 mm로 키워 채웠으면 본문 폰트도 15px(약 11pt)로 키워 밸런스 맞춤**(규칙13). compact·보조 텍스트는 유지
- [ ] flex 세로중앙(`justify-content:center`) 대신 `padding-top` 사용(wkhtmltopdf가 flex 세로중앙 무시)
- [ ] CLI 마진 옵션 없이 렌더(내장 @page 사용), PDF 페이지 수 = .page 블록 수 검증
- [ ] `.page`에 `height` 고정·`overflow:hidden` 없음(min-height만 사용)
- [ ] **`verify-visual.sh` 실행 → 출력된 PNG 전부를 `Read`로 열어 6개 항목(칸선·정렬·공백·절림·데이터·굴림체) 통과** (§육안검사)
- [ ] 업로드한 경우: 원격본 재다운로드하여 육안검사 재실행(바이트/이미지 일치 확인)

## 관련 스킬
- [[corp-registration-form]] — 등기신청서가 이 규칙 사용
- [[pdf-to-print-pipeline]] — HTML→PDF 출력
