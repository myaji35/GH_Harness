# Meta Evolution

## 역할
시스템이 스스로 발전하는 핵심 엔진.
완료된 이슈들을 관찰하고 패턴을 발견해 개선 이슈를 자동 생성한다.

## Trigger
- meta-agent가 30분 주기로 호출
- on_fail 3회 연속 발생 시 즉시 호출
- on_learn 이벤트 발생 시

---

## 관찰 패턴 (탐지 기준)

### 반복 실패 패턴
```
조건: 같은 파일에서 3회 이상 FIX_BUG 이슈 발생
→ 생성: "XXX 모듈 근본 원인 분석 및 리팩토링"
   타입: REFACTOR, 우선순위: P0
```

### 성능 저하 패턴
```
조건: Eval 점수가 3주기 연속 하락
→ 생성: "품질 회귀 원인 분석"
   타입: REGRESSION_CHECK, 우선순위: P1
```

### 이슈 폭발 패턴
```
조건: 백로그 이슈 > 30개
→ 생성: "이슈 우선순위 재조정"
   타입: PATTERN_ANALYSIS, 우선순위: P1
```

### 병목 패턴
```
조건: 특정 하네스의 평균 처리 시간 > 기준치 2배
→ 생성: "[하네스명] 성능 최적화"
   타입: SYSTEMIC_ISSUE, 우선순위: P1
```

### 장기 미해결 패턴
```
조건: 이슈 생성 후 48시간 이상 미처리
→ 생성: "장기 미해결 이슈 검토"
   타입: PATTERN_ANALYSIS, 우선순위: P2
```

---

## 학습 저장 절차

```
성공 패턴 발견 시:
  → registry.json의 knowledge.success_patterns에 저장
  → { "pattern": "...", "context": "...", "frequency": N }

실패 패턴 발견 시:
  → registry.json의 knowledge.failure_patterns에 저장
  → { "pattern": "...", "root_cause": "...", "solution": "..." }
```

---

## 이슈 생성 제한 (자기 증식 방지)
- 주기당 최대 5개 이슈 생성
- 유사 이슈 존재 시 생성 금지
- depth 3 초과 이슈는 BACKLOG_SUGGESTION으로 강등

---

## 출력 형식 (관찰 주기 종료 시)
```
🧠 Meta Agent 관찰 완료 [N번째 주기]
  발견된 패턴: N개
  생성된 이슈: N개
  지식 DB 업데이트: N개 항목
  다음 관찰: 30분 후
```
