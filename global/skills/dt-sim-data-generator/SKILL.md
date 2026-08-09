---
name: dt-sim-data-generator
description: Use when you need physics-based virtual sensor data or fault scenarios for a digital twin before real hardware exists — MQTT sensor simulation, anomaly injection (drift/spike/stuck/noise/offset), or an in-memory broker for E2E testing without Docker/mosquitto.
---

# Digital Twin Sim Data Generator (물리 기반 가상 센서)

## Overview

실물 하드웨어(센서/AGV) 구축 전에 **물리 모델 기반 가상 데이터**를 MQTT로 흘려 트윈을 개발·검증하는 패턴. 스마트팜 DT에서 5개 동의 온·습도·EC·pH를 물리 모델로 생성하고, 이상 시나리오를 시계열 주입했다.

**핵심 원칙**: 시뮬레이터는 **실물과 동일한 인터페이스**(같은 MQTT 토픽 스키마)를 쓴다. 실물이 들어오면 시뮬레이터만 빼면 무손상 교체된다.

## When to Use

- 실물 센서/AGV 없이 트윈을 개발·데모해야 할 때
- 물리 검증엔진([[dt-physics-validator]])에 넣을 이상 시나리오가 필요할 때
- Docker/mosquitto 없이 E2E 테스트 환경을 띄워야 할 때

**When NOT**: 실물 데이터가 이미 있을 때(그땐 시뮬 불필요), 순수 랜덤 jitter로 충분할 때(물리 모델 오버킬).

## 3-Part 구조

```
mqtt-broker/dev-broker.mjs   # 인메모리 MQTT (1883 + WS 9001), Docker 불필요
sim-data/physical-sim.mjs    # 물리 모델 센서 → MQTT publish
sim-data/scenarios.json      # 이상 시나리오 카탈로그 (검증 기대값 포함)
sim-data/run-e2e.sh          # 브로커 + 시뮬 원샷 기동
```

## 물리 모델 3원칙 (단순 jitter와의 차이)

1. **평형값으로 1차 지연 수렴** — 난방/냉방 응답을 τ(시상수)로 모델링:
   `st.temp += (tTarget - st.temp) * (dt / tau) + noise`
2. **일주기(diurnal)** — 낮밤 사인파 오프셋을 평형값에 더함 (테스트는 SPEED 배수로 가속)
3. **작물별 파라미터** — 동마다 `{tEq, hEq, ecEq, tau}` 다르게 (엽채류 19°C / 병풀 24°C 등)

## 이상 시나리오 카탈로그 (검증 기대값 결합)

`scenarios.json`의 각 시나리오는 **어떤 위반을 유발해야 하는지 `expect` 필드로 명시** — 시뮬과 검증엔진이 계약으로 묶인다.

| kind | 물리 의미 | 유발 위반(expect) |
|---|---|---|
| `drift` | 서서히 이탈 (magnitude × 진행도) | RESIDUAL |
| `spike` | 삼각 급변(물리 불가 속도) | THERMO |
| `stuck` | 값 고정 = 센서 고장 | STUCK_SENSOR |
| `noise` | 노이즈 폭증 | ANOMALY |
| `offset` | 상시 편차 | RESIDUAL |

스키마: `{id, name, span(null=전체), metric, kind, magnitude, duration_sec, start_after_sec, expect}`

## 시간 가속 (테스트 필수)

`SPEED` 환경변수로 시간을 배수 가속 → 120초 시나리오를 수 초에 검증. `elapsed()`에만 곱하고 물리 τ는 그대로 두면 실시간과 동일 거동을 압축 재생.

```bash
SPEED=30 INTERVAL_MS=200 node sim-data/physical-sim.mjs   # 30배속
```

## E2E 원샷 기동

```bash
bash sim-data/run-e2e.sh    # 브로커(1883+9001) + 물리 시뮬 동시 기동
# 그다음 http.server로 HTML 열면 live 수신 + 검증 작동
```

`run-e2e.sh`는 기존 프로세스를 `pkill`로 정리하고 trap으로 Ctrl+C 시 자식 정리.

## Common Mistakes

| 실수 | 결과 | 해결 |
|---|---|---|
| 토픽 스키마를 실물과 다르게 | 실물 교체 시 파서 재작성 | `dt/<site>/span/<id>/sensor` 동일 유지 |
| SPEED를 물리 τ에도 곱함 | 거동 왜곡 | elapsed()에만 곱함 |
| 시나리오에 expect 없음 | 검증과 계약 단절 | 모든 시나리오에 유발 위반 명시 |
| stuck을 값 0으로 | 고착≠0 | 마지막 값 유지(out 그대로) |
