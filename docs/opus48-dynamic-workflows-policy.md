# Dynamic Workflows 사용 정책 (Opus 4.8)

> 결정: 2026-05-30 대표님 승인 — **대형 작업 한정**. ISS-340.
> 근거 기능: Opus 4.8 Dynamic Workflows (Claude Code `Workflow` 네이티브 도구, 한 세션 내 수백 서브에이전트 병렬 오케스트레이션).

## 1. 원칙

Harness의 일상 이슈 처리는 **기존 `Agent` 스폰 방식을 유지**한다.
`Workflow` 도구는 **명시적 대형 작업에서만** 사용한다. 무분별한 수백 서브에이전트 발사는 금지.

## 2. Workflow 허용 조건 (모두 충족)

1. **작업 성격이 대형**일 것 — 아래 중 하나:
   - 코드베이스 전체 마이그레이션 (수십~수백 파일)
   - 전체 감사 (보안/품질/디자인 코드베이스 스윕)
   - 대량 리팩토링 (패턴 일괄 변경)
   - 광범위 리서치 (멀티소스 fan-out + 교차검증)
2. **사전 토큰 규모 보고** — 실행 전 예상 서브에이전트 수 + 토큰 규모를 대표님께 1줄 보고.
3. **T2 BUDGET 게이트 통과** — 일일 Opus Hard Cap($20) 정책 유지. 근접/초과 시 `request-user-confirm.sh BUDGET` 발동.

## 3. Workflow 금지 영역

- 단일 이슈 처리 (FIX_BUG, STYLE_FIX 등) → 기존 Agent 스폰
- 일상 PDCA 사이클 (GENERATE_CODE → LINT → TEST → SCORE)
- 예산 Hard Cap 근접 상태

## 4. race-mode 와의 관계

기존 `race-dispatch.sh`(provider 경쟁, git worktree 격리)와 `Workflow`(단일 provider 병렬 fan-out)는 **목적이 다르다**:
- **race-mode** — 같은 작업을 여러 LLM(claude/codex/gemini)이 경쟁 → 승자 선정
- **Workflow** — 한 LLM이 작업을 분해해 병렬 서브에이전트로 동시 처리 → 종합

→ 둘은 대체 관계가 아니다. race-mode를 Workflow로 흡수하지 않는다.
→ 향후 PoC: 대형 마이그레이션 1건을 Workflow로 시범 실행해 토큰/완성도 측정 (대표님 대형작업 지시 시점에 한해).

## 5. 실행 시 보고 템플릿

```
[Workflow 사용 사전 보고]
- 작업: <대형 작업 설명>
- 예상 서브에이전트: ~N개
- 예상 토큰 규모: ~Xk output
- 현재 일일 Opus 비용: $Y / Hard Cap $20
→ GO/STOP 판단 요청
```
