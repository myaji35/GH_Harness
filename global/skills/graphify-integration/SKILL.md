---
name: graphify-integration
description: 코드 수정 전 knowledge graph 조회로 의존성 맹점 제거 + 토큰 절감. 프로젝트에 .claude/graphify/ 존재 시에만 활성.
---

# Graphify Integration (GH_Harness)

## 언제 쓰나
- agent-harness가 GENERATE_CODE / REFACTOR / FIX_BUG 이슈 claim 직후
- qa-reviewer가 교차 검증 시 변경 영향 범위 확인

## 게이트
```bash
test -d .claude/graphify || exit 0   # 미설치 → skip
```

## 질의 패턴
```bash
/graphify query <symbol>     # 호출/정의 그래프
/graphify related <file>     # 같은 서브그래프 내 파일 Top-5
/graphify impact <file>      # 변경 시 영향 파일 목록
```

## 메트릭 기록 (필수)
각 질의 종료 시 `.claude/graphify/metrics.jsonl`에 1줄 append:
```json
{"ts":"2026-04-14T10:00:00Z","issue_id":"ISS-123","query":"impact","target":"src/x.ts","tokens_saved_est":4200,"hit":true}
```

## 리포트 생성 (7일 주기)
- `baseline.json` vs `metrics.jsonl` 비교 → `report.md`
- Phase 1 완료 게이트: token_reduction >= 30% AND qa_pass_rate >= 95%

## 적합 이슈
- 2+ 파일 수정
- 공용 유틸/타입 변경
- API 계약 변경

## 부적합 이슈
- README·주석만 수정
- 단일 파일 오타 수정
