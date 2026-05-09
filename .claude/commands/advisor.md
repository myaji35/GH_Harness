---
description: Hermes 경유로 Advisor(opus) 심층 자문 요청 — 막힘/아키텍처/트레이드오프 판단
---

# /advisor — 상위 모델 자문 요청

현재 작업 맥락에서 **Opus 수준 심층 판단**이 필요할 때 호출합니다.
Hermes(sonnet, 중개자)가 상황을 요약한 뒤 Advisor(opus)에게 전달하여 자문 결과를 회신합니다.

## 사용 시점
- sonnet 에이전트가 반복 실패 중일 때
- 아키텍처/스택 선택 트레이드오프가 애매할 때
- 디자인 감각 판단이 룰 매칭으로는 부족할 때 (design-critic 한계)
- 도메인 규칙 추출이 sonnet으로 커버리지 부족할 때

## 자동 실행 절차

사용자가 `/advisor <질문 또는 이슈ID>`를 입력하면:

1. **맥락 정리** — 현재 대화/코드 변경/등록된 이슈를 요약하여 `context_hint` 작성
2. **Hermes 에스컬레이션 호출**:
   ```bash
   bash .claude/hooks/hermes-escalate.sh \
     "${ISSUE_ID:-MANUAL}" \
     "ARCH_DECISION" \
     "$CONTEXT_HINT"
   ```
   - 인자가 이슈 ID면 해당 이슈를 executor로 사용
   - 없으면 수동 자문 이슈(MANUAL) 생성
3. **HERMES_CONSULT READY 이슈 확인** → dispatch-ready.sh가 hermes 에이전트 스폰
4. **Hermes → Advisor 체인 완료 후** registry.json의 result 필드를 읽어 사용자에게 답변 회신

## reason_code 자동 매핑
| 사용자 질문 패턴 | reason_code |
|---|---|
| "계속 실패해" / "반복 실패" | REPEAT_FAIL |
| "아키텍처" / "스택 선택" / "트레이드오프" | ARCH_DECISION |
| "이 에러 원인 모르겠어" | UNKNOWN_ERROR |
| "이슈 범위가 애매해" | AMBIGUOUS_PAYLOAD |
| "에이전트끼리 충돌" | SCOPE_CONFLICT |
| "핑퐁 중" | CROSS_AGENT_PINGPONG |
| 그 외 | ARCH_DECISION (기본) |

## Circuit Breaker
- 이슈당 최대 3회 / 일일 최대 20회 / 일일 비용 $5 cap
- 초과 시 meta-agent로 SYSTEMIC_ISSUE 인계

## 예산 영향
- Advisor 호출당 예상 비용: $0.27
- Opus 일일 Hard Cap ($20) 근접 시 자동 강등 또는 T2 BUDGET 트리거

## 실행 예시
```
/advisor 이 React 컴포넌트를 여러 페이지에서 재사용하는데 props drilling이 심해. context API vs zustand 중 어떤 걸 써야 할까?
```
→ reason_code=ARCH_DECISION으로 HERMES_CONSULT 생성 → hermes → advisor → 회신
