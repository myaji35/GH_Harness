# GH_Harness v4 업그레이드 기획안

**작성일**: 2026-04-22
**작성자**: Claude Code (Opus 4.7 1M)
**승인**: 강승식 대표 (2026-04-22, C안)
**상태**: Phase 4.1 착수

---

## 0. 요약 (TL;DR)

- **왜**: LangChain 벤치 결과 — 모델 고정 상태에서 harness만 바꿔도 52.8% → 66.5%. 즉 성능의 절반 이상이 harness 설계에 달려있다.
- **무엇**: 레퍼런스 3종(Fowler / LangChain / NxCode 2026)을 교차 매핑한 결과, 현 GH_Harness v3는 **Observability / Sandbox / Computational Sensor 강제 게이트 / Ralph Loop** 4개 영역이 부재.
- **어떻게**: 3-Phase (4.1 관찰가능성·결정성 → 4.2 장기자율성 → 4.3 Fitness·Auto-Rollback). Phase 4.1부터 즉시 착수.
- **기간**: 4.1 2주 / 4.2 3주 / 4.3 4주. 총 9주.

---

## 1. 참조 프레임워크 (3종)

### 1.1 Martin Fowler — Guides & Sensors

- **Agent = Model + Harness**. Harness = 모델 제외한 모든 것
- **빌더 하네스** (Anthropic/OpenAI 제공) + **사용자 하네스** (우리가 만드는 GH_Harness)
- 2대 축:
  - **Guides (피드포워드)**: LSP, 타입체커, AGENTS.md, 부트스트랩 스킬
  - **Sensors (피드백)**: 정적 분석, ESLint, AI 코드 리뷰, LLM-as-judge
- 3 Harness 카테고리:
  - Maintainability (가장 성숙) / Architecture Fitness / **Behaviour (미성숙)**
- **Keep Quality Left**: 커밋 전 → 파이프라인 → 런타임 모니터링 배치
- **Anti-pattern**:
  - 피드백만 → 같은 실수 반복
  - 피드포워드만 → 실제 작동 검증 불가
  - 불일치 신호 → 에이전트 판단 실패
  - **하네스 표류**: Guides와 Sensors가 동기화 안 됨

### 1.2 LangChain — Agent Harness 해부학 (6요소)

| 요소 | 정의 | 핵심 실패 모드 | 권장 구현 |
|---|---|---|---|
| **Context** | 컨텍스트 윈도우 내 정보 주입 | Context Rot | Compaction / Tool offloading / Progressive disclosure |
| **Tool** | 범용 bash + code execution | 도구 변경 시 오버피팅 | 샌드박스 내 범용 실행 + git/browser 기본 제공 |
| **Planning** | 목표를 단계로 분해 | 조기 종료 / 다윈도우 일관성 상실 | 파일시스템 계획 파일 + **Ralph Loop** |
| **Verification** | 자가 검증 루프 | 오류 누적 | 테스트 스위트 + 로그/스크린샷 관찰 |
| **Memory** | 세션 초과 작업 지속 | 지식 단절 | AGENTS.md + Git + Web Search/MCP |
| **Sandbox** | 격리 실행 환경 | 로컬 실행 보안 침해 / 상태 오염 | 네트워크 격리 + 명령 whitelist + 온디맨드 |

### 1.3 NxCode 2026 — 5 Pillars + Production Checklist

**5 Pillars**:
1. Tool Orchestration
2. Guardrails & Safety Constraints
3. **Error Recovery & Feedback Loops** (auto retry, loop detection, rollback)
4. **Observability** (로깅/토큰/결정/이상치)
5. **HITL Checkpoints** (전략적 승인 게이트)

**6-Step Production Checklist**:
- [ ] Define scope: agent can / cannot do
- [ ] Configuration file with conventions
- [ ] Feedback loop (min: write-test-fix cycle)
- [ ] Guardrails (linting, destructive command block)
- [ ] Observability (actions, tool calls, token usage)
- [ ] Human checkpoints (prod data, infra, security)

**2026 핵심 업그레이드 포인트**:
- **세션 메모리 부재** → 설정 파일·아티팩트로 브리징
- **Silent failure** → 검증 루프는 옵션 아닌 필수
- **병렬 실행 복잡도** → 10개 에이전트 캐스케이딩 실패는 observability 없이 디버깅 불가

---

## 2. GH_Harness v3 현황 및 갭 분석

### 2.1 보유 자산

| 자산 | 위치 | 상태 |
|---|---|---|
| 24개 에이전트 | `global/agents/*.md` | ✅ 운영 중 |
| 2축 구조 (plan/check) | `plan-harness.md`, `check-harness.md` | ✅ Phase 1 완료, Codex 전환은 Phase 2 대기 |
| 이슈 레지스트리 | `.claude/issue-db/registry.json` | ✅ ISS-201로 중복 ID·핑퐁 가드 완비 |
| Hook 이벤트 브로커 | `.claude/hooks/*.sh` (23개) | ✅ 운영 중 |
| T0/T1/T2 Tier | CLAUDE.md 자율 실행 원칙 | ✅ 운영 중 |
| Opus 예산 가드 | `opus-budget-check.sh` | ✅ Soft/Hard Cap |
| Freeze-guard | `freeze-guard.sh` | ✅ 편집 범위 제한 |
| Hermes/Advisor | 내부 자문 경로 | ✅ 운영 중 |
| Screen Gap Scan | `screen-gap-scan.sh` | ✅ 비즈니스 결함 탐지 |
| Proactive Scan | `proactive-scan.sh` | ✅ 코드 결함 탐지 |

### 2.2 갭 테이블 (6요소 × 3프레임 교차)

| 영역 | v3 상태 | 갭 | 우선순위 |
|---|---|---|---|
| **Context** | CLAUDE.md + brand-dna.json 주입 | Compaction, Tool call offloading 없음 | **P0** |
| **Tool** | bash + 23 hook | 샌드박스 격리 없음 (로컬 FS 직접 변조) | **P0** |
| **Planning** | 이슈 트리 (parent_id, depth≤3) | 파일시스템 계획 파일, Ralph Loop 없음 | P1 |
| **Verification** | test-harness 체인 + LLM-as-judge | **계산적 sensor 강제 게이트 부재** (lint/type 실패해도 통과 가능) | **P0** |
| **Memory** | `~/.claude/projects/.../memory/` | Git 이력 연동, artifact 재사용 빈약 | P2 |
| **Sandbox** | 없음 | **부재** (careful/freeze는 사용자 메모리 의존) | **P0** |
| **Observability** | hook 로그 + registry | **통합 대시보드 없음**, 토큰/결정/이상치 집계 부재 | **P0** |
| **Guardrails** | freeze + T2 + budget | Rate limiting 없음, 명령 whitelist 외부화 안 됨 | P1 |
| **Error Recovery** | on_fail + hermes + ISS-201 loop guard | 자동 rollback 없음 | P1 |
| **HITL Checkpoint** | T2 5개 카테고리 | ✅ 양호 | - |
| **Behaviour Harness** | scenario-player, journey-validator | Fitness function 공식화 부재 | P2 |
| **Architecture Fitness** | 없음 | 성능 SLO, 레이어 경계, 로깅 표준 자동 검증 부재 | P2 |

### 2.3 핵심 갭 요약

**P0 4개** — Phase 4.1 즉시 착수 대상:
- Observability Dashboard (없으면 10-agent 디버깅 불가)
- Computational Sensor 강제 게이트 (Silent failure 방지)
- Sandbox Provisioning (파괴적 명령 executor 차단)
- Decision Trace (JSONL 시계열)

**P1 5개** — Phase 4.2:
- Plan-File 기반 Planning
- Context Compaction
- Tool Output Offloading
- Ralph Loop Guard
- Command Whitelist 외부화

**P2 4개** — Phase 4.3:
- Fitness Function 레지스트리
- Automatic Rollback
- Drift Detection
- Benchmark Harness

---

## 3. Phase 4.1 — 관찰가능성 + 결정성 (2주)

### 목표
- 10-agent 캐스케이딩 실패를 **5분 내 디버깅 가능**
- Silent failure 자동 차단 (lint/type-check 게이트 필수화)
- 파괴적 명령 executor 레벨 차단
- 모든 이슈 라이프사이클 JSONL 기록

### 산출물 (4개)

#### A. Observability Dashboard
- **무엇**: `.claude/hooks/dashboard.sh` 단일 커맨드로 현재 harness 상태 집계
- **내용**:
  - READY / IN_PROGRESS / COMPLETED 이슈 카운트
  - 에이전트별 성공률 (최근 24h / 7d)
  - Opus 예산 소진율 + 이번 세션 토큰 추정
  - 핑퐁 의심 패턴 (ISS-201 가드 결과)
  - 최근 실패 이슈 5개 + 실패 이유
- **출력**: 터미널 ANSI 컬러 대시보드 + 옵션 `--json`로 기계 읽기
- **위치**: `global/hooks/dashboard.sh`

#### B. Computational Sensor 강제 게이트
- **무엇**: `on_complete.sh`의 GENERATE_CODE/FIX_BUG/BIZ_FIX 분기를 재작성
- **변경**: lint/type-check를 "병렬 체인"이 아닌 **블로킹 게이트**로
  - 실패 시 DEPLOY_READY/SCORE 진입 차단
  - 자동 STYLE_FIX P0 생성 + 원본 이슈는 BLOCKED 상태
  - 3회 연속 실패 시 hermes-escalate
- **위치**: `project/.claude/hooks/on_complete.sh` (installer가 프로젝트에 복사)

#### C. Sandbox Provisioning (C-lite 선행 + C-full 후행)
- **C-lite (이번 phase)**:
  - `SANDBOX_POLICY.md` 정책 문서 (허용/차단 명령 명시)
  - `sandbox-enforce.sh` PreToolUse hook — Bash 도구 호출 전 정규식 검사
  - 차단 명령: `rm -rf /`, `DROP TABLE`, `git push -f`, `chmod -R 777`, `curl ... | sh`, `:(){:|:&};:`
  - 경고 명령: `git reset --hard`, `kubectl delete`, `npm publish`
  - 정책 위반 시 T2 컨펌 요구
- **C-full (Phase 4.2로 이관)**: Docker/Firejail 기반 실제 격리
- **위치**: `global/policy/SANDBOX_POLICY.md` + `project/.claude/hooks/sandbox-enforce.sh`

#### D. Decision Trace
- **무엇**: 이슈 라이프사이클 이벤트를 JSONL로 append
- **이벤트**: `created` / `dispatched` / `started` / `paused` / `resumed` / `completed` / `failed` / `blocked`
- **스키마**:
  ```json
  {"ts":"2026-04-22T10:30:00Z","issue":"ISS-091","event":"dispatched","agent":"agent-harness","model":"sonnet","tier":"T0"}
  ```
- **위치**: `project/.claude/trace/YYYY-MM-DD.jsonl`
- **연동**: dashboard.sh가 이 파일을 집계원으로 사용
- **위치**: `project/.claude/hooks/decision-trace.sh`

### 일정 (Phase 4.1)

| 주차 | 산출물 | 검증 |
|---|---|---|
| **Week 1** | D (Decision Trace) → B (강제 게이트) | 0012_InsureGraph Pro에서 실제 이슈 10개 처리 로그 수집 |
| **Week 2** | A (Dashboard) → C-lite (Sandbox Policy) | 5개 프로젝트에 전파 + install.sh 업데이트 |

---

## 4. Phase 4.2 — 장기 자율성 (3주)

### 목표
- 200K 컨텍스트 70% 도달 시 자동 compaction → 새 세션 이관
- 8KB+ 출력 자동 offload → 참조 path만 주입
- 조기 종료 방지 (Ralph Loop Guard)
- 명령 정책 외부화 (.claude/policy/commands.yaml)

### 산출물 (5개)
- E. Plan-File 기반 Planning (이슈당 `.claude/plans/ISS-XXX.md`)
- F. Context Compaction (session-resume.sh 확장)
- G. Tool Output Offloading (`.claude/artifacts/`)
- H. Ralph Loop Guard (dispatch-ready.sh retry)
- I. Command Whitelist (policy/commands.yaml)

---

## 5. Phase 4.3 — Fitness + Auto-Rollback (4주)

### 목표
- Fowler의 Architecture Fitness 실현
- DEPLOY_READY 실패 시 auto-rollback 제안
- Drift Detection (Guides vs Sensors 주 1회 감사)

### 산출물 (4개)
- J. Fitness Function 레지스트리 (`fitness/*.yaml`)
- K. Automatic Rollback (cicd-harness.md 개선)
- L. Drift Detection (신규 agent: drift-auditor)
- M. Benchmark Harness (LangChain식 A/B)

---

## 6. 성공 지표 (KPI)

| 지표 | v3 baseline | v4 target (Phase 4.1 후) | 측정 방법 |
|---|---|---|---|
| 이슈 평균 해결 시간 | 측정 불가 | 측정 가능 + 20% 단축 | decision-trace.jsonl |
| Silent failure 건수 | 미상 | 0건 | B 게이트 로그 |
| 파괴적 명령 실행 | 미상 | 0건 | sandbox-enforce.sh 차단 로그 |
| 이슈 당 토큰 소비 | 측정 불가 | 측정 가능 | dashboard.sh |
| 핑퐁 감지 정확도 | ISS-201 가드 (3건 이상) | 2건부터 경고 | dispatch-ready.sh 개선 |

---

## 7. 리스크 & 완화

| 리스크 | 영향 | 완화 |
|---|---|---|
| Sandbox가 정상 명령을 오탐 | 생산성 저하 | PreToolUse 경고만 + T2로 우회 가능 |
| Dashboard가 컨텍스트 소모 | 토큰 비용 증가 | `--json` 옵션으로 파싱만, 기본 출력은 간결하게 |
| 강제 게이트로 파이프라인 정체 | 긴급 배포 지연 | `HARNESS_BYPASS_GATE=1` 환경변수로 T2 승인 후 우회 |
| 9주 전체 완성 전 중간 상태 불일치 | 일부 프로젝트만 v4 | install.sh가 backward-compat 보장 (v3 registry.json 자동 마이그레이션) |

---

## 8. 롤백 전략

각 Phase 전에 `GH_Harness` 전체 git tag:
- `v3.2-final` (업그레이드 직전)
- `v4.1-rc1`, `v4.1-final`
- `v4.2-rc1`, `v4.2-final`
- `v4.3-rc1`, `v4.3-final`

문제 발생 시 `install.sh --rollback v3.2-final`로 전 프로젝트 일괄 복원.

---

## 9. 대표님 승인 사항

- [x] 2026-04-22: C안 승인 — 기획 문서 작성 + Phase 4.1 전체 착수
- [ ] Phase 4.1 완료 시 검토 후 4.2 착수 여부 결정
- [ ] Phase 4.2 완료 시 검토 후 4.3 착수 여부 결정

---

## 10. 참고 문헌

1. Martin Fowler — [Harness engineering for coding agent users](https://martinfowler.com/articles/harness-engineering.html)
2. LangChain — [The Anatomy of an Agent Harness](https://www.langchain.com/blog/the-anatomy-of-an-agent-harness)
3. NxCode — [What Is Harness Engineering? Complete Guide 2026](https://www.nxcode.io/resources/news/what-is-harness-engineering-complete-guide-2026)
4. OpenAI — [Harness engineering: leveraging Codex in an agent-first world](https://openai.com/index/harness-engineering/) (원문 403, NxCode 재인용)
5. Claude Code 한국어 공식 문서 — [Claude Code의 작동 방식](https://code.claude.com/docs/ko/how-claude-code-works)
6. revfactory/harness — [한국어 README](https://github.com/revfactory/harness/blob/main/README_KO.md)
