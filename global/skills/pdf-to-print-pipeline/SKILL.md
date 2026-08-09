---
name: pdf-to-print-pipeline
description: HTML을 정확하고 안정적으로 PDF로 출력한다. Chrome 헤드리스(레이아웃 정확)와 wkhtmltopdf(빠름) 자동 선택, 멈춤·중복프로세스·페이지분할·한글폰트 문제 회피. 트리거 "PDF로 출력", "HTML을 PDF로", "인쇄용 PDF 만들어", "PDF 변환".
trigger: /pdf-to-print-pipeline
---

# /pdf-to-print-pipeline

HTML → PDF를 **레이아웃이 깨지지 않게, 멈추지 않게** 출력하는 파이프라인.
macOS 기준. 표 정렬·flex·페이지분할이 정확해야 하는 양식/보고서 출력에 적합.

## 엔진 선택 규칙

| 상황 | 엔진 | 이유 |
|------|------|------|
| flex·grid·`page-break-inside:avoid`·정밀 정렬 | **Chrome 헤드리스** ⭐ | CSS 정확히 렌더 |
| 단순 표·텍스트, 빠른 출력 | wkhtmltopdf | 가볍고 빠름 |
| flex 우측정렬·페이지분할 깨짐 발견 | **Chrome으로 전환** | wkhtmltopdf는 flex/page-break 약함 |

> **교훈: wkhtmltopdf는 flex `space-between`(우측정렬)과 `page-break-inside:avoid`를 제대로 못 한다.** 양식류는 Chrome 우선. 단 HTML은 flex 대신 table로 짜두면(→ `gov-form-html-builder`) 양쪽 다 안전.

## Chrome 헤드리스 — 멈춤 방지 핵심

> **교훈: Chrome 헤드리스가 자주 멈추거나(timeout) 프로필 잠금 충돌(ProcessSingleton)로 실패한다.**

```bash
# 1) 이전 프로세스 정리 (필수)
pkill -9 -f "chrome.*headless" 2>/dev/null; sleep 1

# 2) 고유 프로필 + timeout + --headless=new
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
PROFILE="<scratchpad>/cr-$(date +%s 2>/dev/null || echo x)"   # 매번 고유
rm -rf "$PROFILE" 2>/dev/null

timeout 90 "$CHROME" --headless=new --disable-gpu --no-sandbox --no-pdf-header-footer \
  --user-data-dir="$PROFILE" \
  --print-to-pdf="<출력>.pdf" \
  "file://<입력>.html" 2>&1 | tail -1
```
- `--headless=new` (구 `--headless`보다 안정)
- `--user-data-dir` 매번 **고유 경로** (잠금 충돌 회피)
- `timeout 90`으로 무한 대기 방지
- GPU/network 크래시 로그(`exit_code=15` 등)는 무시 가능 — PDF 생성되면 성공

## wkhtmltopdf — 양식용 옵션
```bash
wkhtmltopdf --enable-local-file-access \
  --page-size A4 \
  --margin-top 6mm --margin-bottom 6mm --margin-left 6mm --margin-right 6mm \
  --encoding utf-8 --disable-smart-shrinking \
  "<입력>.html" "<출력>.pdf"
```
- `--enable-local-file-access` 없으면 로컬 CSS/이미지 무시됨
- 여백 작게(6mm) 양식 살림

### CLI 마진 옵션과 내장 @page 이중 적용 금지 ⭐
> **교훈: HTML `@media print`에 이미 `@page { size:A4; margin:14mm 0 }` 같은 마진 규칙이 있는데 CLI에도 `--margin-top/--margin-bottom`을 주면 마진이 이중 적용되어 내용이 밀려나고 페이지 분할이 깨진다** (10페이지 문서가 9페이지로 나오며 마지막 서식이 통째로 사라진 사례). HTML이 자체 `@page`를 갖고 있으면 CLI 마진 옵션을 **빼고** `--print-media-type`으로 `@media print` CSS를 강제 적용한다.
```bash
# 마진 옵션 없음 + print-media-type 강제 (HTML 내장 @page 사용)
wkhtmltopdf --enable-local-file-access --encoding UTF-8 --print-media-type input.html output.pdf
```
> 페이지 병합 방지는 각 페이지 블록에 `page-break-after: always; page-break-inside: avoid; break-after: page`를 강제하고, flex 표지는 인쇄 시 `display:block`으로 바꾼다(→ `gov-form-html-builder` 12번).

**렌더 후 검증 (필수)**
```bash
mdls -name kMDItemNumberOfPages -raw out.pdf   # 페이지 수 = HTML .page 블록 수 확인
pdftoppm -png -r 60 out.pdf prefix             # 이미지 뽑아 페이지 경계 절림 육안 확인
```
> "페이지 수만 맞음"으로 완료 보고 금지 — 경계에서 내용이 잘리는지 이미지로 눈으로 확인.

## 페이지 수 검증 (원본과 일치 확인)
```bash
python3 -c "
import re
d=open('<출력>.pdf','rb').read()
print('페이지 수:', len(re.findall(rb'/Type\s*/Page[^s]', d)))
"
```
> 양식이 의도한 페이지 수(예: 3장)와 다르면 → page-break CSS 조정 후 Chrome 재출력.

## 한글 폰트
- Chrome: 시스템 폰트 자동 사용(굴림/맑은고딕 정상)
- wkhtmltopdf: `--encoding utf-8` + HTML에 `<meta charset="UTF-8">` 필수

## 워크플로우
1. HTML 레이아웃 성격 판단 → 엔진 선택(flex/정밀 = Chrome)
2. 이전 chrome 프로세스 정리 → 고유 프로필로 출력
3. 페이지 수 검증
4. 출력 후 `open <pdf>`로 사용자 확인
5. 깨짐/페이지수 불일치 → HTML(또는 인쇄 CSS) 수정 후 재출력

## 자가 점검
- [ ] flex/page-break 있으면 Chrome 사용했는가
- [ ] chrome 이전 프로세스 정리 + 고유 프로필 사용
- [ ] 페이지 수가 원본 의도와 일치
- [ ] 한글 깨짐 없음(charset/encoding)
- [ ] 출력 후 open으로 확인

## 관련 스킬
- [[gov-form-html-builder]] — flex 대신 table로 짜면 양 엔진 호환
- [[corp-registration-form]] — 등기서류 최종 PDF 출력
