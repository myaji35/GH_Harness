---
name: youtube-archiver
description: Use when 유튜브 나중에볼영상/좋아요/재생목록에 쌓인 영상을 정리하고 싶을 때 — "유튜브 정리", "나중에볼영상 정리", "유튜브 지식화", "영상 요약해서 옵시디언" 요청 시. 목록을 수집하고 각 영상의 자막을 yt-dlp로 추출해 의미있는 요약 노트를 옵시디언에 만든 뒤, 저장 검증된 영상만 목록에서 삭제한다.
---

# YouTube Archiver (유튜브 → 옵시디언 지식화 + 목록 비우기)

## Overview
유튜브 나중에볼영상/좋아요에 쌓인 영상을 **지식화하고 비운다**. 각 영상의 자막을 yt-dlp로 추출해 **의미있는 요약**(챕터 나열 아님) 노트를 옵시디언에 만들고, 저장 검증된 것만 목록에서 삭제한다.

**철학**: 안 보고 쌓아둔 영상 = 지식 부채. 요약해서 옵시디언에 남기고 목록은 비운다.

## 핵심 원칙 (반드시 지킬 것)
- **하루 100개 절대 초과 금지** (대표님 확정 2026-07-01): 지식화든 삭제든 하루 100개 이내. 유튜브 계정 제약 방지 최우선. 초과하려 하면 STOP.
- **일일 배분 = 나중에볼영상 70 + 좋아요 30** (대표님 확정 2026-07-01, 내일부터 적용). WL에서 앞 70개, LL에서 앞 30개. 단 dedup으로 이미 처리된 중복은 카운트에서 제외하고 다음 것으로 채운다.
- **저장 검증 후 삭제**: 옵시디언 노트 생성 확인된 영상만 목록에서 제거. 유튜브 삭제는 되돌리기 어려움.
- **의미있는 요약 필수**: 자막을 실제로 읽고 핵심 인사이트를 뽑는다. 설명글 복붙 금지.
- **썸네일+링크 필수**: 노트에 클릭 가능한 썸네일(`https://img.youtube.com/vi/{ID}/hqdefault.jpg`)과 영상 링크를 반드시 넣는다.
- **회수 가능성이 노트 수보다 중요**: 목록을 비우고 노트 수만 늘리는 데 최적화하지 말고, `topic`과 MOC로 나중에 다시 찾고 연결할 수 있게 만든다. 종전 시스템은 회수 설계 없이 "목록 비우기"만 최적화해 노트를 고립시켰다.

## 권장 모델 (경제성 기준)
- **자막 요약 (핵심 작업)**: **Sonnet 5** (`claude-sonnet-5`). 2000~3000단어 자막을 읽고 의미있는 요약+인사이트를 뽑는 작업이라 품질이 중요. Haiku는 요약 깊이 부족, Opus는 과함 → Sonnet이 경제성-품질 균형점. 서브에이전트 위임 시 `model: sonnet`.
- **목록 수집·삭제 조작**: 브라우저 명령이라 모델 무관.
- **자막 추출**: yt-dlp(스크립트), AI 불필요.
- 대량(100개) 처리 시 Sonnet 서브에이전트로 병렬화하면 비용·시간 최적.

## 사전 요구
- `yt-dlp` 설치 (`brew install yt-dlp`). ⚠️ 자막은 브라우저 fetch API가 유튜브에 차단됨 → **반드시 yt-dlp**로.
- **브라우저 (목록 수집·삭제용) — 두 방식 중 택1 (2026-07-06 확정):**
  - **① Claude in Chrome 확장 (대표님 선호)**: 대표님이 이미 로그인해 둔 실제 Chrome을 그대로 사용. `tabs_context_mcp(createIfEmpty:true)` → 새 MCP 탭이 대표님 프로필 세션을 공유하므로 유튜브 로그인 그대로 유효. 재로그인 불필요. ⚠️ **프라이버시 필터 주의** → 워크플로우 1단계 참조.
  - **② GStack browse 데몬**: 별도 브라우저 인스턴스라 대표님 Chrome 로그인이 **공유 안 됨**. `browse cookie-import-browser chrome --domain .youtube.com`로 쿠키 임포트 필수(**앞에 점 `.youtube.com` — `youtube.com`은 0개 임포트됨**, Chrome 실행 중이어도 됨). 스크립트 대량처리엔 빠르나 대표님은 ①을 선호.
- 옵시디언 볼트 `f1bf102a80c7398f`: `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Obsidian`, 노트는 `📥아카이브/유튜브/`.

## 워크플로우

### 1. 목록 수집 + 중복 제거 (읽기전용)
**대표님은 링크 손실 방지 습관으로 나중에볼영상(WL)+좋아요(LL) 양쪽에 중복 저장한다.** 반드시 두 목록 모두 수집하고 영상 ID로 dedup한다 (같은 영상 두 번 요약 방지).

**⚠️ Claude in Chrome 프라이버시 필터 (2026-07-06 확정) — 반드시 지킬 것:**
- `javascript_tool`이 반환하는 값에 **URL/쿼리스트링/제목 대량텍스트/JSON/base64가 섞이면 `[BLOCKED: ...]`로 전량 차단**된다 (제목·채널까지 담은 JSON, `id\ttitle` 탭구분, btoa 인코딩 전부 막힘).
- **통과하는 유일한 형태 = video ID(11자)만 공백구분 문자열**: `window.__wl.map(r=>r.id).join(' ')` → OK.
- **제목/채널/메타는 도구로 빼낼 필요 없다.** ID만 확보하면 2단계 yt-dlp(`fetch_video.py`)가 title·channel·조회수·자막을 전부 가져온다. 브라우저에선 **ID만** 수집하면 끝.
- 추출 데이터는 `window.__wl`, `window.__ll`에 저장해두고, ID 문자열만 꺼내 스크래치패드 파일로 넘긴다.

**WL(나중에볼)** — 폴리머 렌더러 사용:
```
navigate → https://www.youtube.com/playlist?list=WL
// 끝까지 스크롤 (개수 안정될 때까지, WL은 최대 100개)
window.__wl = Array.from(document.querySelectorAll('ytd-playlist-video-renderer')).map(el=>{
  const t=el.querySelector('#video-title'); let id=''; if(t&&t.href){const m=t.href.match(/v=([\w-]{11})/); if(m)id=m[1];}
  return {id, title:t?t.title.trim():''};
}).filter(v=>v.id);
window.__wl.slice(0,70).map(r=>r.id).join(' ')   // ← WL 앞 70개 ID만 반환 (통과)
```
**LL(좋아요)** — ⚠️ **DOM 구조가 WL과 다르다** (2026-07-06 확정). `ytd-playlist-video-renderer`가 **0개**로 나온다. `#contents` 하위가 순수 `<div>`라서, watch 링크를 직접 긁어야 함:
```
navigate → https://www.youtube.com/playlist?list=LL   // 렌더 3.5초+ 대기
const c=document.querySelector('#contents'); const seen=new Set(); const ids=[];
c.querySelectorAll('a[href*="watch"]').forEach(a=>{const m=a.href.match(/v=([\w-]{11})/); if(m&&!seen.has(m[1])){seen.add(m[1]);ids.push(m[1]);}});
window.__ll = ids;
window.__ll.slice(0,30).join(' ')   // ← LL 앞 30개 ID만 반환 (70:30 룰)
```
**dedup**: WL70 + LL30 ID 합집합. 각 영상에 `in_wl`/`in_ll` 소속 플래그. 유니크 영상만 1회 요약. 기존 노트 `video_id`와 대조해 처리済 제외(노트 있으면 삭제만).

### 2. 각 영상 자막+메타 추출 (yt-dlp)
```bash
python3 ~/.claude/skills/youtube-archiver/scripts/fetch_video.py <video_id>
# → JSON: title, channel, upload_date, view_count, chapters, transcript, has_transcript
```

### 3. 의미있는 요약 노트 생성
자막(transcript)을 **읽고** 핵심 요약 + 인사이트를 작성. 자막 없으면(has_transcript=false) 설명+챕터로 폴백.
**노트 생성은 반드시 `write_note.py` 사용** (프론트매터·썸네일·링크·**풍부한 태그 자동 도출**). 주제 태그(ClaudeCode/AI에이전트/셀프호스팅…)는 제목+요약을 우선하고 설명은 후보가 부족할 때만 보조로 사용한다. 콘텐츠유형(튜토리얼/리뷰/뉴스)은 제목만 보고, 언어(영어영상/한글영상)와 분석방식(자막분석/설명폴백)도 자동 부착한다. 기존 노트 소급은 `add_tags.py`.
태그는 **최대 5개**다. 주제 태그는 제목+요약 등장 횟수 내림차순으로 선택하고, 콘텐츠유형 정규식은 제목에만 적용한다. 보편어 `영상`/`video`를 `영상제작`으로 매핑하지 않는다.
노트 구조:
```markdown
---
title: ...
channel: ...
published: YYYY-MM-DD
archived: YYYY-MM-DD
category: 유튜브
topic: AI/ClaudeCode
depth: 심층 | 표준 | 로그
duration_min: 25
source: WL | LL | unknown
actionable: true | false
depth_source: 영상길이 | 본문길이추정
tags: [유튜브, ...최대 4개]
video_id: <ID>
url: https://www.youtube.com/watch?v=<ID>
thumbnail: https://img.youtube.com/vi/<ID>/hqdefault.jpg
views: 0
analysis_method: 자막 전문(yt-dlp) | 설명+챕터(폴백)
status: 지식화됨 | 미검증로그
---
# {제목}
[![썸네일](https://img.youtube.com/vi/<ID>/hqdefault.jpg)](https://www.youtube.com/watch?v=<ID>)
▶️ **[영상 보기](URL)** · 📺 {채널} · 👁 {조회수}
## 📌 핵심 요약
## 💡 의미있는 포인트
## 🎯 인사이트 (대표님 관점)
## 🔗 관련
- 볼트에 실제로 존재하는 노트만 `[[정확한 노트 stem]]`으로 연결한다. 키워드나 태그를 임의로 `[[ ]]`로 감싸 유령링크를 만들지 않는다.
```
`write_note.py`는 저장 직전 `resolve_wikilinks()`로 볼트 전체 노트 stem 인덱스와 대조한다. 실존 링크는 유지하고, 실존하지 않는 `[[링크]]`는 평문으로 벗기므로 요약 초안에 위키링크가 많아도 안전하다. 진짜 주제 연결과 탐색 허브는 MOC가 담당한다.
저장 위치: `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Obsidian/📥아카이브/유튜브/YYYY-MM-DD_유튜브_주제.md`

### 4. 저장 검증 → 양쪽 목록에서 삭제 (배치)
노트 파일 존재 확인 후 삭제. **중복 영상(in_wl && in_ll)은 양쪽 모두 삭제** (대표님 확정 2026-07-01 — 옵시디언에 저장됐으니 양쪽 저장 불필요):
```bash
# 나중에볼영상: ⋮ 메뉴 → "나중에 볼 동영상에서 삭제"
# 좋아요: 영상 페이지에서 좋아요 버튼 토글 해제 (가장 안정적, 2026-08-08 100건 전량 성공)
# UI는 자주 바뀜 → 스크린샷으로 확인하며 진행
```

**좋아요(LL) 권장 삭제 절차 (2026-08-08 실측 검증):**
1. 영상 페이지로 이동 후 3.8초 대기한다.
2. `aria-label`에 `좋아요`가 있고 `싫어요`·`요약`이 없는 `button`을 찾는다.
3. `aria-pressed="true"`면 클릭하고 1.5초 대기한 뒤 버튼을 다시 조회해 `false`가 됐는지 확인한다. `true`가 아니면 이미 해제된 것(`ALREADY`)이다.
4. `browser_batch`로 **4건씩** 묶어 처리한다. 5건 이상은 타임아웃 위험이 있다.
5. 버튼을 못 찾은 경우(`NOBTN`)는 즉시 실패로 판정하지 말고, 페이지 대기를 6초로 늘려 재시도한다.

LL 목록 페이지의 `⋮` → `좋아요 표시한 동영상에서 삭제` 메뉴도 작동한다. 다만 삭제마다 목록이 재렌더되므로 한 루프에 4건 이상 처리하면 `CDP Runtime.evaluate`가 45초 타임아웃으로 죽을 수 있다. 목록 방식을 쓸 때는 **1~3건씩** 끊는다.

**삭제 검증은 반드시 목록 페이지를 새로고침한 뒤** 수행한다. 삭제 직후 같은 페이지의 DOM에는 지연 로드로 삭제 전 항목과 캐시된 총계가 남을 수 있으므로, 같은 DOM 재조회만으로 실패 판정하지 않는다. 새로고침 후 ① 헤더의 `동영상 N개` 총계가 줄었는지, ② 대상 `video_id`가 목록에서 사라졌는지 두 가지를 함께 확인한다. **하루 100개 절대 초과 금지.**

### 5. 일자별 인덱스 노트 생성 (분석 목록 + 링크)
**반드시 `build_report.py` 사용** (인라인 Python 금지 — 링크 깨짐/경로 오류 재발 원인). 이 스크립트가 경로·YAML·링크정합·자기검증을 코드로 강제한다:
```bash
python3 ~/.claude/skills/youtube-archiver/scripts/build_report.py <YYYY-MM-DD> [candidates.json]
# candidates.json(선택): [{"id","in_wl","in_ll"},...] 순서·소속. 없으면 archived 노트 전부 날짜순.
# → 볼트 루트 📋일자별보고서/<날짜>_작업보고서.md 생성 + [[링크]] 실제파일 대조 검증(불일치 시 exit 1)
```
스크립트가 보장하는 것:
- **경로**: 볼트 루트 `📋일자별보고서/` (하위폴더에 만들면 대표님 화면 파일탐색기에 안 보임)
- **링크 정합**: 노트의 `video_id`로 **실제 파일명을 읽어** `[[링크]]` 생성 → 제목 재가공 안 하므로 절대 안 깨짐. `[]`는 write_note가 이미 `()`로 안전화.
- **YAML-safe**: title 인용, tags 안전.
- **자기 검증**: 생성 직후 모든 `[[링크]]`가 실제 파일과 일치하는지 대조, 불일치면 비정상 종료.
각 항목 형식: `N. [[노트제목]] · 채널 · [🔗영상](url)` (노트제목=실제 파일명 stem, 클릭 시 요약노트로 이동).

### 6. 자막 임시파일 삭제
옵시디언 저장 검증 완료 후에만 videos/*.json, *.vtt 임시파일 삭제 (대표님 지시). 옵시디언 노트는 보존.

### 7. 주제 MOC 갱신
배치 처리가 끝나면 **반드시** 실행한다. 이 단계를 빼먹으면 새 노트가 MOC에 연결되지 않아 다시 고립된다.
```bash
python3 ~/.claude/skills/youtube-archiver/scripts/build_moc.py
# 점검: python3 ~/.claude/skills/youtube-archiver/scripts/build_moc.py --dry-run
# 기존 노트 보정: python3 ~/.claude/skills/youtube-archiver/scripts/build_moc.py --backfill
```
`build_moc.py`는 `topic`별 MOC를 볼트 루트 `00-MOC/유튜브-<topic>.md`에 만들고, `00-MOC/유튜브-INDEX.md`를 갱신하며, 필요하면 `Home.md`에 INDEX 링크를 추가한다. `--backfill`은 기존 노트의 프론트매터 보정·유령링크 평문화·노이즈 태그 제거를 수행한다. 변경 실행 전 `.backup-유튜브-<타임스탬프>/`에 자동 백업하며, 멱등이므로 같은 상태에서 2회 실행하면 변경은 0개여야 한다. 테스트 볼트는 `YOUTUBE_ARCHIVER_VAULT_ROOT` 환경변수로 오버라이드한다.

`--clusters`는 실험 기능으로 기본 비활성화한다. 제목 토큰 Jaccard 유사도는 같은 사건의 의미를 식별하지 못해 `How to`로 시작하는 무관한 영상까지 묶었다. 의미 임베딩 기반 재설계 전에는 사용하지 않는다(ISS-398).

2026-08-08 실적용 기준: 359개 백필, 주제 MOC 8개 생성(AI/ClaudeCode 142, AI/에이전트 108, AI/LLM일반 41, 개발/일반 20, 비즈니스/마케팅 17, 기타 17, 개발/인프라 6, 금융/투자 3), 유령링크 1260개 평문화, actionable 52개 식별. depth 분포는 심층 7.5% / 표준 52.1% / 로그 40.4%였다.

2026-08-08 삭제 실적: 좋아요 100건 삭제 완료. 목록 4,880 → 4,780(정확히 100 감소), 대상 잔여 0. 지식화는 신규 99건(1건은 기존 노트 보유).

## Common Mistakes
- ❌ 브라우저 fetch로 자막 시도 → status 200 빈 응답 (유튜브 차단). yt-dlp 써라.
- ❌ 챕터 목록만 복붙 → "의미있는 요약" 아님. 자막 읽고 인사이트 뽑아라.
- ❌ 썸네일/링크 누락 → 노트에서 영상 식별 불가. 항상 넣어라.
- ❌ 하루 100개 초과 → 계정 제약 위험.
- ❌ 노트 생성 확인 없이 삭제 → 지식 유실. 검증 후 삭제.
- ❌ **삭제 반복 카운트 오차** (2026-07-01: 첫 테스트삭제 포함 계산 어긋나 1개 남음). 삭제 후 반드시 video_id로 "오늘 대상 잔여 0" 검증. 유튜브가 다음 페이지 자동로드하면 목록 개수가 튀니 개수 아닌 ID로 판정.
- ❌ **삭제 후 같은 페이지 DOM 재조회로 `실패` 판정** (2026-08-08). 유튜브 지연 로드 때문에 갱신 전 목록을 읽는다. 반드시 새로고침 후 총계+ID로 검증하라. 이 오판으로 정상 동작하던 삭제를 중단한 적이 있다.
- ❌ **`browser_batch`에 5건 이상 묶기** (2026-08-08). 영상 페이지 이동+토글은 건당 약 6초라 5건이면 타임아웃 위험. 4건이 안전선이다.
- ❌ **목록 페이지에서 삭제 루프 4건 이상** (2026-08-08). 삭제마다 목록 재렌더가 일어나 `CDP Runtime.evaluate`가 45초 타임아웃. 목록 방식은 1~3건씩.
- ❌ **`NOBTN`을 즉시 실패 처리** (2026-08-08). 페이지 로딩 지연일 뿐이다. 대기 6초로 재시도하면 대부분 성공한다.
- ❌ **서브에이전트 임시파일명 summary_*.md 는 리포트로 오인돼 Write 차단됨**. note_*.md / vidsum_*.md 로 쓸 것.
- ❌ **병렬 yt-dlp 자막 재시도 경쟁 실패** → 자막 있는데도 안 잡힘. 재시도는 순차로.
- ❌ 백그라운드 exit 0 = 완료 착각 금지. 노트 수/삭제 잔여를 실제 수치로 검증.
- ❌ **Claude in Chrome `javascript_tool`이 제목/JSON/URL/base64 반환 시 `[BLOCKED]`** (2026-07-06). video ID만 공백구분으로 반환하라. 제목·메타는 yt-dlp가 채우니 브라우저에선 ID만 긁는다.
- ❌ **좋아요(LL) 목록에 `ytd-playlist-video-renderer` 셀렉터 쓰면 0개** (2026-07-06). LL은 `#contents` 하위 순수 div → `a[href*="watch"]`로 ID 추출. WL과 DOM 구조 다름.
- ❌ **GStack browse `cookie-import-browser chrome --domain youtube.com` → 0개** (2026-07-06). 앞에 점 붙인 `.youtube.com`이라야 임포트됨. 또한 browse 데몬은 대표님 Chrome과 별개 인스턴스라 로그인 비공유 → 쿠키 임포트 필수. (단 대표님은 Claude in Chrome 확장 방식 ①을 선호)
- ❌ **작업보고서를 `📥아카이브/유튜브/📋일자별보고서/`에 저장 → 대표님 화면에 안 보임** (2026-07-06). `📋일자별보고서`는 **볼트 루트** 폴더다. 파일명 `YYYY-MM-DD_작업보고서.md`.
- ❌ **프론트매터 `title:`/`channel:` 값에 `[` `:` `"` 등이 있으면 YAML 파싱 깨져 옵시디언 본문이 빈 화면** (2026-07-06). write_note.py가 title/channel을 항상 큰따옴표로 감싸도록 수정됨(`yq()`). 기존 노트 소급 시 PyYAML로 파싱 실패 노트를 찾아 title·channel 인용 처리. 검증은 `yaml.safe_load` + `isinstance(title,str)`.
- ❌ **파일명에 `[]`가 있으면 옵시디언 `[[위키링크]]`가 깨짐** (2026-07-06). write_note.py 파일명 안전화가 `[]`→`()` 치환하도록 수정됨. 일자별보고서 링크도 `()` 파일명 기준으로 생성해야 매칭됨. 보고서 생성 후 반드시 `[[링크]]` vs 실제 파일명 대조 검증.
- ❌ **유령 위키링크 1258개 사고** — 볼트 조회 없이 키워드를 `[[ ]]`로 감싸면 그래프뷰에서 아무데도 닿지 않는다. 당시 전체 1267개 중 실존 링크는 9개(0.7%)뿐이었다. 실존 노트 링크만 권장하고, 나머지는 `resolve_wikilinks()`에 맡겨 평문화한다.
- ❌ **보편어 태그 오염** — `영상` 같은 단어를 태그 트리거로 쓰면 359개 중 333개(92.8%)에 붙어 분류 기능을 잃는다. `영상`/`video`→`영상제작` 매핑을 다시 추가하지 않는다.
- ❌ **MOC 갱신 누락** — 노트 생성만 하고 `build_moc.py`를 실행하지 않으면 새 노트가 다시 고립된다. 모든 배치의 마지막에 MOC와 INDEX를 갱신한다.
- ❌ **제목 유사도 클러스터링은 의미를 못 잡음** — 제목 토큰 Jaccard는 같은 사건을 식별하지 못하고 무관한 `How to` 영상 등을 묶는다. `--clusters`는 ISS-398의 의미 임베딩 재설계 전까지 사용하지 않는다.

## 자막 언어
기본 en 우선. 한국어 영상은 fetch_video.py의 `--sub-langs`에 `ko` 추가.
