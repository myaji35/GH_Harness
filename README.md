# GH_Harness — Self-Evolving Agent Harness System

> Claude Code를 위한 자율 진화형 에이전트 하네스 시스템

harness-100의 프로덕션 패턴 + Hook 이벤트 시스템 + 자율 이슈 생성을 결합한  
스스로 발전하는 멀티 하네스 운영 체계입니다.

---

## 설치 (1분)

```bash
git clone https://github.com/myaji35/GH_Harness.git
cd GH_Harness
chmod +x install.sh
./install.sh
```

설치 스크립트가 자동으로:
- **전역 설정** → `~/.claude/` (모든 프로젝트에서 사용 가능)
- **프로젝트 설정** → `현재 디렉토리/.claude/` (현재 프로젝트에만 적용)

---

## 사용법

프로젝트 디렉토리에서 Claude Code 실행 후:

```
"Harness 개념으로 프로젝트를 실행하자"
```

이 한 마디로 시스템이 자동으로:
1. 프로젝트 분석 → 아키텍처 패턴 선택
2. 6개 에이전트 팀 구성
3. 이슈 레지스트리 초기화
4. Hook 이벤트 브로커 등록
5. Meta Agent 관찰 시작
6. 자율 진화 루프 시작

---

## 시스템 구조

```
GH_Harness/
├── install.sh              ← 설치 스크립트
├── global/                 ← 전역 설치 (~/.claude/)
│   ├── agents/             ← 6개 전문 에이전트
│   │   ├── agent-harness.md
│   │   ├── test-harness.md
│   │   ├── eval-harness.md
│   │   ├── cicd-harness.md
│   │   ├── meta-agent.md
│   │   └── qa-reviewer.md
│   └── skills/             ← 5개 핵심 스킬
│       ├── harness-orchestrator/
│       ├── hook-registry/
│       ├── issue-registry/
│       ├── progressive-disclosure/
│       └── meta-evolution/
└── project/                ← 프로젝트 설치 (./.claude/)
    └── .claude/
        ├── CLAUDE.md       ← 트리거 진입점
        ├── hooks/          ← Hook 이벤트 핸들러
        └── issue-db/       ← 이슈 레지스트리 DB
```

---

## 핵심 개념

### 4개 하네스
| 하네스 | 역할 | 담당 이슈 타입 |
|--------|------|--------------|
| Agent Harness | 코드 생성 | GENERATE_CODE, REFACTOR, FIX_BUG |
| Test Harness | 검증 | RUN_TESTS, RETEST, COVERAGE_CHECK |
| Eval Harness | 품질 측정 | SCORE, REGRESSION_CHECK |
| CI/CD Harness | 배포 | DEPLOY_READY, ROLLBACK |

### Hook 이벤트
```
on_create  → 이슈 생성 시 자동 라우팅
on_start   → 처리 시작 시 컨텍스트 준비
on_complete → 완료 시 파생 이슈 자동 생성
on_fail    → 실패 시 재시도 또는 에스컬레이션
on_learn   → Meta Agent 학습 트리거
```

### 자율 진화
- 이슈 완료 → 결과 분석 → 파생 이슈 자동 생성
- Meta Agent가 30분마다 패턴 관찰 → 개선 이슈 생성
- 반복 실패 감지 → 근본 원인 분석 이슈 에스컬레이션

---

## 아키텍처 패턴 (자동 선택)

| 작업 유형 | 패턴 | 설명 |
|----------|------|------|
| 순차 개발 | Pipeline | Agent→Test→Eval→CI/CD |
| 독립 모듈 | Fan-out/Fan-in | 병렬 처리 후 통합 |
| 전문가 필요 | Expert Pool | 필요 시 전문가 호출 |
| 품질 중심 | Producer-Reviewer | 생성→QA 교차 검증 |
| 복잡한 작업 | Supervisor | Meta Agent 감독 |
| 대규모 | Hierarchical | 팀 안에 팀 |

---

## License
MIT
