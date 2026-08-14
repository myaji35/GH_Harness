---
name: dt-motion-statemachine
description: Use when coordinating a carrier↔AGV (or robot↔shuttle) handoff in a digital twin so the receiving vehicle is pre-positioned BEFORE the pick/place, not summoned after — adding pre-staging states, predictive dispatch, and role-based waiting to an existing state machine without rewriting it.
---

# DT Motion State Machine — 선점 대기 & 예측 스테이징

## Overview

디지털 트윈에서 캐리어↔AGV 인계를 "사후 랑데부"(캐리어가 작업 후 AGV 호출)가 아니라 **"선점 대기"**(빈 AGV가 픽업지점에 먼저 도착 후 캐리어 작업)로 바꾸는 패턴. 스마트팜 DT에서 기존 상태머신을 최소 침습으로 개조해 구현했다.

**핵심 원칙**: 동선 최소화의 본질은 "만나는 것"이 아니라 **"받을 쪽이 먼저 가 있는 것"**. 이를 위해 상태 순서를 뒤집고, 다음 목적지를 예측해 선행 배차한다.

## When to Use

- 캐리어/로봇이 물건을 꺼내는 순간 받을 AGV가 아래 대기해야 할 때
- 넣을 자재를 실은 AGV가 목적지에 먼저 스테이징돼야 할 때
- 기존 상태머신을 재작성하지 않고 선점/예측을 얹어야 할 때

**When NOT**: 인계가 없는 단독 이동, 실시간 안전제어(여긴 시뮬/권고 레벨).

## 3가지 개조 (사후 랑데부 → 선점)

### 1. 인출 순서 역전 — 새 "선점 대기" 상태 삽입
기존: `픽업(꺼냄) → AMR 호출 → 대기`. AMR이 뒤늦게 옴.
개조: 목적지 도착 → **AMR 먼저 호출 + 새 state(선점대기)** → AMR 도착 확인 후 픽업.

```js
// 목적지 도착 분기 (state 0 끝)
}else if(c.carrying){
  c.state = 2;                      // 이미 보유 → 인계
}else{
  // 픽업 전에 빈 AMR 먼저 호출 → 선점대기 상태로
  if(!existsReq(c) && !assigned(c)) workQueue.push({kind:'pickup-out', carrier:c, ...});
  c.state = 8;                      // 새 상태: AMR 선점 도착 대기
}
// 새 state 8: AMR 도착 확인 후 픽업(1)로
else if(c.state===8){
  const amrReady = pairAmr && dist(pairAmr,c) < .6;
  if(amrReady || c.stateTimer>10) { c.state=1; }   // 안전망 타임아웃 필수
}
```

**함정**: 선점 대기 상태는 **데드락 위험**(AMR이 안 오면 영영 대기). 반드시 타임아웃 안전망(예: 10s 후 그래도 진행). 라이브 검증에서 state가 8→2로 넘어가는지 확인(안 넘어가면 데드락).

### 2. 예측 스테이징 — 다음 타겟 정해질 때 선행 배차
기존: 캐리어의 다음 타겟은 계산되나 AGV에 전달 안 됨.
개조: 타겟 선정 함수(`pickNewTarget`) **끝에서** OUT-AMR을 선행 배차 → 캐리어와 동시 출발.

```js
function pickNewTarget(c){
  ... c.targetCell = best; ...
  // 다음 타겟 확정 즉시 선행 배차 (predictive) → 캐리어와 함께 이동
  if(best>=0 && !existsReq(c) && !assigned(c))
    workQueue.push({kind:'pickup-out', carrier:c, priority:5, predictive:true});
}
```
중복 방지(existsReq/assigned 체크)로 선점(1)과 예측(2)이 이중 큐잉되지 않게.

### 3. 역할 기반 근접 정렬
AGV 정지 위치를 작업 대상(어느 랙/열)에 따라 미세 오프셋 → 인계거리 최소화.
```js
const rk = cellRack(c.targetCell);           // 0~3 랙 인덱스
const nearSide = (rk===0||rk===2) ? -1 : +1; // 좌/우
const finalX = c.x + nearSide * 0.05;        // 물리 여유 안에서만(통로폭 제약)
```
**물리 제약 확인 필수**: 통로폭−장비폭 = 실여유. 좁으면(예 7.5cm) 큰 오프셋 불가 → 장비 본체 이동이 아니라 갠트리/포크로 도달하는 게 정답(straddle 설계).

## 라이브 검증 (필수)

Playwright로 상태 전이를 실관측 — 시간 경과 후 캐리어 state가 순환하는지:
```js
await new Promise(r=>setTimeout(r,10000));
carriers.map(c=>({id:c.id, state:c.state, cycles:c.cycles}));
// 기대: 8(선점대기)→2(인계)→... 순환. 8에 고착되면 데드락.
```
+ 엔진 에러 0 + P0 충돌 무회귀([[dt-physics-validator]] `__collAudit` 재확인).

## Common Mistakes

| 실수 | 결과 | 해결 |
|---|---|---|
| 선점 상태에 타임아웃 없음 | AMR 안 오면 데드락 | 10s 안전망 |
| 선점+예측 이중 큐잉 | 중복 배차 | existsReq/assigned 체크 |
| 물리 여유 무시하고 근접 | 벽 충돌 | 통로폭−장비폭 확인, 갠트리로 도달 |
| 라이브 검증 생략 | 데드락 미발견 | state 8→2 전이 실관측 |
