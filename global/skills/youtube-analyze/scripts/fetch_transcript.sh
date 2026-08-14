#!/usr/bin/env bash
# fetch_transcript.sh — YouTube URL → 자막(텍스트) + 메타데이터(JSON)
# 의존성: yt-dlp (필수). 별도 파이썬 패키지 불필요.
#
# 사용법:
#   fetch_transcript.sh <youtube_url> [out_dir] [lang_pref]
#     lang_pref 기본값: "ko,en"  (콤마 구분, 앞에서부터 우선)
#
# 산출물 (out_dir, 기본 /tmp/yt-<videoid>):
#   meta.json        — 제목/채널/길이/조회수/업로드일/설명
#   transcript.txt   — 타임스탬프 제거된 순수 본문 (요약용)
#   transcript.vtt   — 원본 자막 (타임스탬프 포함, 인용/구간참조용)
#
# 종료코드: 0 성공, 2 자막없음, 3 yt-dlp없음, 4 URL오류

set -euo pipefail

URL="${1:-}"
LANG_PREF="${3:-ko,en}"

if [[ -z "$URL" ]]; then
  echo "ERROR: YouTube URL이 필요합니다." >&2
  echo "usage: fetch_transcript.sh <url> [out_dir] [lang_pref]" >&2
  exit 4
fi

if ! command -v yt-dlp >/dev/null 2>&1; then
  echo "ERROR: yt-dlp 미설치. 설치: brew install yt-dlp (또는 pip install yt-dlp)" >&2
  exit 3
fi

# 비디오 ID 추출 (out_dir 기본값 구성용)
VID="$(yt-dlp --no-warnings --get-id "$URL" 2>/dev/null | head -1 || true)"
[[ -z "$VID" ]] && VID="video"
OUT_DIR="${2:-/tmp/yt-$VID}"
mkdir -p "$OUT_DIR"

echo ">> 메타데이터 수집 중..." >&2
# 메타데이터 (자막은 별도). %(...)j 로 단일 JSON 필드 추출
yt-dlp --no-warnings --skip-download \
  --print '{"id":%(id)j,"title":%(title)j,"channel":%(channel)j,"duration":%(duration)j,"duration_string":%(duration_string)j,"view_count":%(view_count)j,"like_count":%(like_count)j,"upload_date":%(upload_date)j,"webpage_url":%(webpage_url)j,"description":%(description)j}' \
  "$URL" > "$OUT_DIR/meta.json" 2>/dev/null || {
    echo "ERROR: 메타데이터 수집 실패 (URL 또는 네트워크 확인)" >&2
    exit 4
  }

echo ">> 자막 다운로드 중 (lang: $LANG_PREF)..." >&2
# 수동자막 우선, 없으면 자동생성자막. 언어 폴백.
# VTT를 받아서 텍스트로 정제.
SUB_LANGS="$(echo "$LANG_PREF" | sed 's/,/,/g')"

# 1차: 사용 가능한 자막을 받아온다 (수동 → 자동 순으로 yt-dlp가 처리)
yt-dlp --no-warnings --skip-download \
  --write-subs --write-auto-subs \
  --sub-langs "$SUB_LANGS" \
  --sub-format vtt \
  --convert-subs vtt \
  -o "$OUT_DIR/sub.%(ext)s" \
  "$URL" >/dev/null 2>&1 || true

# 받아진 vtt 파일 찾기 (sub.ko.vtt / sub.en.vtt 등)
VTT_FILE="$(ls "$OUT_DIR"/sub*.vtt 2>/dev/null | head -1 || true)"

if [[ -z "$VTT_FILE" ]]; then
  echo "WARN: 지정 언어($LANG_PREF) 자막 없음. 전체 언어 재시도..." >&2
  yt-dlp --no-warnings --skip-download \
    --write-subs --write-auto-subs \
    --sub-langs "all" \
    --sub-format vtt --convert-subs vtt \
    -o "$OUT_DIR/sub.%(ext)s" \
    "$URL" >/dev/null 2>&1 || true
  VTT_FILE="$(ls "$OUT_DIR"/sub*.vtt 2>/dev/null | head -1 || true)"
fi

if [[ -z "$VTT_FILE" ]]; then
  echo "NO_TRANSCRIPT: 이 영상에는 사용 가능한 자막이 없습니다." >&2
  echo "  → 음성 STT가 필요합니다 (이 스크립트 범위 밖)." >&2
  exit 2
fi

cp "$VTT_FILE" "$OUT_DIR/transcript.vtt"

# VTT → 순수 텍스트 (타임스탬프/태그/중복줄 제거)
# WEBVTT 헤더, 시간줄(-->), 위치태그(<...>), 빈줄 제거 후 연속 중복 제거
awk '
  /^WEBVTT/ {next}
  /^Kind:/ {next}
  /^Language:/ {next}
  /-->/ {next}
  /^[[:space:]]*$/ {next}
  /^[0-9]+$/ {next}
  {
    gsub(/<[^>]*>/, "");        # 인라인 타이밍 태그 제거
    gsub(/&nbsp;/, " ");
    line=$0;
    if (line != prev) { print line; prev=line }   # 자동자막 중복줄 제거
  }
' "$OUT_DIR/transcript.vtt" > "$OUT_DIR/transcript.txt"

WORDS="$(wc -w < "$OUT_DIR/transcript.txt" | tr -d ' ')"
echo ">> 완료: $OUT_DIR" >&2
echo "   meta.json / transcript.txt (${WORDS} words) / transcript.vtt" >&2
echo "$OUT_DIR"
