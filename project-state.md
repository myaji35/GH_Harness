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
- 2026-07-08 fix: Hermes 자율운영 데몬 (launchd 외장볼륨 제약 우회)
- 2026-07-08 fix: Hermes launchd 전환 + PATH 주입 (cron 미발화 근본 수정)
- 2026-07-08 chore: graphify-obsidian-input 산출물 gitignore
- 2026-07-08 docs: Agent OS 웹앱 설계 스펙 (0000_master 흡수, localhost:3737)
- 2026-07-08 feat: Hermes 22개 프로젝트 순회 자문 (관제탑)
- 2026-07-08 feat: Hermes 무인 운영 (Claude Code 기반, 구독토큰 전용)
- 2026-07-08 feat: Agent OS 4모듈 구현 (moa/learn/journey/hub)
- 2026-07-08 docs: Agent OS 설계 스펙 추가 (GH_Harness 확장, 3영상 기반)
<!-- GITLOG_END -->

## 6. 살아있는 이슈 (READY/IN_PROGRESS, 자동 갱신)
<!-- ISSUES_BEGIN -->
- **[IN_PROGRESS]** ISS-384 (FIX_BUG) [P0] — [지시] ISS-383 [지시] 리눅스 환경에는 처음 등록해 보는거야. 그러니까 해당명령어에 버그는 없는 지가 1차 테스트 목적이야. 이슈를 처
<!-- ISSUES_END -->

---
_마지막 갱신: 2026-07-14 18:24_
