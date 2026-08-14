---
name: obsidian-claude-brief
description: Use when 대표님이 옵시디언에 지식화된 유튜브 노트 중 Claude(Claude Code/Anthropic/Opus/Sonnet/Fable) 관련 내용을 읽어 요약해 달라고 할 때 — "옵시디언 유튜브 읽어줘", "유튜브에서 claude 요약", "최근 추가된 클로드 관련 유튜브 정리", "옵시디언 클로드 브리핑" 요청 시. 볼트의 유튜브 노트를 최근 추가순으로 훑어 Claude 관련만 필터링하고, Sonnet 서브에이전트에 읽기·요약을 위임해 브리핑을 만든다.
---

# Obsidian Claude Brief (옵시디언 유튜브 → Claude 관련 요약)

## Overview
옵시디언 볼트에 **이미 지식화된** 유튜브 노트 중 **Claude 관련**만 골라 읽고 브리핑한다. 노트를 새로 만들거나 삭제하지 않는 **읽기 전용 조회·요약** 스킬이다.

**철학**: 지식화는 `youtube-archiver`가, *다시 꺼내 읽는 것*은 이 스킬이 담당. 역할이 겹치지 않게 분리한다.

## 핵심 원칙 (반드시 지킬 것)
- **읽기 전용**: 노트 생성·수정·삭제 금지. 오직 조회·요약·출력.
- **A안 = Sonnet 서브에이전트 위임**: 노트를 대량으로 읽어들이는 작업은 **반드시 Sonnet 서브에이전트**(`model: sonnet`)에 위임한다. 메인 세션(Opus 등)의 컨텍스트·토큰을 아끼는 것이 이 스킬의 핵심 설계 의도.
- **Claude 관련 판정 기준**: frontmatter `tags`/`title`/본문에 다음 중 하나라도 있으면 Claude 관련 — `Claude`, `ClaudeCode`, `Anthropic`, `Opus`, `Sonnet`, `Haiku`, `Fable`, `claude-*`. GLM·GPT·Gemini 등만 다루고 Claude 언급이 없으면 제외.
- **최근 추가순**: 파일 mtime(`archived` 날짜가 아닌 실제 파일 수정시각) 내림차순. 대표님이 "최근 추가된"이라 할 때는 mtime 기준.
- **요약 아닌 재요약**: 노트 자체가 이미 요약본이므로, 원문 재해석이 아니라 **여러 노트를 관통하는 메시지·중복·상충점**을 뽑아 대표님 관점 인사이트로 재정리한다.

## 권장 모델 (경제성 기준)
- **노트 읽기·요약 (핵심 작업)**: **Sonnet 5** (`claude-sonnet-5`). 이미 정제된 요약 노트를 읽는 작업이라 Opus 불필요, Haiku는 관통 메시지 추출 깊이 부족 → Sonnet이 균형점. 서브에이전트 위임 시 `model: sonnet` 고정.
- **파일 탐색·정렬·필터**: 셸 명령(mtime 정렬 + grep), AI 불필요.

## 사전 요구
- 옵시디언 볼트: `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Obsidian`
- 유튜브 노트 폴더: `📥아카이브/유튜브/` (한글 이모지 경로 — 셸에서 따옴표 필수)
- 별도 설치 도구 없음. `find`/`stat`/`grep`만 사용.

## 인자
- (없음) → 최근 추가 노트 훑어 Claude 관련 상위 브리핑 (기본 최근 15개 스캔)
- `--recent N` → 최근 N개 노트만 스캔 (기본 15)
- `--all` → 폴더 전체(현재 ~200개) 스캔 후 Claude 관련 전부 (대량 → Sonnet 서브에이전트 병렬 권장)

## 워크플로우

### 1. 볼트 경로 확정 + Claude 관련 노트 목록 추출 (셸, 읽기전용)
```bash
DIR="$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/Obsidian/📥아카이브/유튜브"
# 폴더 존재 확인 (없으면 볼트 재탐색: find ~/Library -type d -iname '*유튜브*')
[ -d "$DIR" ] || echo "폴더 없음 → 볼트 경로 재확인 필요"

# 최근 추가순(mtime) 정렬 → 상위 N개
N=15   # --recent 인자로 대체, --all이면 이 줄 제거하고 전체
find "$DIR" -type f -name "*.md" -exec stat -f "%m %N" {} \; | sort -rn | head -$N
```

### 2. Claude 관련 필터링 (셸 grep)
frontmatter/본문에 Claude 계열 키워드가 있는 파일만 남긴다.
```bash
DIR="$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/Obsidian/📥아카이브/유튜브"
# 1단계에서 뽑은 파일들에 대해 (파일명 + 내용 모두 검사)
grep -liE "claude|anthropic|\bopus\b|\bsonnet\b|\bhaiku\b|\bfable\b" "$DIR"/*.md
# 파일명 자체에 Claude가 있으면 내용 grep 없이도 포함
```
→ 1단계(mtime 정렬)와 2단계(키워드) 교집합 = **최근 추가된 Claude 관련 노트 목록**.

### 3. Sonnet 서브에이전트에 읽기·요약 위임 (A안 핵심)
확정된 노트 경로 목록을 **Sonnet 서브에이전트**에 넘겨 읽고 요약하게 한다. 메인은 경로만 넘기고 본문을 직접 읽지 않는다 (컨텍스트 절약).

- 노트가 **5개 이하**: 서브에이전트 1개에 전체 위임.
- 노트가 **6개 이상**(`--all` 등): 노트를 4~6개씩 묶어 **여러 Sonnet 서브에이전트로 병렬** 위임 후 결과 병합.

서브에이전트 프롬프트 템플릿 (Agent 도구, `model: sonnet`):
```
아래 옵시디언 유튜브 노트 파일들을 Read로 읽고, 각각을 3~5줄로 요약하라.
각 노트의 "📌 핵심 요약"과 "💡 의미있는 포인트"를 근거로, Claude 관련 내용만 뽑아라.
출력 형식(노트당):
### {영상 제목} ({채널})
- (핵심 3~5줄, Claude 관련 포인트 중심)

마지막에 "관통 메시지" 2~3개(여러 노트에 공통되거나 서로 상충하는 지점)를 정리하라.
파일 목록:
{경로 리스트}
```

### 4. 메인이 최종 브리핑 정리·출력
서브에이전트 결과를 받아 대표님 관점 인사이트를 얹어 마크다운으로 출력한다. 노트 파일에는 아무것도 쓰지 않는다.

## 출력 형식 (대표님 보고용)
```
## 📺 옵시디언 유튜브 — Claude 관련 브리핑 (최근 N개 스캔, M건 매칭)

### 1. {제목} ({채널})
- 핵심 요약 3~5줄

... (건별 반복) ...

---
**관통 메시지**: ① ... ② ... (여러 노트 교차 인사이트)
```

## youtube-archiver 와의 관계
- `youtube-archiver`: 유튜브 목록 → 자막 추출 → **노트 생성** → 목록 삭제 (쓰기, 지식화)
- `obsidian-claude-brief`(본 스킬): 생성된 노트 → **조회·요약** (읽기, 브리핑)
- 두 스킬은 볼트 경로/폴더 규칙을 공유하되 역할이 배타적이다.

## 확장 여지 (지금은 하지 않음 — 요청 시)
- 키워드 인자화(`--keyword hermes`)로 Claude 외 주제 범용 브리핑. 현재는 대표님 지시대로 **Claude 전용**.
