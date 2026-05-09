# Graphify Phase 1 파일럿 운영 기록

**시작일:** 2026-04-17
**종료 평가일:** 2026-04-24 (7일 뒤)
**담당:** meta-agent + harness-orchestrator

## 스코프

| # | 대상 | 위치 | 성격 |
|---|---|---|---|
| A1 | **0014 Townin Graph** | `.claude/graphify/` | 프로젝트 코드 + 도메인 KG (H3, 머천트, 전단지 엔티티) |
| A2 | **0012 InsureGraph Pro** | `.claude/graphify/` | GraphRAG 본래 용도 — 보험 약관/규정 엔티티 |
| C1 | **GH_Harness meta-KG** | `.claude/graphify/` | 에이전트/훅/이슈타입 관계 |

## 최초 빌드 체크리스트

- [ ] A1: `cd "0014_Townin Graph" && /graphify app --mode deep`
- [ ] A2: `cd "0012_InsureGraph Pro" && /graphify src --mode deep`
- [ ] C1: `cd GH_Harness && /graphify . --mode deep --no-viz`

각 빌드 후 `graphify-out/GRAPH_REPORT.md` + `graph.json` 생성 확인.

## 일간 측정 항목 (자동)

`graphify-integration` 스킬이 각 질의마다 `.claude/graphify/metrics.jsonl`에 append:
```json
{"ts":"...","issue_id":"ISS-xxx","query":"impact|related|query","target":"...","tokens_saved_est":N,"hit":true|false}
```

## Phase 1 통과 게이트 (2026-04-24)

### A1 + A2 (프로젝트 파일럿)
- [ ] `token_reduction >= 30%` (KG 없는 같은 이슈와 비교)
- [ ] `qa_pass_rate >= 95%` (agent-harness 생성 코드가 첫 시도에서 테스트 통과)
- [ ] `hit_rate >= 70%` (질의한 심볼/파일이 KG에 실제 존재)

### C1 (메타 KG)
- [ ] `routing_accuracy >= 95%` (axis-router.sh가 KG 조회로 결정한 경로가 사람 판단과 일치)
- [ ] `meta-review 노이즈 -20%` (중복/쓸모없는 개선 이슈 감소)

## 실패 시 대응

1. **hit_rate < 70%** → KG 스탈. `--update` 재빌드 + 증분 자동화 우선 착수
2. **qa_pass_rate < 95%** → LLM이 KG 결과를 잘못 해석. 쿼리 프롬프트 튜닝
3. **token_reduction < 30%** → KG 조회 자체가 큼. 질의 범위 축소, Top-5 제한

## Phase 2 진입 시 작업 예정

- `on_complete.sh`에 "파일 10개 이상 변경 시 KG 자동 재빌드" 훅
- `axis-router.sh`가 meta-KG 쿼리로 AxisMode 추천
- 0017 SocialDoctors에 3번째 파일럿 확장 (PII 해싱 필수)
- `opus_budget_state`에 `graphify_savings` 라인 추가

## 운영 결정 (2026-04-17 A안 채택)

**A안: Graphify 단독 유지, Phase 1 지속.**

- GraphRAG 정석 이식은 이번 파일럿에 포함하지 않는다 (0012 InsureGraph 전용 과제로 분리)
- 0014 / GH_Harness 메타는 Graphify로 충분 — 내부 개발 지원 용도이고 사용자 질의 백엔드 아님
- 0012는 별도 이슈(FEATURE_PLAN)로 "GraphRAG 정석 로드맵"을 분리 발행 예정
- 7일 평가일(2026-04-24)에 게이트 기준으로 Phase 2 진입 여부 결정

## 활성화 로그 (2026-04-17)

| 대상 | 상태 | 노드 | 엣지 | 커뮤니티 | 비고 |
|---|---|---|---|---|---|
| **A1 0014** | ✅ 빌드 완료 (AST only) + 재클러스터링 + 상위 20 라벨 | 4,899 | 4,990 | 723 | INFERRED 엣지 0%, 고립 노드 1,498개 (MLflow Python 도크스트링) |
| **A2 0012** | ⏸ 미빌드 | - | - | - | 별도 세션에서 `/graphify src --mode deep --no-viz` 실행 예정 |
| **C1 meta** | ⏸ 미빌드 | - | - | - | 별도 세션에서 `/graphify global/agents docs --mode deep --no-viz` 실행 예정 |

### A1 0014 즉석 인사이트
1. **두 축 혼재**: `townin-platform/` (Flutter) + `pm4py-action-items/` (Python MLflow). 모노레포 분리 검토 여지
2. **C16 레거시 발견**: Neo4j 보험 도메인 서비스 잔재 (InsureGraph Pro 유산). 제거 or 명시 분리 필요
3. **C0 거대 커뮤니티 (n=294, cohesion 0.01)**: "Flutter 앱 코어"로 라벨했으나 응집도 낮음 → 실제로는 `flutter/material` 의존성 허브. 의미 분할 필요
4. **고립 노드 1,498개**: AST만 돌려 Python 도크스트링이 엣지 없이 뜸. `--mode deep` LLM 추출로 해결 예상

## 상태 대시보드 (일간 수동 업데이트)

| 날짜 | A1 hit_rate | A1 token_saved | A2 상태 | C1 상태 | 비고 |
|---|---|---|---|---|---|
| 04-17 | 기준선 (빌드만) | - | 미빌드 | 미빌드 | 활성화 + 재클러스터링 완료 |
| 04-18 | | | | | |
| 04-19 | | | | | |
| 04-20 | | | | | |
| 04-21 | | | | | |
| 04-22 | | | | | |
| 04-23 | | | | | |
| 04-24 | | | | | **평가일 — Phase 2 진입 여부 결정** |

## 다음 실행 명령 (대표님이 별도 세션에서)

```bash
# A2 — 0012 최초 빌드
cd "/Volumes/E_SSD/02_GitHub.nosync/0012_InsureGraph Pro"
/graphify src --mode deep --no-viz

# C1 — GH_Harness 메타 KG
cd /Volumes/E_SSD/02_GitHub.nosync/GH_Harness
/graphify global/agents docs --mode deep --no-viz

# A1 보강 — INFERRED 엣지 추가하고 싶을 때
cd "/Volumes/E_SSD/02_GitHub.nosync/0014_Townin Graph"
/graphify app --update --mode deep --no-viz
```

## graphify-integration 스킬 발동 조건 (확인)
- [x] 0014 `.claude/graphify/` 존재 → 자동 발동 ✓
- [x] 0012 `.claude/graphify/` 존재 → 자동 발동 ✓
- [x] GH_Harness `.claude/graphify/` 존재 → 자동 발동 ✓

이후 agent-harness가 GENERATE_CODE / REFACTOR / FIX_BUG 이슈 처리 시 자동으로 KG 조회. 각 질의마다 `metrics.jsonl`에 1줄 기록.
