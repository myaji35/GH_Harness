# Project State — GH_Harness

> 이 파일은 SessionStart에 자동 로드됩니다. 프로젝트의 살아있는 맥락입니다.
> Harness hook이 자동 갱신하며, 수동 편집도 허용됩니다.

## 1. 지금 만들고 있는 것
<!-- 한 문장으로. 대표님이 직접 작성하거나 product-manager가 갱신 -->
_(아직 정의되지 않음 — 'harness 시작'으로 FEATURE_PLAN을 만들어 주세요)_

## 2. 최근 결정사항 (최신순, 최대 20개)
<!-- DECISIONS_BEGIN -->
- **2026-04-16 17:42** — Screen Gap Scanner(화면 갭 스캐너) 도입 — 라우트/메뉴 구조에서 빠진 비즈니스 기능 자동 탐지, SCREEN_GAP 이슈 → USER_STORY 파이프라인 구축
- **2026-04-16 09:47** — 2축 아키텍처(PLAN/CHECK) 도입 — plan-harness + check-harness 신설, 기존 22개는 모드 프로파일로 보존. codex-check.sh 스켈레톤 배포(비활성). 토큰 절약 + Codex 전환 준비
- **2026-04-15 19:47** — GraphRAG 3원칙(Entity Resolution+하이브리드 스키마+증분 업데이트) 가이드 13개 프로젝트 전파
- **2026-04-15 13:04** — 2026.zip 분실 incident — 원본 삭제 확인, 심볼릭 링크만 잔존. 복구는 보류(옵션3). macOS 26.4.1 업그레이드 우선.
- **2026-04-15 09:04** — Phase 1 적용: design-critic opus→sonnet 강등, /advisor 커맨드 신설, project-state.md 도입
<!-- DECISIONS_END -->

## 3. 미해결 질문
<!-- OPEN_QUESTIONS_BEGIN -->
- _(없음)_
<!-- OPEN_QUESTIONS_END -->

## 4. 다음 마일스톤
<!-- MILESTONES_BEGIN -->
- _(미정)_
<!-- MILESTONES_END -->

## 5. 최근 변경 이력 (git log, 자동 갱신)
<!-- GITLOG_BEGIN -->
- 2026-04-14 docs(incident): 사용자 명시값 무시 incident + CLAUDE.md 규칙 추가
- 2026-04-14 Revert "feat(harness): Gemma 로컬 토글 + keep_alive 전략 (로컬 30m / 배포 영구)"
- 2026-04-14 Revert "feat(harness): Gemma 4 E4B 로컬 LLM 통합 — 'gemma 사용하자' 트리거"
- 2026-04-14 Revert "feat(harness): Gemma 4 E4B 안정화 (M2 16GB 전용 ultrathink 튜닝)"
- 2026-04-14 feat(harness): Gemma 4 E4B 안정화 (M2 16GB 전용 ultrathink 튜닝)
- 2026-04-14 feat(harness): Gemma 로컬 토글 + keep_alive 전략 (로컬 30m / 배포 영구)
- 2026-04-14 feat(harness): Gemma 4 E4B 로컬 LLM 통합 — 'gemma 사용하자' 트리거
- 2026-04-14 feat(harness): Graphify 통합 + Pre-Delivery 검증 훅 + LLM Wiki lane
- 2026-04-13 feat(harness): 토큰 최적화 프로파일 --optimize-tokens 추가
- 2026-04-10 feat(harness): VIEW_AUDIT + 비즈니스 로직 점검 통합 트리거
- 2026-04-10 fix: 듀얼 랜딩 맹점 인시던트 보고서 + design-critic 다크 배경 가독성 체크 추가
- 2026-04-10 feat(harness): brand-dna 템플릿에 motion/animation 확장 토큰 반영
- 2026-04-10 feat(harness): 10개 프로젝트 brand-dna 재구성 + motion/animation 토큰 확장
- 2026-04-10 feat(harness): Journey Validator — 사용자 여정/역할별/인팩트/온보딩 검증
- 2026-04-10 feat(harness): Design Token System — 프로젝트별 UI 개성 차별화
- 2026-04-10 fix(harness): 뻔한 후속 작업은 컨펌 없이 즉시 실행 원칙 추가
- 2026-04-10 feat(harness): install.sh v3 업그레이드 — 신규 에이전트/훅/디렉터리 배포 + CLI 우선 원칙
- 2026-04-10 feat(harness): v3 — Hermes/Advisor + 3-Tier 컨펌 + UI 5 Levels + Audience Researcher
<!-- GITLOG_END -->

## 6. 살아있는 이슈 (READY/IN_PROGRESS, 자동 갱신)
<!-- ISSUES_BEGIN -->
- _(살아있는 이슈 없음 — 새 기획 필요)_
<!-- ISSUES_END -->

---
_마지막 갱신: 2026-04-16 17:42_
