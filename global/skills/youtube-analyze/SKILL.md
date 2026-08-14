---
name: youtube-analyze
description: Use when given a YouTube URL (youtube.com/watch, youtu.be, shorts) and asked to analyze, summarize, extract insights, fact-check, transcribe, or turn the video into a report/graph/JSON. Fetches the transcript via yt-dlp (no API key) and analyzes the content.
---

# YouTube 영상 분석 (youtube-analyze)

## Overview
YouTube URL을 받아 **yt-dlp로 자막(스크립트)과 메타데이터를 추출**한 뒤, 그 텍스트를 분석한다. 별도 API 키나 파이썬 패키지 불필요 — `yt-dlp` 하나만 있으면 된다. 핵심 원칙: **영상을 보지 말고 자막 텍스트를 읽어 분석한다.** (LLM은 자막 텍스트 분석에 가장 빠르고 정확하다.)

## When to Use
- URL이 `youtube.com/watch?v=`, `youtu.be/`, `youtube.com/shorts/` 형태
- "이 영상 분석/요약/정리해줘", "핵심만 뽑아줘", "받아쓰기", "팩트체크", "보고서로 만들어줘" 등
- **When NOT**: 자막이 전혀 없는 영상(라이브 음악 등) → STT 필요(이 스킬 범위 밖, 사용자에게 안내)

## Workflow

### 1단계 — 추출 (항상 먼저)
```bash
~/.claude/skills/youtube-analyze/scripts/fetch_transcript.sh "<URL>" /tmp/yt-out "ko,en"
```
- 3번째 인자는 언어 우선순위(콤마 구분). 기본 `ko,en`. 한국어 영상이면 그대로, 영어 채널이면 `en` 우선이 자연스럽다.
- 산출물 (`/tmp/yt-out`):
  - `meta.json` — 제목/채널/길이/조회수/좋아요/업로드일/설명
  - `transcript.txt` — 타임스탬프 없는 순수 본문 → **요약·분석용**
  - `transcript.vtt` — 타임스탬프 포함 → **특정 구간 인용·시점 참조용**
- **종료코드**: `2`=자막없음(STT 안내), `3`=yt-dlp없음(`brew install yt-dlp` 안내), `4`=URL오류

### 2단계 — 읽기
`transcript.txt`와 `meta.json`을 Read로 읽는다. 긴 영상(수만 단어)이면 `transcript.txt`를 청크로 나눠 읽거나 분석을 Agent에 위임한다.

### 3단계 — 분석 + 산출 (요청에 맞춰)
| 사용자 요청 | 산출 방식 |
|---|---|
| 기본 / "요약" / "정리" | 대화 내 마크다운으로 출력 (아래 템플릿) |
| "보고서" / "PDF" / "리포트" | `report-pdf-builder` skill 호출 (전역 룰) |
| "지식 그래프" / "graphify" | `transcript.txt`를 입력으로 `graphify` skill 호출 |
| "JSON" / "데이터로" | 구조화 JSON으로 저장 (아래 스키마) |

여러 산출물을 동시에 요청하면 모두 생성한다.

## 분석 출력 템플릿 (기본 요약)
```markdown
## 📺 {제목}
- 채널: {channel} · 길이: {duration_string} · 조회수: {view_count} · 업로드: {upload_date}

### 한 줄 요약
{영상 전체를 한 문장으로}

### 핵심 포인트
1. {요지} — {근거/구간}
2. ...

### 타임라인 (선택, vtt 활용)
- 00:00 도입 …
- 05:20 핵심 주장 …

### 인사이트 / 시사점
- {표면 너머의 함의}
```

## JSON 스키마 (요청 시)
```json
{
  "video": {"id":"","title":"","channel":"","duration":"","views":0,"upload_date":"","url":""},
  "summary": "",
  "key_points": [{"point":"","timestamp":""}],
  "topics": [""],
  "sentiment": "",
  "transcript_word_count": 0
}
```

## Common Mistakes
- ❌ 자막을 받기도 전에 제목·썸네일만으로 추측 요약 → 반드시 1단계 추출 먼저
- ❌ `transcript.vtt`(타임스탬프 범벅)를 통째로 요약 입력 → 본문은 `transcript.txt`를 쓴다
- ❌ 자막 없음(exit 2)인데 억지로 진행 → 사용자에게 "자막 없음, STT 필요" 안내
- ❌ "보고서"라 했는데 마크다운만 출력 → 전역 룰: `report-pdf-builder` 호출 의무
- ❌ 자동생성 자막의 중복 줄을 그대로 노출 → 스크립트가 이미 dedup 처리하므로 `transcript.txt` 사용
