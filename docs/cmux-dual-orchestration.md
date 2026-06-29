# cmux 2분할 듀얼 오케스트레이션 설계

> 결정: 2026-06-29 대표님 구상 — **좌: Claude(지휘) / 우: GLM 5.2(실행)**, registry.json 공유 칠판.
> 진행 범위: 설계 문서만 (코드 변경 없음). 구현은 별도 지시 시.

## 1. 목표

cmux로 터미널을 2분할하여:
- **좌측 패널 = Claude (오케스트레이터)** — 지시 분류, 이슈 생성, dispatch, 결과 분석, 다음 plan 수립
- **우측 패널 = GLM 5.2 (실행자)** — 코딩/리서치 실제 수행

두 패널은 **각자 독립 Claude Code 세션**이지만, **registry.json을 공유 메시지 버스**로 삼아 한 파이프라인처럼 작동한다.

## 2. 왜 registry.json 공유인가 (핵심 설계 결정)

기존 하네스의 단일 진실 소스가 이미 `registry.json`(파일 기반)이다. 두 패널을 잇는 방법으로 MCP/소켓/IPC를 새로 만들 필요가 없다 — **파일 = 메시지 버스**.

| 후보 | 평가 |
|---|---|
| MCP 서버 신설 | ❌ CLI 우선 원칙 위배, 세션 상태 동기화 복잡 |
| 소켓/IPC | ❌ 과설계(Karpathy #2). 두 로컬 프로세스에 불필요 |
| **registry.json 공유** | ✅ 이미 존재. 양 패널이 같은 파일 read/write. 부품 재사용 |

근거: 하네스 2축 아키텍처(PLAN/CHECK)가 이미 "CHECK축 → 외부 LLM 전환"을 명시. 본 설계는 그 물리적 시각화.

## 3. 아키텍처

```
┌─ 좌: Claude (오케스트레이터) ──┐      ┌─ 우: GLM 5.2 (실행자) ─────┐
│ 1. 대표님 지시 수신            │      │ 4. registry READY 이슈 폴링 │
│ 2. intent-gate → 이슈 생성    │ ───▶ │ 5. assign_to=glm-executor   │
│ 3. registry.json write        │      │    이슈를 코딩/리서치 실행   │
│ 8. 결과 분석 → 다음 plan      │ ◀─── │ 6. 산출물 + 결과 JSON write │
│    (on_complete.sh)           │      │ 7. on_complete.sh 호출       │
└──────────────────────────────┘      └────────────────────────────┘
              ↕ 양 패널이 같은 .claude/issue-db/registry.json 을 read/write
```

### 역할 분리
| | 좌 (Claude) | 우 (GLM 5.2) |
|---|---|---|
| 책임 | 지휘·판단·검증 | 실행(코딩/리서치) |
| 하네스 역할 | 오케스트레이터 + CHECK축 | PLAN축 code 모드 (= agent-harness 대체) |
| 모델 | Fable/Opus (메인 루프) | glm-5.2[1m] |
| 쓰는 이슈 | 생성·분석 | 처리·결과기록 |

## 4. 우측 패널 GLM 5.2 구동 방법

Claude Code가 Anthropic 호환 엔드포인트를 지원하므로 **env var 스왑만으로** 우측 패널을 GLM으로 구동:

```bash
# 우측 cmux 패널에서만 export (좌측은 기본 Claude 유지)
export ANTHROPIC_BASE_URL="https://api.z.ai/api/coding/paas/v4"
export ANTHROPIC_API_KEY="<GLM_CODING_PLAN_KEY>"   # 환경변수만, 코드/문서 평문 금지(secret-guard)
export ANTHROPIC_DEFAULT_OPUS_MODEL="glm-5.2[1m]"  # 1M 컨텍스트 변종
claude   # 이 세션은 GLM 5.2로 구동됨
```

- 키는 **환경변수로만** 주입 (CLAUDE.md 시크릿 규칙 — 평문 커밋 시 secret-guard exit 2).
- 좌/우가 **같은 프로젝트 디렉터리**를 열어야 registry.json을 공유한다.

## 5. 연결 메커니즘 — 기존 부품 재사용

새로 만들 게 거의 없다. 부품 매핑:

| 필요 기능 | 기존 부품 | 신규 필요 |
|---|---|---|
| 우측이 처리할 이슈 식별 | `assign_to` 필드 | `glm-executor` 값 추가 |
| 우측 폴링 | `dispatch-ready.sh` READY 정렬 | 우측용 폴링 래퍼(선택) |
| 결과 → 다음 plan | `on_complete.sh` 결과 분석 엔진 | 그대로 |
| 동시 파일수정 충돌 | RACE_MODE worktree 격리 | 좌/우 다른 파일 만지면 불필요 |
| 좌측 지시 분류 | `intent-gate.sh` | 그대로 |

### 신규로 필요한 최소 부품 (구현 시)
1. **`glm-executor` assign_to 값** — MODEL_MAP/axis-router에 매핑 1줄.
2. **우측 폴링 루프** (선택) — `assign_to=glm-executor && status=READY` 이슈를 집어 실행하는 얇은 래퍼. 없으면 대표님이 우측에 수동으로 "다음 이슈 처리해" 지시.
3. **락 처리** — 양 패널이 registry.json 동시 write 시 경합. 단순 파일락(`flock`) 또는 좌측만 write/우측은 result 전용 필드 write로 분리.

## 6. 충돌·리스크

| 리스크 | 완화 |
|---|---|
| registry.json 동시 write 경합 | flock 또는 write 권한 분리(좌=이슈생성, 우=result만). **0012 InsureGraph 손상 사고**가 동시 write 위험의 실증 — 락 필수 |
| 우측 GLM이 좌측 모르게 폭주 | DAILY_ISSUE_CAP(ISS-372 적용됨) + freeze-guard scope 제한 |
| 키 유출 | env var 전용, secret-guard 강제 |
| 좌우 컨텍스트 불일치 | registry.json이 단일 진실 소스 → 항상 파일 기준으로 재동기 |
| 비용 | GLM 5.2는 Opus 대비 ~5x 저렴 → 우측 실행 비용 절감. 좌측만 Fable/Opus |

## 7. 단계적 도입 (구현 시 권장 순서)

1. **수동 모드** — 좌측이 이슈 생성 → 대표님이 우측에 "ISS-NNN 처리해" 수동 지시 → 우측 실행 → 좌측이 결과 확인. (신규 코드 0)
2. **반자동** — 우측에 폴링 래퍼 추가(`assign_to=glm-executor` READY 자동 집기).
3. **자동** — 좌측 on_complete가 `glm-executor`로 이슈 라우팅 + 락 처리.

→ **1단계는 지금 당장 가능**(부품 다 있음). 2~3단계만 신규 코드 소량.

## 8. 결론

- 구상은 우리 2축 아키텍처의 자연스러운 진화 — **권장**.
- 핵심은 registry.json 공유 + 동시 write 락. 새 인프라 거의 불필요.
- 우측 GLM 5.2는 env var 스왑으로 즉시 구동, 비용 ~5x 절감.
- **다음 액션(별도 지시 시)**: 1단계 수동 모드부터 PoC → 락 메커니즘 검증 → 반자동.

---

Sources:
- [GLM-5.2 in Claude Code (MindStudio)](https://www.mindstudio.ai/blog/how-to-use-glm-5-2-in-claude-code)
- [GLM-5.2 Developer Guide (Developers Digest)](https://www.developersdigest.tech/blog/glm-5-2-developer-guide-2026)
- [GLM-5.2 with Claude Code/Cline/Cursor (apidog)](https://apidog.com/blog/glm-5-2-claude-code-cline-cursor/)
