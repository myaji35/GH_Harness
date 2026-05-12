# GH_Harness Wiki

> Self-Evolving Harness System — 코드 위키 (g3doc 스타일)

## 위키 목적

GH_Harness 프로젝트의 모든 문서를 검색 가능한 단일 위키로 통합. 에이전트(Claude/Codex)와 사람 모두가 grep 대신 풀텍스트 검색으로 컨텍스트를 빠르게 확보하는 것이 목표.

## 주요 카테고리

- **Architecture** — 이슈 스키마, 워크트리 워크플로우, 디자인 결정
- **Incidents** — 사후 보고서 (대표님이 직접 발견한 문제 + 회고)
- **Specs** — 파일럿 명세서
- **Agents** — 22+ 에이전트 카탈로그 (별도 페이지: `agents.md`)

## 하위 도메인 (서브폴더)

- `audience/` — 타겟 오디언스 리서치 산출물
- `brand/` — 브랜드 DNA 정의
- `llm-wiki/` — LLM 운용 노하우
- `superpowers/` — 강화된 능력 명세
- `ui-snapshots/` — UI 변경 추적

## 검색 사용법

- 우상단 검색창에 키워드 입력 → 한국어/영어 모두 인덱싱됨
- 예시: `hermes`, `race-mode`, `incident`, `freeze`

## 새 문서 추가 (기여 방법)

1. `docs/` 또는 하위 폴더에 `.md` 파일 추가
2. 첫 줄에 `# 제목` (H1) 작성 → 카탈로그/네비게이션에 자동 반영
3. PR로 리뷰 후 머지 → `mkdocs build --strict` 통과 시 위키 자동 갱신
4. 사이드바에 노출하려면 `mkdocs.yml`의 `nav:` 블록에도 추가 (선택)

## 자동 생성된 문서 카탈로그

> 아래는 빌드 시점의 docs/ 트리. mkdocs Material의 자동 트리가 사이드바에 동일하게 표시됨.
> 새 .md 추가 시 사이드바는 자동 갱신되지만, 이 카탈로그는 **빌드 시 mkdocs-gen-files 또는 수동 갱신** 필요.

### 루트 문서 (Architecture · Incidents · Specs)

- [Issue Schema v4](issue-schema-v4.md) — Harness 이슈 DB 스키마
- [V4 Upgrade Plan](v4-upgrade-plan.md) — 2축(Plan/Check) 업그레이드 계획
- [Race Mode Design](race-mode-design.md) — 멀티 LLM 경쟁 실행 설계
- [GraphRAG Principles](graphrag-principles.md) — 지식 그래프 3원칙
- [Worktree Workflow](worktree-workflow.md) — 격리 워크트리 운용
- [Graphify Phase1 Pilot](graphify-phase1-pilot.md) — 그래파이 파일럿 명세
- [Incident: Dual Landing Blindspot](incident-report-dual-landing-blindspot.md)
- [Incident: User Explicit Value Override](incident-report-user-explicit-value-override.md)

### 하위 도메인

- [Audience Research](audience/) — 오디언스 리서치
- [Brand DNA](brand/) — 브랜드 정체성
- [LLM Wiki](llm-wiki/) — LLM 운용 노하우
- [Superpowers](superpowers/) — 강화 능력 명세
- [UI Snapshots](ui-snapshots/) — UI 변경 기록

---

> **묘비 효과 차단 정책**: 본 위키는 6개월 미수정 문서를 자동 STALE 라벨링한다 (Phase 2 검증 hook). 새 문서 추가 시 `mkdocs serve` 로 즉시 확인할 것.
