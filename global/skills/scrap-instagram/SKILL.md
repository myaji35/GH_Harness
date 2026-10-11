---
name: scrap-instagram
description: Use when 인스타그램 저장 목록(saved)을 옵시디언 스크랩 노트로 정리할 때 — "인스타 저장목록 정리", "인스타 스크랩", "인스타 저장한 거 조사". ego 브라우저(대표님 로그인)로 저장 게시물과 작성자 바이오 링크를 모으고, Sonnet이 항목별 정본 사이트·구매 링크·가격을 조사해 08-Scraps/인스타에 노트를 쓴 뒤 validate_scrap.py로 검사한다. 저장 해제는 별도 지시가 있을 때만.
---

# scrap-instagram — 인스타 저장 목록 → 옵시디언 구매 조사 노트

기준(2026-09-24 Hermes 대화에서 정함): 저장한 게시물마다 **무엇인지(상품·서비스·장소·정보·영감·광고)** 판별하고, **정본 사이트·구매 링크·가격·배송·신뢰도**를 조사한다. 시트 대신 옵시디언 노트로 남기고, 표는 `스크랩.base`의 "인스타 구매 조사" 보기로 본다.

## 위치
- 노트: `<볼트>/08-Scraps/인스타/` (볼트 = `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Obsidian`)
- 수집기: `~/.claude/skills/scrap-instagram/scripts/collect_saved.mjs`
- 검사기: `~/.claude/skills/scrap-youtube/scripts/validate_scrap.py` (공용)

## 절차

### 1. 수집 (ego-browser, 대표님 로그인 필요)
ego 런타임에는 셸 환경변수가 전달되지 않는다. 설정은 스크립트 앞에 한 줄로 붙인다.
```bash
OUT=<스크래치패드>/ig.json
SKIP=$(grep -rhoE 'instagram.com/(p|reel)/[A-Za-z0-9_-]+' "<볼트>/08-Scraps/인스타" | sed -E 's#.*/##' | python3 -c 'import sys,json;print(json.dumps(sys.stdin.read().split()))')
{ echo "process.env.SCRAP_IG_CONFIG = '{\"user\":\"kang_seung_sik\",\"limit\":10,\"skip\":$SKIP,\"out\":\"$OUT\"}';"; \
  cat ~/.claude/skills/scrap-instagram/scripts/collect_saved.mjs; } | ego-browser nodejs
```
- 결과: `items[]` = id, url, handle, caption, datetime, has_video, **profile_link**(작성자 바이오 링크, 스레드 배지와 추적 파라미터 제거), profile_bio.
- `{"login_required": true}`가 나오면 `ego-browser` 스킬의 `task.handOff()`로 대표님께 로그인을 부탁하고 멈춘다. 비밀번호를 입력하지 않는다.
- 상한: 한 번에 최대 30개(스크립트가 강제한다). 사람 속도로 대기한다. 저장 해제 기능은 없다.

### 2. 조사 + 노트 작성 — Sonnet 서브에이전트
`Agent(model: "sonnet")`에게 JSON 경로와 아래 규칙을 넘긴다.

**조사 순서 (이 순서가 핵심이다):**
1. **profile_link부터 연다**(WebFetch). linktree·inpock·mtrbio 같은 링크 모음 페이지면 그 안에서 상품·공식몰 링크를 고른다. 브랜드 계정은 대부분 여기서 정본 사이트가 나온다.
2. 캡션의 @멘션, 해시태그, 상품명으로 웹검색한다(항목당 2~3회).
3. 그래도 없으면 "확인 안 됨"으로 둔다. **검색에서 실제로 나온 URL만 쓴다. 지어내지 않는다.**
- "댓글 남기면 DM" 유도형은 그렇다고 적고, 실제 제품을 찾을 수 있으면 찾는다.
- 할인·오픈일처럼 날짜가 지나면 무효가 되는 정보는 게시일을 함께 적는다.

**형식:**
```yaml
---
categories:
  - "[[스크랩]]"
  - "[[인스타]]"
title: "<항목명 또는 게시물 요지>"
platform: instagram
source: "https://www.instagram.com/p/<id>/"
author: "[[<handle>]]"
published: <YYYY-MM-DD>
clipped: <오늘>
media: "<reel|image|carousel>"
kind: "<상품|서비스|장소|정보|영감|광고>"
item: "<상품·서비스명>"
official_site: "<URL 또는 확인 안 됨>"
buy_link: "<URL 또는 확인 안 됨>"
price: "<가격 + 확인일, 또는 확인 안 됨>"
shipping: "<국내 배송 여부, 또는 확인 안 됨>"
confidence: "<높음|중간|낮음>"
topics:
  - "[[<개념>]]"
use_for:
  - "[[<프로젝트>]]"    # 0~2개. 광고 크리에이티브 참고면 [[SocialDoctors]]
summary: "<한 줄, 60자 이내>"
transcript: false
status: new
origin_list: saved
origin_status: kept
rating:
---
## 한 줄
## 핵심 내용      (캡션 요지 3~5개. 음성은 전사하지 않았다고 표시)
## 조사 결과      (정본·구매·가격·대안·주의점 + 출처 URL)
## 써먹을 곳
## 원문 발췌
```
파일명 규칙과 `use_for` 후보는 `scrap-youtube`와 같다.

### 3. 검사 (필수, 내가 직접 실행)
```bash
python3 ~/.claude/skills/scrap-youtube/scripts/validate_scrap.py "<볼트>/08-Scraps/인스타" --platform instagram
```
ERROR가 0이어야 한다. 이어서 official_site/buy_link가 채워진 노트 2개의 링크를 직접 열어 실재하는지 확인한다.

### 4. 저장 해제 — 별도 지시가 있을 때만
기본은 해제하지 않는다(`origin_status: kept`). 지시가 있으면, 검사를 통과하고 대표님이 확인한 항목만 게시물의 저장(북마크) 버튼을 눌러 해제하고 `origin_status: removed`로 바꾼다. 한 번에 소량씩 하고, 새로고침 후 저장 목록에서 사라졌는지 id로 확인한다.

## 한계
- 릴스 음성은 전사하지 않는다. 캡션이 짧은 릴스는 내용이 빈약하다. 필요하면 `whisper-cli`(설치됨)로 전사하는 단계를 추가할 수 있다.
- 개인 계정 저장 목록 API는 없다. ego로 화면을 읽는 방식이라 인스타 화면 구조가 바뀌면 수집기를 고쳐야 한다.

## 실측 (2026-10-11 샘플 10개)
- 1차(웹검색만): 정본 사이트 1/10.
- 바이오 링크 우선 조사(이 문서 절차) 후: 정본 사이트 4/10, 구매 링크 6/10. 링크 3개를 직접 열어 200 응답 확인.
- 못 찾는 유형: 바이오 링크가 없는 개인·코치 계정, 영화·영감형 게시물, "댓글 남기면 DM" 유도형(쿠팡 파트너스 스토어까지만 추적됨).
- 네이버 스마트스토어 링크는 WebFetch가 막혀서 `curl`로 페이지 제목만 읽을 수 있다.
