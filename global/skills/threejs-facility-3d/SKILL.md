---
name: threejs-facility-3d
description: Use when building or tuning a Three.js 3D view of an industrial facility (smart farm, warehouse, factory) — real-measured dimensions, responsive camera distance across screen sizes, overhead OHT rails, AGV/AMR clearance, and a debug camera hook for Playwright screenshot verification.
---

# Three.js Facility 3D (실측 산업 시설)

## Overview

산업 시설(스마트팜/창고/공장)을 Three.js로 실측 치수 기반 3D화할 때의 검증된 레시피. 스마트팜 DT에서 카메라 튜닝을 수십 회 반복하며 정착시킨 패턴을 체크리스트화한 것 — 같은 튜닝을 재발명하지 마라.

**핵심 원칙**: 치수는 실측 상수로 한 곳에 모으고(`ASSETS.dimensions`), 카메라는 화면 크기에 반응형으로, 검증은 URL 파라미터 디버그 훅으로.

## When to Use

- Three.js로 시설/설비/AGV를 3D 렌더링할 때
- 화면 크기별로 뷰가 너무 크거나 작게 보이는 문제를 풀 때
- 천정 OHT 레일 + 지상 AGV의 수직 분리(간섭 회피)를 표현할 때
- Playwright로 3D 뷰를 스크린샷 검증할 때

**When NOT**: 2D 대시보드, 게임 엔진 필요 수준의 물리, 단순 모델 뷰어(orbit controls 라이브러리로 충분).

## 반응형 카메라 거리 (재발명 금지)

화면이 크면 가깝게(크게 보임), 작으면 멀리(전체 보임). 기준 폭에서 base rad, 폭 비율의 **완만한 승(0.55)**으로 과확대 방지, 클램프 필수.

```js
function fitRad(){
  const w = (ctr && ctr.clientWidth) ? ctr.clientWidth : (window.innerWidth||1280);
  const REF=1280, BASE=88;
  const scale = Math.pow(REF / Math.max(640, w), 0.55);  // 완만하게 → 과확대 방지
  return Math.round(Math.min(120, Math.max(58, BASE*scale)));  // 클램프 [58,120]
}
```

구면좌표 카메라: `rad`(거리) + `th`(방위) + `ph`(고도). 타깃은 시설 중심으로 상향(`tgt.y`↑)해야 상단 공백이 안 생긴다.

```js
cam.position.set(
  tgt.x + rad*Math.sin(ph)*Math.sin(th),
  tgt.y + rad*Math.cos(ph),
  tgt.z + rad*Math.sin(ph)*Math.cos(th));
cam.lookAt(tgt);
```

## 치수는 상수 한 곳에

실측값을 `ASSETS.dimensions`(외부 JSON)로 모으고 코드는 참조만. 스마트팜 예: 셀 4단 중심 `TY=[0.5,2.0,3.5,5.0]`(1단 1500mm), Z축 50m = 주통로3 + 셀구간44 + 주통로3.

**AGV/AMR 간섭 회피(수직 분리)**: 캐리어 폭과 통로/다리밑 간격을 실측으로 검증 — AGV가 캐리어 밑을 통과하는 구조면 다리밑 높이 > AGV 높이를 상수로 보장. (예: 통로 1.75m에 폭 1.6m 여유 운행, 다리 안쪽 1.15m에서 1m 셀 픽업)

## 천정 OHT (반도체 팹 방식)

컨베이어를 지상이 아닌 공중 레일로 올려 바닥 통로를 비운다. 레일 주행 + 승강 호이스트 + 그리퍼. 셀 높이·하우스 높이·천정 클리어런스를 상수로 잡아 AGV와 수직 분리.

## Playwright 검증용 디버그 카메라 훅

URL 파라미터로 스핀을 멈추고 카메라를 고정 → 스크린샷 재현성 확보.

```js
if(new URLSearchParams(location.search).get('dbg')==='1'){
  spin=false;   // 자동 회전 정지 → 결정론적 스크린샷
  // window.__cam = {setView, rad, th, ph} 등 노출 → page.evaluate로 각도 고정
}
```

`?dbg=1`로 열고 `page.evaluate`로 뷰 세팅 후 `waitFor(networkidle)` → screenshot.

## Common Mistakes

| 실수 | 결과 | 해결 |
|---|---|---|
| 카메라 거리 고정 | 큰 화면 과확대/작은 화면 잘림 | fitRad() 반응형 |
| 폭 비율 선형 승 | 극단 화면서 과확대 | 0.55승 + 클램프 |
| 치수를 코드 곳곳에 하드코딩 | 정본화 실패, 반복 수정 | ASSETS.dimensions 한 곳 |
| 자동 회전 켠 채 스크린샷 | 비결정론 검증 | ?dbg=1로 spin 정지 |
| AGV·OHT 같은 높이 | 간섭 | 수직 분리 상수 보장 |
