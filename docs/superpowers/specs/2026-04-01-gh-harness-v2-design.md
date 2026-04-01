# GH_Harness v2 설계 문서

## 개요

Self-Evolving Harness System을 **실제 작동 가능한 수준**으로 보완한다.
- 에이전트별 Claude 모델 차등 배치 (Opus/Sonnet/Haiku)
- ux-harness 신규 추가 (프로젝트별 UX 아젠다 자동 생성/진화)
- Claude Code Agent 도구 기반 실행 엔진
- settings.json hooks로 이벤트 기반 트리거 연결

---

## 1. 에이전트 구성 (7 + 1)

### 모델 배치

| Agent | Model | 역할 | 비용 |
|-------|-------|------|------|
| harness-orchestrator | Opus | 오케스트레이션, 패턴 선택 | 높음 |
| agent-harness | Opus | 코드 생성/수정 | 높음 |
| meta-agent | Opus | 관찰/진화/아젠다 보완 | 높음 |
| ux-harness | Sonnet | UX 아젠다 기반 검증 | 중간 |
| test-harness | Sonnet | 테스트 실행 | 중간 |
| eval-harness | Sonnet | 품질 점수 산출 | 중간 |
| cicd-harness | Sonnet | 배포 판단 | 중간 |
| qa-reviewer | Sonnet | 교차 검증 | 중간 |
| hook-router | Haiku | 이슈 라우팅, JSON 조작 | 낮음 |

**비용 효과**: 전부 Opus 대비 약 40~45% 비용으로 동등 이상 생산성.

### 아키텍처

```
harness-orchestrator (Opus)
    │
    ├→ agent-harness (Opus) ──→ 코드 생성
    │       │
    │       ├→ UI_REVIEW ──→ ux-harness (Sonnet)  ┐ 병렬
    │       └→ RUN_TESTS ──→ test-harness (Sonnet) ┘
    │                              │
    │                              ▼
    │                        eval-harness (Sonnet)
    │                              │
    │                              ▼
    │                        cicd-harness (Sonnet)
    │
    └→ meta-agent (Opus) ──→ 30분 관찰 + 진화
    
    hook-router (Haiku) ──→ 이슈 라우팅
```

---

## 2. ux-harness 상세 설계

### 역할
프로젝트 코드/설정을 자동 분석하여 도메인을 추론하고, 해당 도메인에 최적화된 UX 검증 아젠다를 자동 생성한다. 획일화된 체크리스트가 아니라 프로젝트별 맞춤 기준.

### 프로젝트 분석 → 도메인 추론

분석 대상:
1. package.json → 프레임워크/라이브러리 감지
2. README/docs → 도메인 키워드 추출
3. 컴포넌트 구조 → UI 패턴 분류
4. 기존 스타일 → 디자인 시스템 감지

### 도메인 → 아젠다 매핑

| 감지 신호 | 추론 도메인 | 자동 생성 아젠다 |
|----------|-----------|----------------|
| D3/Chart.js, graph, node/edge | 데이터 시각화 | 그래프 가독성, 색상 대비, 범례 명확성, 줌/팬 조작성 |
| progress, step, quiz, score | 학습/교육 | 진행률 피드백, 단계 전환 UX, 모바일 학습 최적화 |
| feed, post, comment, like | 소셜/커뮤니티 | 무한 스크롤, 모바일 반응형, 접근성(WCAG), 광고 비침습성 |
| form, input, validation, CRUD | 비즈니스 앱 | 폼 가독성, 에러 메시지, 키보드 내비게이션, 테이블 정렬 |
| cart, payment, product | 이커머스 | 결제 흐름, CTA 명확성, 이미지 로딩, 신뢰 신호 |
| dashboard, metric, KPI | 어드민/대시보드 | 정보 밀도, 카드 계층, 필터 접근성, 실시간 갱신 |
| map, location, geo | 지도/위치 | 지도 인터랙션, 핀 가독성, 모바일 터치 영역 |

### ux-agenda.json 구조

```json
{
  "project": "auto-detected",
  "domain": "데이터 시각화",
  "detected_signals": ["d3.js", "force-graph", "node-link"],
  "agenda": [
    {
      "id": "UXA-001",
      "category": "가독성",
      "rule": "그래프 노드 라벨은 12px 이상, 배경 대비 4.5:1 이상",
      "severity": "P0",
      "auto_check": true
    }
  ],
  "evolved_by_meta": [],
  "version": 1
}
```

### 이슈 파이프라인 내 위치

```
agent-harness 완료 → UI_REVIEW 이슈 생성 → ux-harness
  ux-harness:
    1. ux-agenda.json 로드
    2. 변경 파일만 스캔
    3. 아젠다 항목별 pass/fail
    4. 전체 pass → on_complete → RUN_TESTS
       fail 있음 → UX_FIX 이슈 → agent-harness로 반환
```

### 담당 이슈 타입
- UI_REVIEW
- UX_FIX (재검증)
- ACCESSIBILITY_CHECK
- RESPONSIVE_CHECK

---

## 3. 실행 엔진 설계

### 3-1. CLAUDE.md 개선

프로젝트 CLAUDE.md가 Claude Code에게 명확한 실행 지침을 제공:
- 트리거 문구 인식 → harness-orchestrator 스킬 읽기
- Agent 도구로 에이전트 스폰 시 model 파라미터 지정
- registry.json 기반 이슈 라우팅

### 3-2. settings.json hooks

```json
{
  "hooks": {
    "postToolUse": [
      {
        "matcher": "Write|Edit",
        "command": "bash .claude/hooks/post-code-change.sh \"$TOOL_INPUT\""
      }
    ],
    "notification": [
      {
        "matcher": ".*",
        "command": "bash .claude/hooks/on-agent-complete.sh \"$AGENT_NAME\" \"$RESULT\""
      }
    ]
  }
}
```

### 3-3. 에이전트 간 통신 흐름

```
트리거 → CLAUDE.md 인식 → orchestrator 실행
  → Phase 1-6 (분석/패턴선택/이슈초기화/hook등록/팀구성/시작)
  → ISS-001 생성 → agent-harness 스폰 (Opus)
  → 코드 생성 완료 → on_complete.sh
    → UI_REVIEW + RUN_TESTS 이슈 생성
    → ux-harness (Sonnet) + test-harness (Sonnet) 병렬 스폰
  → 둘 다 완료 → SCORE 이슈 → eval-harness (Sonnet)
  → 점수 >= 70 → DEPLOY_READY → cicd-harness (Sonnet)
  → 전체 완료 → on_learn → meta-agent 학습
```

### 3-4. Meta Agent 30분 관찰

CronCreate 도구로 30분 주기 등록:
- meta-agent를 Opus로 스폰
- registry.json + ux-agenda.json 분석
- 패턴 탐지 → 이슈/아젠다 진화

### 3-5. Hook Router (Haiku)

registry.json에서 READY 이슈 탐색 → assign_to 확인 → 다음 에이전트 스폰 알림.
최소 비용으로 이슈 라우팅만 담당.

### 3-6. install.sh 추가 항목

기존:
- 전역 agents/skills 복사
- 프로젝트 CLAUDE.md/hooks/issue-db 생성

추가:
- .claude/settings.json 생성 (hooks 등록)
- ux-agenda.json 초기 템플릿 생성
- 에이전트 .md에 model 필드 주입
- post-code-change.sh 생성
- on-agent-complete.sh 생성

---

## 4. 자율 진화 메커니즘

### 진화의 3축

#### ① 이슈 패턴 진화

기존 5가지 패턴 + 신규 2가지:
- 기존: 반복 실패, 성능 저하, 이슈 폭발, 병목, 장기 미해결
- 신규: UX fail 반복 → 아젠다 규칙 강화
- 신규: 에이전트 간 핑퐁 3회 → 근본 원인 분석

#### ② UX 아젠다 진화

meta-agent 30분 관찰 시:
1. UX 이슈 fail 항목 집계
2. 패턴 분류:
   - 반복 fail (3회+) → 규칙 구체화
   - 새 컴포넌트 유형 감지 → 아젠다 항목 추가
   - pass 연속 5회 → severity 낮춤 + auto_check 전환
3. ux-agenda.json version 증가 + 변경 이력 기록

진화 예시:
```
v1: "폼 입력 필드 가독성 확보" — P1
v2: "input: border-gray-300, text-sm, py-2.5 필수" — P0 (fail 반복 후)
v3: severity P0→P1, auto_check: true (안정화 후)
```

#### ③ 시스템 자체 진화

장기 관찰 데이터에서 시스템 수준 개선 발견:
- agent-harness UI_REVIEW fail율 높음 → ux 체크리스트 사전 주입 제안
- test-harness 처리 시간 증가 → 테스트 범위 최적화 제안

### knowledge DB 확장

```json
{
  "knowledge": {
    "success_patterns": [
      { "pattern": "...", "context": "...", "frequency": 12, "discovered_at": "..." }
    ],
    "failure_patterns": [
      { "pattern": "...", "root_cause": "...", "solution": "...", "frequency": 8 }
    ],
    "meta_observations": [
      { "cycle": 5, "timestamp": "...", "findings": "...", "actions_taken": [] }
    ],
    "ux_agenda_history": [
      { "version": 1, "item_count": 5, "created_at": "...", "trigger": "auto-detect" },
      { "version": 2, "item_count": 7, "created_at": "...", "trigger": "meta-agent cycle 3" }
    ]
  }
}
```

### 진화 안전장치

| 제한 | 값 | 이유 |
|------|---|------|
| 주기당 이슈 생성 | 최대 5개 | 자기 증식 방지 |
| 이슈 깊이 | 최대 3단계 | 파생 폭발 방지 |
| 아젠다 항목 | 최대 20개/프로젝트 | 검증 비용 제한 |
| 아젠다 변경 | 주기당 최대 3개 항목 | 급격한 기준 변동 방지 |
| 유사 이슈 | 중복 생성 금지 | 노이즈 방지 |
| severity 강등 | pass 5회 연속 필요 | 성급한 완화 방지 |

---

## 5. 파일 변경 목록

### 신규 파일
- `global/agents/ux-harness.md` — UX 검증 에이전트 스펙
- `global/agents/hook-router.md` — 경량 라우팅 에이전트 스펙
- `global/skills/ux-agenda-generator/skill.md` — 도메인 분석/아젠다 생성
- `project/.claude/hooks/post-code-change.sh` — 코드 변경 감지
- `project/.claude/hooks/on-agent-complete.sh` — 에이전트 완료 감지
- `project/.claude/settings.json` — Claude Code hooks 설정
- `project/.claude/issue-db/ux-agenda.json` — UX 아젠다 템플릿

### 수정 파일
- `global/agents/agent-harness.md` — model: opus 추가, UI_REVIEW 파생 규칙 추가
- `global/agents/test-harness.md` — model: sonnet 추가
- `global/agents/eval-harness.md` — model: sonnet 추가
- `global/agents/cicd-harness.md` — model: sonnet 추가
- `global/agents/meta-agent.md` — model: opus 추가, UX 아젠다 진화 로직 추가
- `global/agents/qa-reviewer.md` — model: sonnet 추가
- `global/skills/harness-orchestrator/skill.md` — Agent 도구 스폰 절차, ux-harness 포함
- `global/skills/meta-evolution/skill.md` — UX 아젠다 진화 패턴 2개 추가
- `project/.claude/CLAUDE.md` — 실행 방법 구체화, 에이전트 스폰 규칙 추가
- `project/.claude/hooks/on_complete.sh` — UI_REVIEW 파생 이슈 추가
- `install.sh` — settings.json/ux-agenda.json 생성 추가
- `README.md` — v2 변경사항 반영

---

## 6. 설치 및 사용

```bash
git clone https://github.com/myaji35/GH_Harness.git
cd GH_Harness
chmod +x install.sh
./install.sh
```

프로젝트 디렉토리에서:
```
"Harness 개념으로 프로젝트를 실행하자"
```

자동으로:
1. 프로젝트 분석 → 도메인 추론
2. UX 아젠다 자동 생성
3. 에이전트 팀 구성 (모델 차등 배치)
4. 이슈 기반 파이프라인 시작
5. Meta Agent 30분 관찰 루프 등록
