#!/usr/bin/env bash
# 멀티 에이전트 오케스트레이션 — 모델 라벨 가시화 (전역)
#
# 목적: 규칙 1(모델 라벨 의무 출력)이 "문서에만 있고 화면에는 안 보이는" 상태를 해소.
#       대표님 지적(2026-07-20): "시각적으로 적용되고 있는 모습이 확실하게 안보여서 주문한거야."
#
# 동작: 자연어 실작업 요청이 감지되면 UserPromptSubmit 시점에 라벨 규약을 주입한다.
#       주입된 지시는 응답 첫 줄부터 [모델 · 역할] 라인을 출력하게 만들어 화면에 드러난다.
#
# 근거: ~/.claude/CLAUDE.md "멀티 에이전트 오케스트레이션 — 3대 운영 규칙"
set -uo pipefail

INPUT="$(cat 2>/dev/null || true)"
PROMPT="$(printf '%s' "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('prompt',''))" 2>/dev/null || true)"
SESSION_ID="$(printf '%s' "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id') or 'nosession')" 2>/dev/null || true)"
[ -z "$SESSION_ID" ] && SESSION_ID="nosession"

[ -z "$PROMPT" ] && exit 0

# 즉답/조회형은 제외 — 라벨 강제가 오히려 소음이 되는 구간
if printf '%s' "$PROMPT" | grep -qiE '^(상태|현황|뭐야|무엇|왜|어디|언제|맞나|맞아|보여|확인만|커밋 뭐|어떻게 생각)'; then
  exit 0
fi

# 실작업 신호가 없으면 조용히 통과 (짧은 대화·감탄사 등)
if ! printf '%s' "$PROMPT" | grep -qiE '(해줘|하자|합시다|하시죠|해라|해봐|가자|진행|이어서|계속|만들어|추가|구현|수정|고쳐|바꿔|옮겨|넣어|지우|없애|리팩토링|적용|배포|삭제|점검|분석|검증|실행|정리|개선|반영|보강|연결|등록|마무리|처리|좋겠어|좋겠다|했으면|해보자|주세요|봐$|봐\.|보자|자$)'; then
  exit 0
fi

# 직전 턴에서 라벨이 누락됐으면(orch-enforce-label.sh가 남긴 플래그) 강조 경고 선주입
NEED_LABEL_FLAG="$HOME/.claude/.orch-need-label"
NEED_FULL_LABEL=0
if [ -f "$NEED_LABEL_FLAG" ]; then
  NEED_FULL_LABEL=1
  rm -f "$NEED_LABEL_FLAG" 2>/dev/null || true
  cat <<'RELABEL'

🔴 [직전 턴 위반] 실작업 턴인데 [모델 · 역할] 라벨이 없었다. 이번 턴은 반드시 라벨을 출력하라.
RELABEL
fi

LABEL_MARKER="$HOME/.claude/.orch-label-shown-$SESSION_ID"
if [ ! -f "$LABEL_MARKER" ] || [ "$NEED_FULL_LABEL" -eq 1 ]; then
cat <<'LABEL'

━━━ [오케스트레이션 규약] ━━━
1 라벨: 단계마다 `[모델 · 역할] 무엇을`, 건너뛴 단계는 `[생략]`. 턴 끝에 모델별 요약 표.
2 검증: 구현자 자기보고 인용 금지 — 직접 실행 결과로 판정.
3 위임: /model 전환 요구 금지. 서브에이전트는 독립적이고 큰 작업에만(작은 일·자기검증용 스폰 금지). 이슈 도출 Fable 위임은 대형 기능 요청일 때만.
4 착수 근거는 대표님 발화뿐. 지시 범위 안은 되묻지 말고 끝까지, 보고 요청엔 보고만.
5 규약이 현실과 안 맞으면 보고하고 보강안 제시.
━━━━━━━━━━━━━━━━━━━━━━
LABEL
  if [ ! -f "$LABEL_MARKER" ]; then
    find "$HOME/.claude" -maxdepth 1 -name '.orch-label-shown-*' -mtime +6 -delete 2>/dev/null || true
    touch "$LABEL_MARKER" 2>/dev/null || true
  fi
else
  printf '%s\n' '━━━ [오케스트레이션 규약 적용 중] 라벨 · 직접검증 · 위임 최소 · 지시범위 내 연속처리 ━━━'
fi

exit 0
