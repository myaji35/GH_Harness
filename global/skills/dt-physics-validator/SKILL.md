---
name: dt-physics-validator
description: Use when adding physics/safety validation or autonomous decision logic to a browser-based digital twin (Three.js/Rapier), AGV/AMR fleet sim, or single-HTML monitoring app — especially when the engine must not modify existing rendering code and must be verified with Playwright.
---

# Digital Twin Physics Validator (비침습 검증엔진)

## Overview

디지털 트윈에 **물리·안전·자율 의사결정** 검증을 추가할 때, 기존 렌더링/시뮬 코드를 **0줄 수정**하고 별도 IIFE로 `window.__phys*`를 읽기 전용 노출하는 패턴. 스마트팜 DT(smartfarm_dt_monitor_v04.html)에서 10축을 이 패턴으로 구축·검증했다.

**핵심 원칙**: 검증엔진은 관찰자다. 기존 상태(`window.COLL`, 캐리어 배열)를 **읽기만** 하고, 결과는 새 전역에 노출한다. 침습하면 회귀 위험 + 검증 불가.

## When to Use

- 브라우저 디지털 트윈에 물리 검증(동역학/열역학/센서잔차)을 추가할 때
- AGV/AMR fleet에 자율 의사결정(충전 배차/교착 해소/지오펜스)을 넣을 때
- 기존 3D 앱을 건드리지 않고 검증 레이어만 얹어야 할 때
- Playwright로 검증 결과를 자동 확인해야 할 때

**When NOT**: 서버사이드 물리 엔진, 실시간 제어 루프(여기 패턴은 관찰·권고 전용), 신규 앱 처음부터 설계 시(그땐 엔진 분리를 처음부터).

## 2-Layer 아키텍처

| 레이어 | 전역 | 역할 | 축 |
|---|---|---|---|
| 탐지·예측 | `window.__physValidator` | 위반 감지, 추세 외삽 | 동역학/환경물리/센서잔차/인과/학습/예측정비 (1~6) |
| 자율 의사결정 | `window.__physAI` | 배차·양보·감속 권고 | SOC충전/교착/지오펜스/핸드오프 (7~10) |

두 레이어는 별도 IIFE. `__physAI`는 `__physValidator`를 **읽기만** 한다(`Object.assign`으로 통합 노출 가능).

## 절대 규칙 (이 프로젝트에서 실제로 데인 함정)

### 1. no-cache 서버로 검증하라 (거짓 통과 방지)
`python -m http.server`는 Cache-Control 헤더가 없어 **Playwright가 옛 코드를 캐시**한다. 코드를 고쳤는데 검증이 통과하면 옛 코드를 본 것일 수 있다.

```bash
# ❌ 거짓 통과 위험
python3 -m http.server 8000

# ✅ no-cache 헤더 서버
npx http-server -c-1 -p 8000    # -c-1 = no cache
# 또는 검증 전 하드 리로드: page.reload({ waitUntil:'networkidle' }) + 캐시 무효화 쿼리(?v=timestamp)
```

### 2. 상태 배열명과 노출 함수명을 분리하라
내부 상태 배열을 `issues`로 두고 노출 함수도 `issues()`로 만들면 충돌한다. **내부는 `_issues`, 노출은 `issues()`**로 복사 반환.

```js
const PA = { _issues:[] };                    // 내부 상태(언더스코어)
PA.issues = () => PA._issues.map(x=>({...x})); // 노출: 방어적 복사(원본 오염 방지)
```

### 3. 기존 엔진 0줄 수정
새 축을 추가할 때 기존 IIFE를 건드리지 마라. 새 IIFE + `Object.assign(window.__physValidator, {신규})` 로 확장.

### 4. 검증 훅은 읽기 전용
`__phys*._test`에 `reset()`/주입 함수를 두되, 프로덕션 로직을 바꾸지 않는 순수 테스트 훅으로 격리.

```js
PA._test = {
  reset(){ PA._kin={}; PA._issues=[]; },       // 테스트 격리용
  // 상태를 읽거나 초기화만. 프로덕션 판정 로직 호출 금지.
};
```

## 신규 축 추가 레시피

1. 새 IIFE 작성 (`(function(){ ... window.__physAI.newAxis = ...; })()`)
2. 기존 상태를 **읽기만** (예: 캐리어 배열, `window.COLL`)
3. 위반/권고를 내부 배열에 push, 노출 함수는 방어적 복사 반환
4. 자동조치 불가 = 이슈 등록(운영자 에스컬레이션), 크리티컬만 음성 보고
5. 오탐 방지 임계 설정 (예: 예측 축은 최소기울기 + 최소 R² 게이트)
6. **위반 시나리오 + 정상 시나리오 둘 다** Playwright 검증 (정상에서 오탐 0 확인)

## 오탐 방지 (검증된 게이트)

- 학습형(ANOMALY): Welford 온라인 평균/분산, 워밍업 40표본, 위반 중 값은 학습 제외(베이스라인 오염 방지)
- 예측(PREDICT): 최소기울기 + 최소 R²(0.6)로 노이즈 차단, violations 아닌 forecasts()로 분리
- 안전(GEOFENCE): 존 사각형 내부에서만 속도상한 적용 → 구역 밖 동일 속도는 오탐 0

## Playwright 검증 4축 (완료 기준)

각 신규 축마다:
1. **위반 주입** → 해당 타입 탐지 확인 (예: SOC 12% → SOC_CRITICAL + 충전 큐 정렬)
2. **정상 시나리오** → 오탐 0 확인 (예: 구역 밖 8m/s → GEOFENCE 미발동)
3. **라이브 패널** → 실제 UI에 반영되는지 스크린샷
4. **엔진 에러 0건** (콘솔) — MQTT 미기동 등 예상 경고만 허용

`__phys*.snapshot()` / `.issues()`를 `page.evaluate()`로 읽어 단정.

## Common Mistakes

| 실수 | 결과 | 해결 |
|---|---|---|
| `http.server`로 검증 | 옛 코드 거짓 통과 | no-cache 서버 |
| `issues` 배열 = `issues()` 함수 | 이름 충돌 | `_issues` / `issues()` 분리 |
| 기존 엔진에 축 추가 | 회귀 위험 | 새 IIFE + Object.assign |
| 위반만 테스트 | 오탐 방치 | 정상 시나리오도 필수 |
| 무중력 충돌 질의에 dynamics 사용 | 불필요 복잡 | `gravity:0` + intersection 질의만 |
