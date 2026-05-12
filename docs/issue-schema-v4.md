# Issue Schema v4 — rubric 필드 공식 정의

> 버전: v4.0  
> 도입: 2026-05-12 (ISS-309)  
> 컨셉 출처: Anthropic Claude Managed Agents — Outcome (사전 루브릭 + 독립 채점)

---

## 개요

v4 스키마는 이슈 payload에 `rubric` 필드를 선택적(optional)으로 추가한다.  
rubric이 존재하는 이슈는 check-harness / eval-harness가 **동적 기준 대신 명시 rubric을 우선 참조**하여 채점한다.  
작업(PLAN)과 채점(CHECK)의 구조적 분리(2축 아키텍처)의 본질을 강화하는 필드다.

---

## rubric 필드 스키마

```json
{
  "rubric": {
    "criteria": ["문자열 배열 — 측정 가능한 성공 기준 (3~5개 권장)"],
    "threshold": "string — 통과 조건 (예: '4/4 충족' / '점수 ≥ 70' / 'all PASS')",
    "scorer_axis": "CHECK | PLAN — 독립 채점 축 (기본 CHECK)",
    "optional": true
  }
}
```

### 필드 설명

| 필드 | 타입 | 필수 | 설명 |
|---|---|---|---|
| `criteria` | `string[]` | rubric 사용 시 필수 | 측정 가능한 성공 기준. 동사형 문장 권장. 3~5개 권장. |
| `threshold` | `string` | rubric 사용 시 필수 | 통과 판정 기준. `"N/N 기준 충족"` / `"점수 ≥ N"` / `"all PASS"` 형식 중 택일. |
| `scorer_axis` | `"CHECK" \| "PLAN"` | 선택 | 채점 담당 축. 기본값 `"CHECK"`. `"PLAN"`은 특수 케이스에만 사용. |
| `optional` | `true` | 항상 true | 이 필드 자체가 optional임을 명시. 파서 힌트용. |

---

## 전체 이슈 payload 스키마 (v4)

```json
{
  "id": "ISS-NNN",
  "type": "GENERATE_CODE | REFACTOR | FIX_BUG | LINT_CHECK | RUN_TESTS | SCORE | ...",
  "title": "string",
  "priority": "P0 | P1 | P2 | P3",
  "status": "READY | IN_PROGRESS | COMPLETED | FAILED | AWAITING_USER",
  "assign_to": "agent-name",
  "created_at": "ISO 8601",
  "depth": 0,
  "parent": "ISS-NNN | null",
  "payload": {
    "scope_dir": "string — 편집 허용 루트 디렉터리",
    "files": ["string — 대상 파일 목록 (선택)"],
    "blocked_by": "ISS-NNN | null",
    "rubric": {
      "criteria": ["성공 기준 1", "성공 기준 2"],
      "threshold": "2/2 기준 충족",
      "scorer_axis": "CHECK",
      "optional": true
    }
  }
}
```

---

## rubric 작성 가이드

### 좋은 criteria 예시
```
✅ "PDF 파일 업로드 시 텍스트 추출 성공 (3개 샘플 기준)"
✅ "6개 트리거 이벤트 모두에서 webhook-emit.sh 호출 라인 추가"
✅ "15개 누락 에이전트 전원에 Hermes 에스컬레이션 섹션 주입"
✅ "환경변수 미설정 시 무시(silent fail) — 본 파이프라인 영향 없음"
```

### 나쁜 criteria 예시
```
❌ "잘 작동해야 함" — 측정 불가
❌ "사용성이 좋아야 함" — 주관적
❌ "코드가 깨끗해야 함" — 기준 불명확
❌ "모든 기능이 완성돼야 함" — 범위 불명확
```

### threshold 형식

| 상황 | threshold 표기 |
|---|---|
| N개 기준 모두 통과 | `"N/N 기준 충족"` |
| 정량 점수 통과 | `"점수 ≥ 70"` |
| 모든 항목 PASS | `"all PASS"` |
| 역할 커버리지 | `"역할 3개 모두 커버"` |

---

## 채점 흐름 (2축 아키텍처)

```
이슈 COMPLETED (PLAN 축)
  → on_complete.sh
    → check-harness 스폰 (eval 모드)
      → payload.rubric 존재?
        ├─ YES: rubric.criteria 순서대로 검증
        │         → rubric.threshold 충족? PASS / FAIL
        │         → FAIL: rubric_fail:true → FIX 이슈 자동 생성
        └─ NO : 기존 동적 평가 (eval-harness 점수 기준 적용)
```

---

## 호환성 정책 (회귀 없음)

| 조건 | 동작 |
|---|---|
| `payload.rubric` 필드 없음 | 기존 동적 평가 로직 그대로 작동. 변경 없음. |
| `payload.rubric` 있음 | rubric 우선 참조. 동적 평가 보조 참고만. |
| `rubric.scorer_axis == "PLAN"` | check-harness는 결과만 전달, 채점은 plan-harness 담당. |
| rubric 파싱 실패 | 오류 무시 후 동적 평가로 fallback. 파이프라인 중단 없음. |

**핵심 원칙**: rubric은 평가를 **더 엄격하게** 만들 수 있지만, **파이프라인을 더 취약하게** 만들면 안 된다.  
rubric 관련 오류는 항상 graceful fallback (동적 평가) 경로를 유지한다.

---

## Retroactive 적용 이슈 목록 (학습 자료)

아래 이슈들은 ISS-309 작업 시 rubric 필드를 소급 적용한 예시다.  
check-harness가 재채점 시 이 기준을 참조할 수 있다.

| 이슈 ID | 타입 | rubric threshold | 실제 결과 |
|---|---|---|---|
| ISS-301 | REFACTOR | 3/3 기준 충족 | COMPLETED ✓ |
| ISS-302 | GENERATE_CODE | 3/3 기준 충족 | COMPLETED ✓ |
| ISS-303 | GENERATE_CODE | 3/3 기준 충족 | COMPLETED ✓ |
| ISS-304 | DIAGNOSE | 3/3 기준 충족 | COMPLETED ✓ |
| ISS-305 | REFACTOR | 3/3 기준 충족 | COMPLETED ✓ |
| ISS-306 | TEST | 4/4 기준 충족 | COMPLETED ✓ |
| ISS-307 | GENERATE_CODE | 4/4 기준 충족 | COMPLETED ✓ (rubric 최초 적용) |
| ISS-308 | GENERATE_CODE | 4/4 기준 충족 | COMPLETED ✓ |
| ISS-309 | REFACTOR | 4/4 기준 충족 | COMPLETED ✓ (이 이슈) |

---

## 변경 이력

| 버전 | 날짜 | 변경 내용 |
|---|---|---|
| v4.0 | 2026-05-12 | rubric 필드 도입 (ISS-309). check-harness / eval-harness / product-manager 연동. |
| v3.x | 2026-04-16 | 2축 PLAN/CHECK 아키텍처 도입. |
| v2.x | 2026-04-14 | Hermes T1 에스컬레이션 / T2 컨펌 정책 도입. |
| v1.x | 2026-04-01 | 초기 이슈 스키마. |
