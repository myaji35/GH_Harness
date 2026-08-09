---
name: opus-codes
description: Codex가 코딩하고 Opus(나)가 오케스트레이터로 꼼꼼히 검수하는 위임-검수 워크플로우. 트리거 "Opus 코딩해줘", "옵스 코딩", "코덱스한테 시키고 검수해", "codex로 구현하고 검수". Fable/PM이 등록한 registry 이슈를 Codex에 위임 구현하고, 구현 결과를 Opus가 진단 정확성·회귀·규칙 위반 관점에서 검수한 뒤에만 커밋한다.
---

# opus-codes — Codex 코딩 + Opus 검수 오케스트레이션

> 대표님 확정 (2026-07-18): *"코딩은 Codex가 하고 검수는 너가 꼼꼼하게 진행해줘."*
> 전역 CLAUDE.md의 **LLM 오케스트레이션 원칙**(코딩=Codex, Claude=오케스트레이터)을 실행 절차로 강제하는 스킬.

## 핵심 계약

- **코딩 = `codex exec`** — 실제 파일 편집/생성은 Codex에 위임한다.
- **검수 = Opus(나)** — Codex 산출물을 커밋 전에 반드시 꼼꼼히 검수한다. 검수 없는 커밋은 규칙 위반.
- **오케스트레이션 = Opus(나)** — 요구 분석, 이슈 스펙 정제, 작업 분할, 결과 통합, registry 상태 관리.

## ⭐ 검수가 이 스킬의 존재 이유다 (절대 원칙)

Codex는 지시받은 대로 코딩한다. 그런데 **지시(=이슈 스펙) 자체가 틀렸을 수 있다.**
그래서 위임 전과 후 두 번 검수한다:

### A. 위임 前 검수 — "이슈 진단이 실제 코드와 맞는가?"
이슈를 Codex에 넘기기 전에 **반드시 대상 파일을 직접 열어** 진단의 사실 여부를 확인한다.
- 이슈가 "X가 없다/틀렸다"고 주장하면 → 정말 없는지/틀렸는지 코드로 확인
- 진단이 틀렸으면 → Codex에 넘기지 말고 이슈를 `CLOSED_INVALID` 또는 스펙 정정
- **근거**: 2026-07-18 VINTEE ISS-075 — "폼 input이 border-gray-200/text-xs/uppercase label 위반"이라 등록됐으나, 실제 register 폼은 이미 `border-gray-300 px-3 py-2.5 text-sm`로 규칙 준수. `uppercase tracking-widest`는 label이 아니라 섹션 eyebrow 카피였고, `border-gray-200`은 전부 카드 테두리(정답)였음. 그대로 위임했다면 멀쩡한 코드를 망침(Karpathy #3 위반).

### B. 위임 後 검수 — "Codex 산출물이 옳고 안전한가?"
Codex가 코딩을 마치면 커밋 전에 diff를 검수한다. 체크리스트:
1. **정확성** — 요청한 동작을 실제로 하는가? (테스트/실행으로 확인, 눈으로만 보고 통과 금지)
2. **범위** — 바뀐 모든 줄이 이슈에 직접 추적되는가? 무관한 파일/리팩토링 침범 없는가? (Karpathy #3)
3. **회귀** — 기존 기능을 깨지 않았는가? type-check/lint/관련 테스트 통과?
4. **규칙 위반** — 가독성 규칙, 아이콘 규칙, 시크릿 하드코딩, 프로젝트 컨벤션 위반 없는가?
5. **과잉** — 요청 안 된 기능/추상화 추가 없는가? (Karpathy #2)
- 결함 발견 시 → Codex에 재위임(구체적 수정 지시) 또는 직접 미세 수정(1~2줄 한정).
- 전부 통과해야만 커밋. **"Codex가 했으니 됐다"는 통과 사유가 아니다.**

## 실행 절차

### 1. 대상 이슈 확정
```bash
jq -r '.issues[] | select(.status=="READY") | "\(.priority)\t\(.id)\t\(.type)\t\(.title)"' \
  .claude/issue-db/registry.json | sort
```
- 우선순위 P0>P1>P2>P3. 실패 이슈 > 신규 이슈. 의존성 해소된 것 먼저.
- 대표님이 "Fable이 만든 이슈"처럼 범위를 지정하면 그 범위만.

### 2. 위임 前 검수 (A) + 이슈 IN_PROGRESS 전환
대상 파일을 열어 진단 검증. 통과한 이슈만 IN_PROGRESS로:
```bash
jq --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '(.issues[] | select(.id=="ISS-NNN") | .status) = "IN_PROGRESS"' \
  .claude/issue-db/registry.json > /tmp/reg.tmp && jq empty /tmp/reg.tmp \
  && cat /tmp/reg.tmp > .claude/issue-db/registry.json && rm /tmp/reg.tmp
```
> 주의: `mv`는 이 저장소에서 소유권 오류가 날 수 있음 → `cat >`로 덮어쓴다.

### 3. Codex 위임

두 가지 모드가 있다. **herdr 세션 안이면 B(병렬)를 기본으로 쓴다.**

#### 모드 A — `codex exec` (블로킹, 기본 폴백)
```bash
codex exec --skip-git-repo-check "<정제된 작업 지시>"
```
Codex가 끝날 때까지 Opus는 아무것도 못 한다. herdr이 없을 때만 쓴다.

#### 모드 B — herdr 병렬 위임 (권장) ⭐
Codex를 별도 pane에 상주시키고 **위임과 검수를 동시에 굴린다.**
`herdr` 세션 안에서만 가능(`herdr pane current`가 성공하면 herdr 안이다).

```bash
# 1) pane 확보 + Codex 기동 (최초 1회. 이미 있으면 herdr agent list로 재사용)
MYPANE=$(herdr pane current | python3 -c "import sys,json;print(json.load(sys.stdin)['result']['pane']['pane_id'])")
CXPANE=$(herdr pane split --pane "$MYPANE" --direction right --ratio 0.4 \
  --cwd "$PWD" | python3 -c "import sys,json;print(json.load(sys.stdin)['result']['pane']['pane_id'])")
sleep 3                      # ★ 셸 프롬프트 준비 대기 — 없으면 agent_pane_busy
herdr agent start codex --kind codex --pane "$CXPANE" --timeout 60000

# 2) ★ 화면을 반드시 눈으로 확인 (모달 걸림 여부) — interactive_ready 는 믿지 마라
herdr agent read "$CXPANE" --source visible --lines 15 --format text

# 3) 위임 + 완료 대기 — done/idle/blocked 셋 다 잡는다
herdr agent prompt "$CXPANE" "<정제된 작업 지시>" \
  --wait --until done --until idle --until blocked --timeout 900000

# 4) 결과 회수 (--source visible 을 쓴다)
herdr agent read "$CXPANE" --source visible --lines 60 --format text
```

**함정 6가지 (전부 2026-08-01 실측으로 확인·재현됨):**
1. **`--until done`을 빼면 타임아웃 난다.** ⭐ Codex의 정상 종료 상태는 **`done`**이다.
   `--until idle --until blocked`만 주면 작업이 끝났는데도 못 잡고 대기한다.
   *실측: `idle+blocked`만 → **3분 타임아웃**. `done` 추가 → **3.1초 정상 반환**. 같은 작업이다.*
2. **`agent start`의 `interactive_ready: true`를 믿지 마라.** ⭐ Codex가 모달에 걸려 있어도 `true`가 나오고 `agent_status`도 `idle`로 보인다. 기동 직후 반드시 `agent read --source visible`로 **화면을 눈으로 확인**하고, 모달이면 `agent send-keys`로 해소한 뒤 위임한다.
   *실측: 훅 신뢰 모달 → `agent_prompt_stalled`. 해소 후 재기동하니 이번엔 업데이트 안내 모달. **모달 종류는 매번 다르니 상태값이 아니라 화면으로 판정한다.***
3. **pane 생성 직후 바로 `agent start` 하면 실패한다.** `agent_pane_busy: not an available shell`. 셸 프롬프트가 뜰 시간(`sleep 3`)을 준다.
4. **`--source recent`는 빈 값이 나올 수 있다.** `experimental.pane_history = false`(herdr 기본값)면 그렇다. **`--source visible`을 쓴다.**
5. **`agent prompt`는 턴을 추적하지 않는다.** 이미 `working`인 에이전트에 넣으면 *그 이전 턴*의 완료를 잡는다. 위임 전 `agent list`로 `idle`/`done`인지 확인한다.
6. **`--timeout` 없이 쓰면 무한 대기한다.** 항상 상한을 준다(긴 작업 15분 = 900000).

**훅 신뢰는 필수가 아니다.** Codex 기동 시 "Hooks need review"가 뜨면 3번(*Continue without trusting*)을 골라도 **위임·응답·회수 전부 정상 동작한다**(실측). 신뢰하면 herdr이 Codex 상태를 더 정확히 보고할 뿐이다. 대표님 환경에 대한 영구 설정이므로 **Opus가 대신 신뢰를 누르지 마라.**

**병렬의 실익**: 2)에서 대기하는 대신, 다른 이슈의 *위임 前 검수*(A)를 진행하거나 앞선 이슈의 diff를 검수할 수 있다. 단 **같은 파일을 만지는 작업을 동시에 돌리지 마라** — 충돌한다.

지시문 작성 규칙(두 모드 공통):
- **정확한 파일 경로 + 구체적 변경**을 준다 (모호한 "개선해줘" 금지).
- **건드릴 파일만** 명시하고 그 밖은 손대지 말라고 제약한다.
- 프로젝트 특수 제약을 반드시 포함 (예: VINTEE는 Next.js 16 breaking change — `node_modules/next/dist/docs/` 참조, Tailwind v4, 한글 서비스).
- 시크릿 하드코딩 금지, 기존 스타일 매치를 명시.

### 4. 위임 後 검수 (B)
```bash
cd <project> && git diff --stat && git diff
bun run type-check   # 또는 프로젝트 검증 명령
```
체크리스트 B 5항목 전부 통과 확인. 필요 시 실제 실행/브라우저 저니로 동작 검증.

### 5. 커밋 + on_complete
검수 통과 후에만:
```bash
git add -A && git commit -m "<type>(<scope>): <한국어 요약> (ISS-NNN)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
git push
bash .claude/hooks/on_complete.sh ISS-NNN <TYPE> '<result-json>'
```

## 🔴 예외 없음 — 무조건 Codex다 (2026-07-29 대표님 확정)

> 대표님 원문: *"반드시 무조건 코딩은 Codex로 한다는것은 전역변수로 기록해."*

**종전 예외 3개(미설치·1~2줄 수정·명시 지시)는 폐기됐다.** 줄 수와 무관하다. 1줄이어도 Codex.

- 유일하게 남는 조건: `which codex`가 실패해 **물리적으로 불가능할 때**뿐이며,
  그때는 직접 짜지 말고 **그 사실을 먼저 보고**한다.
- **자기판단 금지어**: "이건 짧으니까" / "루프가 끊기니까" / "왕복이 비효율이라" /
  "버그 수정은 발견-수정-검증이 한 흐름이라" — 전부 위반 사유다. 효율 판단은 내 몫이 아니다.
- **적용 범위**: 신규 구현·버그 수정·리팩토링·설정 파일·마이그레이션·스크립트 전부.
  문서(.md)와 이슈 registry 갱신은 코딩이 아니므로 제외.

> 모드 B(herdr 병렬)는 이 규칙을 지키면서 "왕복이 비효율"이라는 유일한 실질적 불만을 없애기 위한 것이다.
> 위임 중에도 Opus가 검수를 계속하므로, 짧은 수정을 직접 짜야 할 이유가 사라진다.

## 배치 처리
여러 이슈를 받으면:
- 서로 다른 파일을 만지는 이슈는 순차 위임(작은 diff 단위 검수가 쉬움).
- 같은 파일을 만지는 이슈는 묶어서 한 번에 위임(충돌 방지).
- 의존 이슈(예: 브랜드 토큰 → 폰트 → 폼 스타일)는 선행 이슈부터.

**모드 B에서의 파이프라인** — Codex가 ISS-N을 코딩하는 동안 Opus는 놀지 않는다:
```
Codex:  [ISS-1 구현]────────▶[ISS-2 구현]────────▶
Opus:   [ISS-2 위임前검수]   [ISS-1 위임後검수·커밋]
```
`herdr agent prompt --wait`로 대기하는 대신, 그 시간에 **다음 이슈의 위임 前 검수**를 끝내둔다.
Codex pane은 **하나만 유지**한다. 여러 Codex를 동시에 띄우면 같은 저장소에서 충돌하고,
어느 쪽이 무엇을 바꿨는지 diff로 가릴 수 없게 된다(검수 불가 = 이 스킬의 존재 이유 파괴).

## 자율 실행
전역/프로젝트 CLAUDE.md의 자율 실행 원칙 준수. "진행할까요?" 금지.
단, T2(외부배포/보안체계변경/DB마이그레이션/브랜드DNA변경/예산)는 대표님 컨펌.
brand-dna.json 신규 정의는 DIRECTION(T2) — 초안만 만들고 확정은 대표님.
