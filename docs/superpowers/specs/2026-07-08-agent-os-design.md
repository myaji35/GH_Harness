# Agent OS — 설계 스펙

- 작성일: 2026-07-08
- 방식: **GH_Harness 확장** (신규 프레임워크 설치 아님)
- 근거: 유튜브 3영상 분석 — Hermes Agent / Agent OS 개념

## 배경 — 세 영상이 공통으로 말하는 것

| # | 영상 | 채널 | 핵심 |
|---|---|---|---|
| 1 | Claude Code + Hermes Agent 연결 | Tech Bridge | Hermes를 MCP 서버로 Claude Code에 연결 → self-evolving skill + persistent memory + cron PRD 자동 진화 |
| 2 | Hermes 신기능 7가지 | Alex Finn | Mixture of Agents(`/moa`), `/learn`(URL→스킬), `/journey`(스킬-메모리 그래프), 자가개선 저비용화, Fable 5 프로필 |
| 3 | Agent OS Q&A | Julian Goldie | Agent OS = 모든 에이전트를 한 허브에 꽂고 커스텀 워크플로우 제작. OmniRoute(무료 90+모델), 메모리 |

**세 영상을 아우르는 하나의 개념 = "Agent OS"**: 여러 에이전트/모델을 한 허브에 연결 + 스스로 진화하는 스킬·메모리 + cron 자율 워크플로우.

## 핵심 판단 — 대부분 이미 존재한다

GH_Harness는 이 개념의 뼈대를 이미 갖고 있다. 따라서 **새로 만드는 것은 "빠진 4조각"뿐**이며, 모두 기존 자산을 래핑한다 (Karpathy #2 단순함 / #3 외과적 변경).

| 영상의 Agent OS 요소 | 기존 GH_Harness 자산 | 상태 |
|---|---|---|
| self-evolving skill | `global/skills/meta-evolution`, skillify | ✅ |
| persistent memory | `memory/` + `MEMORY.md` | ✅ |
| Hermes MCP 중개 | `global/agents/hermes.md` + `hooks/hermes-escalate.sh` | ✅ |
| cron 자율 워크플로우 | hooks + CronCreate + `registry.json` | ✅ |
| 멀티모델 배치 | Opus/Sonnet/Haiku + codex | 🟡 배치만 있고 MoA 합의 없음 → **신규 ①** |
| /journey 그래프 | graphify | 🟡 skill-memory 전용 뷰 아님 → **신규 ③** |
| 통합 허브 대시보드 | `dashboard.sh`(텍스트) | ❌ 웹 허브 없음 → **신규 ④** |
| /learn URL→스킬 | skillify(수동) | 🟡 URL 원샷 아님 → **신규 ②** |

## 아키텍처

```
GH_Harness/                          ← Agent OS 코어 (기존 그대로)
  global/agent-os/                   ← 신규: 빠진 4조각
    router/    moa-route.sh          ① MoA 멀티모델 합의 라우팅
    learn/     learn-url.sh          ② URL → 스킬 자동 생성
    journey/   journey-build.sh      ③ skill-memory 그래프
    hub/       hub-render.sh
               hub.template.html     ④ 단일 HTML 한글 허브
  bin/agent-os                       ← 신규: 통합 진입점 CLI
  (재사용: registry.json, hooks, meta-evolution, hermes.md, memory/, graphify, skillify)
```

## 컴포넌트 설계

### ① MoA 라우터 — `global/agent-os/router/moa-route.sh`
- **무엇을**: 프롬프트 1개 → 참조 모델들에 병렬 전달 → aggregator(Opus)가 합의 종합.
- **어떻게**: 새 LLM 배관 없이 `codex` 스킬 + `claude -p`(non-interactive) 병렬 호출로 참조 응답 수집 → Opus가 종합.
- **입력**: `moa-route.sh "<프롬프트>" [모델목록]`
- **출력**: 종합 답변(stdout) + `registry.json`에 MOA_RUN 기록.
- **의존**: codex 스킬(있으면 참조모델로 사용), 없으면 claude 단독 다중 샘플로 폴백.
- **API 키 룰**: 무료/로컬 후보(OmniRoute 스타일) 1순위. 유료 API는 인자로 명시할 때만.

### ② /learn — `global/agent-os/learn/learn-url.sh`
- **무엇을**: URL 1개 → 콘텐츠 추출 → 재사용 스킬 생성.
- **어떻게**: 유튜브면 `youtube-analyze/fetch_transcript.sh`, 웹이면 텍스트 추출 → `skillify` 규약으로 `global/skills/<slug>/SKILL.md` 생성.
- **입력**: `learn-url.sh <URL>`
- **출력**: 새 스킬 디렉토리 + `registry.json`에 SKILL_LEARNED 기록.
- **의존**: yt-dlp(유튜브), skillify SKILL.md 규약.

### ③ /journey — `global/agent-os/journey/journey-build.sh`
- **무엇을**: 스킬 ↔ 메모리 연결 그래프 시각화.
- **어떻게**: `memory/*.md` + `global/skills/*/SKILL.md`를 graphify 입력으로 → 클러스터 그래프 HTML.
- **입력**: `journey-build.sh`
- **출력**: `global/agent-os/journey/journey.html`(graphify 산출물 링크/복사).
- **의존**: graphify 스킬.

### ④ 통합 허브 — `global/agent-os/hub/hub-render.sh` + `hub.template.html`
- **무엇을**: Agent OS 중심 화면. **기본 언어 한국어.**
- **읽기 소스**: `registry.json`(이슈/에이전트 상태), `memory/MEMORY.md`, journey.html 링크, 20개 프로젝트 git 상태.
- **어떻게**: 셸이 소스를 읽어 JSON 스냅샷 생성 → 템플릿에 주입 → 단일 `hub.html`(인라인 CSS/JS, 의존성 0).
- **디자인**: `harness-ui-trends-2026` 기본값. `brand-dna.json`이 채워지면 그 토큰 우선(현재는 빈 템플릿이라 기본값).
- **입력**: `hub-render.sh [--open]`
- **출력**: `global/agent-os/hub/hub.html`, `--open` 시 브라우저 오픈.

### ⑤ 통합 CLI — `bin/agent-os`
- 서브커맨드 디스패처. 각 모듈 스크립트로 위임.
```
agent-os moa "<프롬프트>"     → router/moa-route.sh
agent-os learn <URL>          → learn/learn-url.sh
agent-os journey              → journey/journey-build.sh
agent-os hub [--open]         → hub/hub-render.sh
agent-os help                 → 사용법(한글)
```

## 데이터 흐름
```
사용자 → agent-os CLI → moa/learn/journey → registry.json / global/skills / memory 갱신
        → agent-os hub → 위 소스 읽어 hub.html(한글) 렌더 → 브라우저
```

## 에러 처리
- 각 `.sh`는 의존 도구 부재 시(graphify/skillify/codex/yt-dlp) 한글 안내 메시지 후 비-0 exit. 침묵 실패 금지.
- registry.json 쓰기는 임시파일 + mv 원자적 교체(기존 하네스 패턴 준수).
- URL/입력 오류는 사용법 출력 후 exit 1.

## 테스트 / 검증 (성공 기준)
"실행 없이 완료 보고 금지" 룰 준수. 각 명령 실제 실행:
1. `agent-os learn <실제 URL>` → `global/skills/`에 새 SKILL.md 생성 확인.
2. `agent-os journey` → journey.html 생성 확인.
3. `agent-os hub` → hub.html 렌더, 한글 표시 + 20개 프로젝트/이슈 수치 반영 확인.
4. `agent-os moa "<간단 프롬프트>"` → 종합 답변 stdout + registry 기록 확인.
5. `agent-os help` → 한글 사용법.

## 범위 밖 (YAGNI)
- Hermes 신규 설치, 별도 MCP 서버 운영(기존 hermes.md 재사용으로 충분).
- Fable 5 전용 프로필(대표님 요청 4기능에 없음).
- 유료 API 자동 연동(무료 우선 룰).
- 실시간 서버/소켓(허브는 렌더-온-디맨드 정적 HTML).
