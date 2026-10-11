---
name: scrap-youtube
description: Use when 유튜브 나중에볼영상(WL)·좋아요를 옵시디언 스크랩 노트로 정리할 때 — "유튜브 스크랩", "나중에볼영상 정리", "유튜브 N개 정리", "다시볼 영상 옵시디언". ego 브라우저로 목록 ID를 모으고, fetch_yt.py로 자막을 받아, Sonnet이 08-Scraps/유튜브에 메타데이터 노트를 쓴 뒤 validate_scrap.py로 검사한다. 원본 목록 삭제는 별도 지시가 있을 때만.
---

# scrap-youtube — 유튜브 → 옵시디언 스크랩 노트

목적: 대화 중 Claude·Hermes가 "일전에 스크랩한 ○○을 써볼까요?"라고 꺼내 쓸 수 있는 노트를 만든다.
그래서 요약보다 **`use_for`(써먹을 곳)와 `summary`(한 줄)의 정확도**가 더 중요하다.

기존 `youtube-archiver`(📥아카이브/유튜브, 구 형식)를 대체한다. 구 노트 562개는 그대로 둔다.

## 위치
- 볼트: `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Obsidian`
- 노트: `08-Scraps/유튜브/` · 보기: `08-Scraps/스크랩.base` · 분류 노트: `08-Scraps/스크랩.md` · 템플릿: `99-Templates/Scrap Note.md`
- 스크립트: `~/.claude/skills/scrap-youtube/scripts/`

## 절차

### 1. 목록 ID 수집 (ego-browser)
`ego-browser` 스킬을 따른다. ego에 유튜브 로그인이 되어 있어야 한다.
```bash
ego-browser nodejs <<'EOF'
const task = await taskSpace("scrap-youtube");
const page = task.page("p1");
await page.goto("https://www.youtube.com/playlist?list=WL");
await page.waitForSelector("ytd-playlist-video-renderer", { timeout: 15000 });
const ids = await page.evaluate((n) => [...document.querySelectorAll("ytd-playlist-video-renderer")]
  .map(el => (el.querySelector("#video-title")?.href || "").match(/v=([\w-]{11})/)?.[1]).filter(Boolean).slice(0, n), 10);
console.log(ids.join(" "));
await task.finish({ keep: [] });
EOF
```
- 좋아요(LL)는 DOM이 다르다: `#contents a[href*="watch"]`에서 `v=` ID를 뽑는다.
- **중복 제외**: `grep -rh '^video_id:' 08-Scraps/유튜브/`로 이미 있는 ID를 뺀다.
- 하루 상한 100개(계정 보호, youtube-archiver와 공유).

### 2. 메타 + 자막
```bash
for id in <IDs>; do python3 ~/.claude/skills/scrap-youtube/scripts/fetch_yt.py $id --out <스크래치패드>/yt; done
```
- 언어 하나씩 순서대로 시도한다: 수동 ko → 수동 en → 자동(영상 원어) → 자동 en → 자동 ko.
- ⚠️ `ko.*` 같은 번역 패턴을 한꺼번에 요청하면 429로 막힌다. 구 `fetch_video.py`가 이 문제로 10개 중 8개 자막을 놓쳤다(2026-10-11). 이 스크립트로 해결됐다.
- 병렬로 돌리지 않는다(순차).

### 3. 노트 작성 — Sonnet 서브에이전트에 맡긴다
`Agent(model: "sonnet")`에게 JSON 경로와 아래 **형식·규칙**을 그대로 넘긴다. 10개당 약 4분이 걸린다.

파일명: 내용을 설명하는 한국어 제목(40자 이내). `/ \ : * ? " < > | [ ] # ^`는 쓰지 않는다.

```yaml
---
categories:
  - "[[스크랩]]"
  - "[[유튜브]]"
title: "<원제>"
platform: youtube
source: "https://www.youtube.com/watch?v=<ID>"
author: "[[<채널명, | 는 제거>]]"
published: <YYYY-MM-DD>
clipped: <오늘>
duration: "<mm:ss>"
media: video
video_id: "<ID>"
topics:
  - "[[<개념>]]"        # 2~4개
use_for:
  - "[[<프로젝트>]]"    # 0~3개, 정말 맞을 때만
summary: "<무엇을 얻는지 한 줄, 60자 이내>"
depth: "<심층|표준|로그>" # 로그 = 낚시성·내용 빈약
transcript: true
status: new             # new | used | archived
origin_list: WL         # WL | LL
origin_status: kept     # kept = 원본 목록에 남아 있음
rating:
---
![thumbnail](https://img.youtube.com/vi/<ID>/hqdefault.jpg)
## 한 줄
## 핵심 내용      (수치·단계·도구명이 들어간 5~8개 항목)
## 써먹을 곳      (use_for 프로젝트별로 어떻게 적용할지)
## 원문 발췌      (핵심 문장 2~3개)
```

`use_for` 후보: `[[GH_Harness]]` 하네스·훅·스킬 / `[[Hermes]]` 개인 AI 에이전트 / `[[XimTier]]` 분석 SaaS / `[[누리팜]]` 스마트팜 / `[[SocialDoctors]]` SNS 마케팅 대행 / `[[insuPro]]` 보험 / `[[홈네트워크]]` Pi5·HA·맥미니 / `[[개인-건강]]` / `[[개인-생활]]`.
- 자막에 없는 사실은 쓰지 않는다. 낚시성 영상이면 summary에 그렇다고 쓰고 depth를 로그로 둔다.
- 서브에이전트 임시파일 이름을 `summary_*.md`로 하지 않는다(리포트로 오인되어 차단된다).

### 4. 검사 (필수, 내가 직접 실행)
```bash
python3 ~/.claude/skills/scrap-youtube/scripts/validate_scrap.py "<볼트>/08-Scraps/유튜브"
```
ERROR가 0이어야 완료다. 이 검사기는 YAML, 필수 필드, 허용값, 파일명, 중복 source를 확인한다. 이어서 노트 2개를 직접 열어 내용 품질을 확인한다(자막과 맞는지, use_for가 억지가 아닌지).

### 5. 원본 정리 — 별도 지시가 있을 때만
- 기본은 **삭제하지 않는다**(`origin_status: kept`). Base의 "원본 삭제 대기" 보기에 쌓인다.
- 대표님이 삭제를 지시하면, 노트 검사를 통과한 것만 WL에서 지우고 `origin_status: removed`로 바꾼다. 삭제 UI 절차와 함정은 `youtube-archiver` 4단계를 따른다(4건씩, 새로고침 후 ID로 검증).

## 실측 (2026-10-11 샘플 10개)
- 자막 10/10 확보(수동 1, 자동 9). 노트 10개 검사기 통과, Sonnet 작성 약 4분.
- depth 분포: 심층 2 / 표준 7 / 로그 1. use_for는 GH_Harness 6, Hermes 3.
