#!/bin/bash
# intent-gate.sh — v5.3 / 지시 분류 게이트
# UserPromptSubmit 시점 호출. 대표님의 단순 프롬프트를 3분류:
#   실작업형 → registry.json에 이슈 자동 생성 + 검증루프 안내(stdout 컨텍스트 주입)
#   즉답형/조회형 → 통과(이슈화 X)
#   모호형 → 통과(Claude가 시작 전 1회 옵션 제시 — 메타룰 #1)
# 근거: 대표님 "단순 지시도 이슈화→구현→검증 강제" 요청(2026-06-29). 강도=실작업형만.
set -euo pipefail

REGISTRY=".claude/issue-db/registry.json"
[ -f "$REGISTRY" ] || exit 0   # 하네스 미설치 프로젝트는 통과

# UserPromptSubmit hook은 stdin으로 JSON({prompt:...}) 수신
INPUT="$(cat)"
PROMPT="$(printf '%s' "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('prompt',''))" 2>/dev/null || true)"
[ -n "$PROMPT" ] || exit 0

# ── 분류 ──
# 즉답/조회형(이슈화 제외): 짧은 조회·상태·값변경·하네스 메타 명령
# 실작업형(이슈화 강제): 코드 산출물을 만들거나 바꾸는 동사
python3 - "$PROMPT" <<'PY'
import sys, re, json, datetime

prompt = sys.argv[1]
low = prompt.lower()

# 0) 제외: 너무 짧거나(즉답), 하네스 메타 트리거(이미 자체 파이프라인 보유), 조회/설명형
EXCLUDE_META = ['harness', '하네스', '점검', '확인해', '상태 보여', '스캔',
                'biz check', '비즈', 'race mode', '레이스', '화면 갭', 'graphify',
                '커밋', 'push', '푸시', '의견', '어떻게 생각', '알려줘', '설명',
                '보여줘', '뭐야', '무엇', '왜', '리스트', '목록', '찾아줘',
                '반영', '되고 있', '제대로', '맞나', '맞아', '되나', '하고 있',
                # 규칙성 메타 지시 — 작업이 아니라 CLAUDE.md에 박을 규칙 (ISS-073 오인 방지)
                '앞으로', '항상', '매번', '언제나', '규칙으로', '~하게 해', '하도록 해',
                '하게 해줘', '하도록 해줘', '습관', '원칙으로']

# 0-b) 의문문/조회형 우선 통과 — 실작업 동사가 섞여도 '질문'이면 이슈화하지 않는다.
#      (ISS-074: '~기능 반영되고 있나?' 같은 메타질문이 WORK 동사에 걸려 오탐하던 버그)
#      조회형 통과는 이슈를 '안 만드는' 안전 방향이라 전역 적용해도 부작용이 적다.
QUESTION = ['?', '？', '나요', '습니까', '까요', '는가', '은가', '했는데', '하는데',
            '되는지', '있는지', '인지', '될까', '할까']
def asks():
    p = prompt.strip()
    return any(p.endswith(q) or q in p for q in QUESTION)
if asks():
    sys.exit(0)
# 실작업형 동사(이것이 있으면 이슈화)
WORK = ['추가', '구현', '만들어', '만들어줘', '생성해', '개발',
        '수정', '고쳐', '버그', 'fix', '리팩터', '리팩토링', 'refactor',
        '바꿔줘', '변경해', '교체', '삭제해', '제거해', '연동', '통합해',
        'feature', 'implement', '기능']

def has(words):
    return any(w in low or w in prompt for w in words)

# 우선순위: 메타/조회형이면 통과(이슈화 X)
if has(EXCLUDE_META):
    sys.exit(0)
# 너무 짧으면(즉답형) 통과
if len(prompt.strip()) < 12:
    sys.exit(0)
# 실작업 동사 없으면 통과(모호/대화형 — Claude 판단에 맡김)
if not has(WORK):
    sys.exit(0)

# ── 여기부터 실작업형: 이슈 자동 생성 ──
REG = ".claude/issue-db/registry.json"
reg = json.load(open(REG))

# 타입 추정
if has(['버그','고쳐','fix','오류','에러']):
    itype, assign, prio = 'FIX_BUG', 'agent-harness', 'P0'
elif has(['리팩터','리팩토링','refactor','정리']):
    itype, assign, prio = 'REFACTOR', 'agent-harness', 'P2'
else:
    itype, assign, prio = 'FEATURE_PLAN', 'product-manager', 'P1'

# 중복 체크: 동일 title 활성 이슈 있으면 skip
title = ('[지시] ' + prompt.strip().replace('\n',' '))[:80]
for iss in reg['issues']:
    if iss.get('title') == title and iss.get('status') in ('READY','IN_PROGRESS'):
        sys.exit(0)

# ID 계산(on_complete.sh add_issue와 동일 규칙)
def num(iid):
    try: return int(str(iid).split('-')[-1])
    except: return 0
nums = [num(i.get('id','')) for i in reg.get('issues',[])]
nxt = max((max(nums) if nums else 0)+1, reg.get('stats',{}).get('total_issues',0)+1)
while any(i.get('id')==f'ISS-{nxt:03d}' for i in reg['issues']):
    nxt += 1
iid = f'ISS-{nxt:03d}'

now = datetime.datetime.now().isoformat()
reg['issues'].append({
    'id': iid, 'title': title, 'type': itype, 'status': 'READY',
    'priority': prio, 'assign_to': assign, 'depth': 0,
    'created_at': now, 'updated_at': now,
    'payload': {'origin': 'intent-gate', 'raw_prompt': prompt.strip()},
})
reg.setdefault('stats', {})['total_issues'] = reg['stats'].get('total_issues',0)+1
json.dump(reg, open(REG,'w'), ensure_ascii=False, indent=2)

# stdout → Claude 컨텍스트 주입(검증 루프 강제 안내 + 즉시 실행 명령)
print(f"[지시 분류 게이트] 이 지시를 실작업으로 분류 → {iid}({itype}/{prio}) 자동 생성.")
print(f"")
print(f"[강제 실행 지시 — 이 턴에서 즉시 수행하라]")
print(f"1. {iid}를 status=IN_PROGRESS로 변경하고 '이슈로 등록했습니다'로 끝내지 마라.")
print(f"   → 이슈 생성은 시작점이지 완료가 아니다. 지금 이 응답에서 바로 구현에 착수하라.")
print(f"2. {assign} 역할로 {iid}({itype})를 실제 구현/수정한다.")
print(f"3. 구현 후 bash .claude/hooks/on_complete.sh {iid} {itype} '{{...result...}}' 호출")
print(f"   → LINT/TEST/캐릭터저니 검증 자동 파생. 검증 통과 전 '완료' 보고 금지.")
print(f"4. 완료 시 {iid} status=COMPLETED.")
print(f"※ '이슈화했습니다' 또는 '다음 세션에서 처리' 류로 미루는 것은 규칙 위반이다. 지금 실행하라.")
PY
exit 0
