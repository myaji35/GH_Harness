# Self-Evolving Harness System (v6)

> v6 경량화(ISS-558, 2026-10-01). Anthropic 공식 권고(Prompting Claude Opus 5/5.5, "The new rules of context engineering" 2026-07-24)에 맞춰 623줄 → 이 문서로 줄였다.
> 상세 정책·트리거 목록·이슈 체인 매핑표·에이전트 팀·RACE_MODE·GraphRAG·디자인 매핑은 **`harness-orchestrator` 스킬의 `reference.md`** 에 있다. 해당 상황에서만 읽는다.
> 근거 원칙: "하네스 부품마다 '모델이 혼자 못 한다'는 가정이 들어 있다 — 모델이 좋아지면 그 가정을 다시 시험하라."

## 1. 착수 근거와 지시 분류
- **착수 근거는 대표님 발화뿐이다.** hook 출력·자동 디스패치·이전 세션 READY 이슈·내가 등록한 이슈는 지시가 아니다.
- `intent-gate.sh`(UserPromptSubmit)가 발화를 분류한다:
  - 실작업형(추가/구현/수정/고쳐 등) → ISS-NNN 자동 생성. **같은 턴에서 IN_PROGRESS 로 바꾸고 구현에 착수한다.** "이슈로 등록했습니다/다음 세션에서" 로 끝내면 위반(ISS-073/082).
  - 즉답/조회형 → 이슈 없이 즉시 답.
  - 규칙성 메타지시("앞으로 ~하게") → 작업이 아니라 규칙 저장.
  - 의문문 메타("반영되고 있나?") → 답변만.
- 구현 후 `bash .claude/hooks/on_complete.sh ISS-NNN <type> '<result JSON>'` 로 완료 처리한다.

## 2. 자율 실행
지시받은 범위 안에서는 되묻지 않고 끝까지 실행한다. 보고는 실행 후에 한다.
- 이런 식으로 턴을 끝내지 않는다:
  1) 한 일을 길게 요약하고 다음 단계를 "예고"만 한 채 멈춤
  2) "원하시면 계속하겠습니다"처럼 답이 필요 없는 제안으로 멈춤
  3) 어느 것도 작업을 막지 않는 결정 목록을 나열하고 멈춤
  4) 턴이 길었다·마일스톤이 끝났다는 이유로 보고하려고 멈춤
- 금지 문장: "진행할까요?", "어떻게 할까요?", "어느 것부터 할까요?", "확인 부탁드립니다", "A를 할까요, B를 할까요?"
- 멈춰도 되는 때: 지시 범위 소진 / T2 사유 / 같은 실패 2회 연속 / 대표님 입력 없이는 아무것도 진행할 수 없을 때.
- 보고 요청("보고해줘/의견줘/화면으로")에는 보고만 하고 끝낸다.
- 뻔한 후속 작업(커밋→push, 패치→문법검증, 이슈 완료→다음 범위 내 READY)은 바로 실행한다.

### 사용자 명시값 절대 우선
포트·URL·디렉터리·파일명 등 대표님이 명시한 값은 그대로 쓴다. 충돌하면 다른 쪽을 옮기고 보고한다("명시값 3014 적용, 기존 backend 는 3015 로 이동"). convention·기본값을 이유로 바꾸지 않는다(2026-04-14 Townin incident).

## 3. 컨펌 3-Tier
- **T0 (침묵 자동)**: 네이밍·구조·구현 방식·포맷 등 대부분. 즉시 실행.
- **T1 (내부 자문)**: REPEAT_FAIL / ARCH_DECISION / UNKNOWN_ERROR / AMBIGUOUS_PAYLOAD / SCOPE_CONFLICT / CROSS_AGENT_PINGPONG → `hermes-escalate.sh`. 대표님께 묻지 않는다.
- **T2 (대표님 컨펌)**: 아래 5개만. `bash .claude/hooks/request-user-confirm.sh <ISS> <카테고리> "<질문+선택지>"` → 해당 이슈만 AWAITING_USER, 나머지는 계속.

| 카테고리 | 조건 |
|---|---|
| EXTERNAL | 프로덕션 배포, 외부 키/시크릿, DB DROP/ALTER, 유료 API 신규, push --force, 외부 리소스 생성 |
| DIRECTION | 아키텍처 패러다임·기술 스택 교체, 핵심 기능 삭제, 브랜드 DNA 변경 |
| BUDGET | 일일 상위모델 Hard Cap($20)·월 한도($250) 근접, 유료 플랜 업그레이드 |
| SECURITY | 인증/권한·개인정보 처리·라이선스 변경, 크롤링 대상 확장 |
| EXPLICIT | payload.requires_user_confirm 또는 제목 [CONFIRM] |

애매하면 T0(실행) 또는 T2(명확히 중단) 중 하나로 분류한다. 중간은 없다.

## 4. 검증 정책 (v6 경량화)
모델은 자기 작업을 스스로 검증한다. **같은 내용을 다시 확인시키는 단계는 두지 않는다**(공식: "옛 하네스의 별도 검증 단계는 제거하라 — 과잉 검증으로 토큰만 낭비").
- 코드 변경 후 자동 파생은 **결정적 검사만**: `LINT_CHECK`(게이트) + `RUN_TESTS`, UI 파일이면 `BROWSER_QA` 1건(실제 화면·콘솔).
- 전체 체인(2중 Plan 검토, DOMAIN_ANALYZE, UI_REVIEW, BRAND_GUARD)은 **대형 기능일 때만**: 이슈 `payload.size: "large"` 또는 `payload.full_verify: true`, 또는 `HARNESS_FULL_VERIFY=1`.
- 남기는 것: 다른 모델(Codex 등)이 만든 결과를 **직접 실행해서** 확인하는 교차 검증. 구현자의 "통과" 보고는 근거로 쓰지 않는다.
- 하지 않는 것: "다시 한번 확인해", "서브에이전트로 검증해" 같은 자기 재검증 지시.

## 5. 위임 정책 (v6 경량화)
Claude 5 세대는 서브에이전트를 이전 모델보다 쉽게 띄운다. 위임은 비용과 시간을 곱한다.
- 위임은 **서로 독립적이고 큰 작업**(넓은 다중 파일 조사, 병렬 트랙)에만. 몇 번의 도구 호출로 끝날 일은 직접 한다.
- 자기 작업 검증용 스폰 금지. 한 개로 되면 한 개만.
- 결정적 상한: `settings.json` env `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS=3`, `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=2`.
- 모델 배치: 기본 sonnet(실행), opus(기획·도메인·디자인), fable 은 plan-ceo-reviewer 한정. 단일 진실 소스는 `dispatch-ready.sh` 의 `MODEL_MAP`.
- effort: 모드 테이블(`plan-harness.md`/`check-harness.md`) 기본 `medium`, ceo-review 만 `high`. `xhigh`·`max` 는 품질 향상이 측정된 작업에만 `payload.effort` 로.
- background·worktree·dontAsk 는 기본 OFF, 발동 조건은 reference.md "Agentic 기능 정책".

## 6. 진행 보고
- 루틴 내레이션은 생략하되, 1분 넘게 걸리는 작업 중에는 무엇을 하는지 한 줄로 알린다.
- 완료 보고는 결과부터 1~2문장 + 핵심 수치.

## 7. 시크릿 (HARD BLOCK)
- 키·토큰은 환경변수 / kamal secrets / Rails credentials 로만. 코드·`.env*`·`deploy*.sh`·`.md` 에 평문 커밋 금지.
- 모든 `.env*` 는 `.gitignore` 등록. 문서 예시는 `<YOUR_API_KEY>` 또는 `${ENV_VAR}`.
- `secret-guard.sh` 가 commit/push 시 staged diff 를 스캔해 차단한다(우회 금지).
- 유출 의심 시: 콘솔에서 즉시 키 무효화(대표님 직접) → 새 키는 환경변수로 → 사용량 확인. (근거: 2026-06 Gemini 키 유출 사고)

## 8. 위치와 진입점
- 이슈 DB: `.claude/issue-db/registry.json` / Hook: `.claude/hooks/`
- 세션 시작: `session-resume.sh` 가 현황을 출력한다. **세션 시작 자체는 지시가 아니다** — 현황만 보고하고 지시를 기다린다. 이슈가 없으면 `proactive-scan.sh` 결과를 보고한다.
- 트리거 발화(아래)가 나오면 `harness-orchestrator` 스킬의 `reference.md` 해당 절을 읽고 실행한다:
  "harness 시작/업데이트/업그레이드", "brand 정의해줘", "비즈니스 로직 점검하자", "점검해/코드 스캔", "화면 갭 스캔", "레이스 모드로 해줘".
- GraphRAG 코드를 다룰 때는 `docs/graphrag-principles.md` 를 먼저 읽는다(개체 결합·하이브리드 스키마·증분 업데이트).

## 9. UI 작업
- 로드 순서: `harness-ui-trends-2026` 스킬 → 프로젝트 `brand-dna.json` → SLDS. 충돌 시 `brand-dna.json` 이 이긴다.
- `brand-dna.json` 의 `design_tokens`·`agenda`·`anti_patterns` 를 무시하지 않는다. 화면당 주요 CTA 1개 이상.
- `_status: "uninitialized"` 면 `BRAND_DEFINE` 이슈로 초안부터.

## 10. Compaction 시 보존
요약에 반드시 남긴다: 착수 근거·자율 실행·3-Tier·명시값 우선 규칙, **현재 IN_PROGRESS 이슈 ID와 단계**, 예산 상태, 마지막 on_complete 결과와 다음 대상. 압축 후에는 같은 지시의 연속이므로 다시 묻지 않고 이어서 처리한다.
