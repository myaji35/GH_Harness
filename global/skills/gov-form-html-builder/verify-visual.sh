#!/usr/bin/env bash
# gov-form-html-builder — 육안검사 강제 스크립트
# PDF를 페이지별 PNG로 렌더하고, Claude가 각 PNG를 Read로 열어보도록 경로를 출력한다.
# "페이지 수만 맞음"으로 완료 보고하는 실수를 구조적으로 차단한다.
#
# 사용법:
#   verify-visual.sh <pdf경로> [출력디렉토리] [dpi]
#   verify-visual.sh 심티어_설립등기신청서_최종.pdf              # 기본 scratchpad, 100dpi
#   verify-visual.sh out.pdf /tmp/chk 120
#
# 종료코드: 0=렌더성공(육안확인 대기), 1=입력오류/렌더실패
set -euo pipefail

PDF="${1:-}"
if [[ -z "$PDF" || ! -f "$PDF" ]]; then
  echo "❌ PDF 경로가 없거나 파일이 없습니다: '$PDF'" >&2
  echo "   사용법: verify-visual.sh <pdf> [출력디렉토리] [dpi]" >&2
  exit 1
fi

# 출력 디렉토리: 인자 > SCRATCHPAD 환경변수 > PDF와 같은 위치의 .verify
OUTDIR="${2:-${SCRATCHPAD:-$(dirname "$PDF")/.verify}}"
DPI="${3:-100}"
mkdir -p "$OUTDIR"

BASE="$(basename "${PDF%.*}")"
PREFIX="$OUTDIR/vchk-$BASE"

# 기존 렌더 정리(같은 prefix만)
rm -f "$PREFIX"-*.png 2>/dev/null || true

if ! command -v pdftoppm >/dev/null 2>&1; then
  echo "❌ pdftoppm 없음 → 'brew install poppler' 필요" >&2
  exit 1
fi

pdftoppm -png -r "$DPI" "$PDF" "$PREFIX" >/dev/null 2>&1

# 페이지 수
NPAGES=$(ls "$PREFIX"-*.png 2>/dev/null | wc -l | tr -d ' ')
if [[ "$NPAGES" -eq 0 ]]; then
  echo "❌ 렌더 실패: PNG가 생성되지 않음" >&2
  exit 1
fi

# PDF 메타 페이지 수(macOS) — 참고용
META_PAGES=""
if command -v mdls >/dev/null 2>&1; then
  META_PAGES=$(mdls -name kMDItemNumberOfPages -raw "$PDF" 2>/dev/null || echo "")
fi

echo "════════════════════════════════════════════════════════════"
echo " 육안검사 대상: $BASE  (${NPAGES}장 렌더 완료, ${DPI}dpi)"
[[ -n "$META_PAGES" ]] && echo " PDF 메타 페이지수: $META_PAGES"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "▶ 다음 PNG를 반드시 Read 도구로 하나씩 열어 육안 확인할 것:"
ls "$PREFIX"-*.png | sort | sed 's/^/   /'
echo ""
echo "▶ 각 페이지에서 확인할 항목 (하나라도 실패면 수정 후 재검사):"
cat <<'CHECK'
   [1] 표 칸선(테두리)이 모든 항목에 보이는가? — 텍스트만 떠 있으면 border 누락 (실패)
   [2] 라벨과 값이 같은 줄에 정렬되는가? — 라벨 가운데뜨고 값 어긋나면 (실패)
   [3] 하단 공백이 30% 이상인가? — 위만 차고 아래 비면 행 높이(mm) 재산정 (실패)
   [4] 상단 여백 ≈ 하단 여백인가? (여백 균형) — 위는 딱 붙고 아래만 크게 비거나 그 반대면 (실패)
       → @page margin 상하 대칭 확인, 콘텐츠를 세로 중앙/균등 배치
   [5] 페이지 경계에서 표/글자가 잘렸는가? — 절림 있으면 (실패)
   [6] 예정한 데이터(날짜·이름·금액)가 실제로 찍혔는가? — 값 확인 (실패 시 데이터 오류)
   [7] 굴림체(고딕)인가? — 명조/바탕이면 (실패)
CHECK
echo ""
echo "⚠️  이 스크립트는 렌더만 한다. PNG를 Read로 보지 않고 '완료' 보고 금지."
echo "════════════════════════════════════════════════════════════"
