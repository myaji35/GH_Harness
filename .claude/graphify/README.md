# Graphify Meta-KG — GH_Harness

하네스 자체의 구조를 그래프화한다.

## 노드 타입
- Agent (22개): product-manager, plan-ceo-reviewer, agent-harness, ...
- Hook (약 20개): on_complete.sh, dispatch-ready.sh, axis-router.sh, ...
- IssueType (30+): FEATURE_PLAN, GENERATE_CODE, BIZ_VALIDATE, ...
- AxisMode: plan-harness:product / check-harness:biz / ...
- Skill: harness-orchestrator, graphify, harness-ui-trends-2026, ...

## 엣지 타입
- handles (Agent → IssueType)
- spawns (IssueType → IssueType via Hook)
- routes_to (IssueType → AxisMode)
- triggers (Hook → Hook)
- provides (Skill → Agent)

## 활용 (Phase 2)
- axis-router.sh: 이슈 타입 → 가장 가까운 AxisMode 경로 자동 추천
- meta-review.sh: 7패턴 대신 그래프에서 "비정상 사이클" 탐지
- 신규 에이전트 추가 시 "이 에이전트가 채우는 공백이 어디인가" 시각화

## 최초 빌드
```bash
cd /Volumes/E_SSD/02_GitHub.nosync/GH_Harness
/graphify . --mode deep --no-viz   # 또는 수동 노드/엣지 JSON 작성
```

## 게이트 (Phase 1 → 2)
- 라우팅 정확도 95% 이상
- meta-review 노이즈 20% 이상 감소
