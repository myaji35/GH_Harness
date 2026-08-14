#!/usr/bin/env bash
# 오케스트레이션 규칙 사후 강제 #2 — 라벨/요약표 미출력 검사 (전역 Stop)
#
# 목적: 규칙1(모델 라벨 의무)을 사후 검사. 실작업 턴인데 [모델·역할] 라벨이
#       한 번도 안 나왔으면 다음 턴 시작 시 경고를 주입한다.
#       대표님 지적: "시각적으로 적용되는 모습이 안 보인다" → 라벨 누락을 스스로 잡게.
#
# 동작: transcript에서 직전 assistant 응답을 읽어
#       ① 도구를 여러 개 쓴 실작업 턴인가(간단 대화는 제외)
#       ② [모델 · 역할] 또는 [생략] 라벨이 있는가
#       라벨이 없으면 .orch-need-label 플래그 파일을 남긴다.
#       (Stop hook의 stdout은 사용자에게 안 보이므로, 플래그를 남겨
#        orchestration-label.sh가 다음 프롬프트에서 강조 주입하도록 연계.)
#
# 근거: ~/.claude/CLAUDE.md 규칙1 + orchestration-label.sh
set -uo pipefail

INPUT="$(cat 2>/dev/null || true)"

TRANSCRIPT="$(printf '%s' "$INPUT" | python3 -c "import sys,json;print(json.load(sys.stdin).get('transcript_path',''))" 2>/dev/null || true)"
[ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ] && exit 0

# 직전 assistant 텍스트 + 도구 사용 수 추출
RESULT="$(python3 - "$TRANSCRIPT" <<'PY' 2>/dev/null || true
import sys,json
path=sys.argv[1]
lines=open(path,encoding='utf-8').read().splitlines()
# 마지막 assistant 메시지 블록의 텍스트와 tool_use 카운트
last_text=[]; tool_uses=0
# 뒤에서부터 최근 assistant turn 하나를 모은다
recent=[]
for ln in reversed(lines):
    try: obj=json.loads(ln)
    except: continue
    recent.append(obj)
    if len(recent)>40: break
recent.reverse()
seen_user=False
for obj in reversed(recent):
    role=obj.get('message',{}).get('role') or obj.get('role')
    if role=='user':
        break
for obj in recent:
    msg=obj.get('message',{})
    if (msg.get('role') or obj.get('role'))!='assistant': continue
    content=msg.get('content',[])
    if isinstance(content,str): last_text.append(content)
    elif isinstance(content,list):
        for c in content:
            if c.get('type')=='text': last_text.append(c.get('text',''))
            if c.get('type')=='tool_use': tool_uses+=1
txt='\n'.join(last_text)
has_label = ('· ' in txt and '[' in txt) and any(m in txt for m in ['Opus','Codex','Fable','Sonnet','Haiku','생략'])
print(json.dumps({'tools':tool_uses,'has_label':has_label,'len':len(txt)}))
PY
)"

[ -z "$RESULT" ] && exit 0

TOOLS="$(printf '%s' "$RESULT" | python3 -c "import sys,json;print(json.load(sys.stdin).get('tools',0))" 2>/dev/null || echo 0)"
HAS_LABEL="$(printf '%s' "$RESULT" | python3 -c "import sys,json;print('1' if json.load(sys.stdin).get('has_label') else '0')" 2>/dev/null || echo 1)"

FLAG="$HOME/.claude/.orch-need-label"
rm -f "$FLAG" 2>/dev/null || true

# 실작업 턴 판정: 도구를 3개 이상 쓴 턴(간단 조회는 보통 0~2개)
if [ "${TOOLS:-0}" -ge 3 ] && [ "${HAS_LABEL:-1}" = "0" ]; then
  touch "$FLAG" 2>/dev/null || true
  TS="$(python3 -c 'import datetime;print(datetime.datetime.now().isoformat())' 2>/dev/null || echo now)"
  echo "$TS LABEL_MISSING tools=$TOOLS" >> "$HOME/.claude/.orch-violations.log" 2>/dev/null || true
fi

exit 0
