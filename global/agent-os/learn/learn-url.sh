#!/bin/bash
# learn-url.sh — URL을 재사용 스킬로 자동 변환 (Agent OS ②)
#
# URL 1개를 받아 콘텐츠를 추출하고, GH_Harness 스킬 규약(frontmatter + 본문)에
# 맞는 SKILL.md를 global/skills/<slug>/ 에 생성한다. 영상2의 /learn 재현.
#
# 사용법:
#   learn-url.sh <URL> [slug]
#     slug 생략 시 자동 생성.
#
# 콘텐츠 추출:
#   - 유튜브(youtube.com/youtu.be) → yt-dlp 자막
#   - 그 외 → curl로 HTML 받아 텍스트화
#
# exit 0 = 스킬 생성, 1 = 사용법 오류, 2 = 콘텐츠 추출 실패, 3 = 의존 도구 없음

set -euo pipefail

HARNESS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SKILLS_DIR="$HARNESS_ROOT/global/skills"
REGISTRY="$HARNESS_ROOT/.claude/issue-db/registry.json"
YT_FETCH="$HOME/.claude/skills/youtube-analyze/scripts/fetch_transcript.sh"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

URL="${1:-}"
SLUG="${2:-}"

if [ -z "$URL" ]; then
  echo "[learn] 사용법: learn-url.sh <URL> [slug]" >&2
  echo "[learn] 예: learn-url.sh https://youtu.be/XXXX" >&2
  exit 1
fi

# --- 콘텐츠 추출 -------------------------------------------------------
CONTENT="$WORKDIR/content.txt"
TITLE=""

if echo "$URL" | grep -qE 'youtube\.com|youtu\.be'; then
  if [ ! -x "$YT_FETCH" ]; then
    echo "[learn] youtube-analyze 스크립트를 찾을 수 없습니다: $YT_FETCH" >&2
    exit 3
  fi
  "$YT_FETCH" "$URL" "$WORKDIR/yt" "en,ko" >/dev/null 2>&1 || {
    echo "[learn] 유튜브 자막 추출 실패 (자막 없는 영상일 수 있음)." >&2
    exit 2
  }
  cp "$WORKDIR/yt/transcript.txt" "$CONTENT"
  TITLE="$(python3 -c "import json;print(json.load(open('$WORKDIR/yt/meta.json')).get('title',''))" 2>/dev/null || echo "")"
else
  if ! command -v curl >/dev/null 2>&1; then
    echo "[learn] curl 이 필요합니다." >&2
    exit 3
  fi
  curl -fsSL --max-time 30 "$URL" 2>/dev/null > "$WORKDIR/raw.html" || {
    echo "[learn] URL 접근 실패: $URL" >&2
    exit 2
  }
  # 간단 텍스트화: 스크립트/스타일 제거 후 태그 제거
  if ! python3 - "$WORKDIR/raw.html" "$CONTENT" 2>/dev/null <<'PY'
import re, sys
html = open(sys.argv[1], encoding="utf-8", errors="ignore").read()
html = re.sub(r'<(script|style)[^>]*>.*?</\1>', ' ', html, flags=re.S|re.I)
m = re.search(r'<title[^>]*>(.*?)</title>', html, flags=re.S|re.I)
title = re.sub(r'\s+', ' ', m.group(1)).strip() if m else ""
text = re.sub(r'<[^>]+>', ' ', html)
text = re.sub(r'\s+', ' ', text).strip()
open(sys.argv[2], "w", encoding="utf-8").write(text[:12000])
open(sys.argv[2]+".title", "w", encoding="utf-8").write(title)
PY
  then
    echo "[learn] HTML 텍스트화 실패." >&2
    exit 2
  fi
  TITLE="$(cat "$CONTENT.title" 2>/dev/null || echo "")"
fi

if [ ! -s "$CONTENT" ]; then
  echo "[learn] 추출된 콘텐츠가 비었습니다." >&2
  exit 2
fi

# --- slug 결정 --------------------------------------------------------
if [ -z "$SLUG" ]; then
  base="${TITLE:-$URL}"
  SLUG="$(echo "$base" | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9가-힣]+/-/g; s/^-+//; s/-+$//' | cut -c1-40)"
  [ -z "$SLUG" ] && SLUG="learned-$(date +%s)"
fi
SKILL_PATH="$SKILLS_DIR/$SLUG"

# --- 스킬 본문 생성 (claude 요약 → frontmatter 규약) ------------------
GEN_PROMPT="다음 콘텐츠에서 '재사용 가능한 작업 절차(스킬)'를 추출하세요.
출력 형식(정확히 이대로):
DESCRIPTION: <한 줄 요약 + 트리거 키워드, 한국어>
---BODY---
<마크다운 본문: ## 역할 / ## When to Use / ## 절차 / ## 주의 섹션. 한국어.>

[콘텐츠]
$(cat "$CONTENT")"

GEN=""
if command -v claude >/dev/null 2>&1; then
  GEN="$(claude -p "$GEN_PROMPT" 2>/dev/null || true)"
fi

if [ -z "$(echo "$GEN" | tr -d '[:space:]')" ]; then
  # claude 미가용 폴백: 원문 앞부분을 그대로 스킬 본문으로
  DESC="${TITLE:-$URL} 에서 학습한 스킬 (자동 생성)"
  BODY="## 출처
- URL: $URL
- 제목: ${TITLE:-N/A}

## 원문 발췌
$(head -c 4000 "$CONTENT")"
else
  DESC="$(echo "$GEN" | sed -n 's/^DESCRIPTION: *//p' | head -1)"
  [ -z "$DESC" ] && DESC="${TITLE:-$URL} 에서 학습한 스킬"
  BODY="$(echo "$GEN" | sed -n '/---BODY---/,$p' | sed '1d')"
  [ -z "$(echo "$BODY" | tr -d '[:space:]')" ] && BODY="$(echo "$GEN")"
fi

# --- SKILL.md 저장 ----------------------------------------------------
mkdir -p "$SKILL_PATH"
{
  echo "---"
  echo "name: $SLUG"
  echo "description: $DESC"
  echo "source_url: $URL"
  echo "learned_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "---"
  echo ""
  echo "$BODY"
} > "$SKILL_PATH/SKILL.md"

echo "[learn] ✅ 스킬 생성: global/skills/$SLUG/SKILL.md"

# --- registry에 SKILL_LEARNED 기록 -----------------------------------
if [ -f "$REGISTRY" ] && command -v python3 >/dev/null 2>&1; then
  python3 - "$REGISTRY" "$SLUG" "$URL" <<'PY' 2>/dev/null || true
import json, sys, datetime, tempfile, os, shutil
reg, slug, url = sys.argv[1:4]
data = json.load(open(reg, encoding="utf-8"))
data.setdefault("learned_skills", []).append({
    "slug": slug, "url": url,
    "ts": datetime.datetime.now(datetime.timezone.utc).isoformat(),
})
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(reg))
with os.fdopen(fd, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
shutil.move(tmp, reg)
PY
fi
