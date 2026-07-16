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

# ── 시스템 알림 차단 (무한 루프 방지) ⭐ 2026-07-15 ──
# UserPromptSubmit에는 사람이 친 것뿐 아니라 하네스/하네스가 뱉은 알림도 들어온다.
# 이걸 지시로 오분류하면: 알림 → 이슈 생성 → READY 증가 → dispatch-ready exit 2(rewake)
#                        → 응답 → Stop 훅 → 또 알림 → ... 무한 루프.
# 실제 사고: 2026-07-15 Bloomberg. 제목이 "[지시] <task-notification>..."인 쓰레기 이슈가
#            반복 생성되고 Stop 훅이 수십 회 재발화. payload.raw_prompt에 훅 자기 출력이 그대로 박힘.
case "$PROMPT" in
  *"<task-notification>"*|*"<system-reminder>"*|*"[SYSTEM NOTIFICATION"*|\
  *"Stop hook feedback"*|*"Harness Auto-Dispatch"*|*"[자동 실행 지시]"*|\
  *"[지시 분류 게이트]"*|*"hook blocking error"*|*"[Harness Freeze]"*)
    exit 0 ;;
esac

# ── 분류 ──
# 즉답/조회형(이슈화 제외): 짧은 조회·상태·값변경·하네스 메타 명령
# 실작업형(이슈화 강제): 코드 산출물을 만들거나 바꾸는 동사
python3 - "$PROMPT" <<'PY'
import sys, re, json, datetime

prompt = sys.argv[1]
low = prompt.lower()

# 0) 제외: 너무 짧거나(즉답), 하네스 메타 트리거(이미 자체 파이프라인 보유), 조회/설명형
# 주의: 'harness'/'하네스'는 여기 두지 않는다. 대표님이 "harness, 00 구현해줘"처럼
#       하네스를 호출하며 작업을 지시하는 습관이 있어, EXCLUDE에 두면 오히려 자동화가 꺼진다.
#       harness 메타 '명령'(시작/업데이트/업그레이드)은 아래 HARNESS_META_CMD에서 별도 제외.
EXCLUDE_META = ['점검', '확인해', '상태 보여', '스캔',
                'biz check', '비즈', 'race mode', '레이스', '화면 갭', 'graphify',
                '커밋', 'push', '푸시', '의견', '어떻게 생각', '알려줘', '설명',
                '보여줘', '뭐야', '무엇', '왜', '리스트', '목록', '찾아줘',
                '반영', '되고 있', '제대로', '맞나', '맞아', '되나', '하고 있',
                # 규칙성 메타 지시 — 작업이 아니라 CLAUDE.md에 박을 규칙 (ISS-073 오인 방지)
                '앞으로', '항상', '매번', '언제나', '규칙으로', '~하게 해', '하도록 해',
                '하게 해줘', '하도록 해줘', '습관', '원칙으로']

# 0-a) harness 메타 '명령'만 제외 (자체 파이프라인 보유). 작업 동사가 없을 때만 메타로 본다.
#      "harness 시작/업데이트/업그레이드/초기화" → 메타 → 통과.
#      "harness, 00 구현/이슈화/검증해줘" → 작업 → 아래 WORK 로직으로 진행(이슈화).
HARNESS_META_CMD = ['harness 시작', '하네스 시작', 'harness init', 'harness 업데이트',
                    '하네스 업데이트', 'harness update', 'harness 업그레이드',
                    '하네스 업그레이드', 'harness 초기화', '하네스 초기화']

# 0-b) 의문문/조회형 우선 통과 — 실작업 동사가 섞여도 '질문'이면 이슈화하지 않는다.
#      (ISS-074: '~기능 반영되고 있나?' 같은 메타질문이 WORK 동사에 걸려 오탐하던 버그)
#      조회형 통과는 이슈를 '안 만드는' 안전 방향이라 전역 적용해도 부작용이 적다.
QUESTION = ['?', '？', '나요', '습니까', '까요', '는가', '은가', '했는데', '하는데',
            '되는지', '있는지', '인지', '될까', '할까']
def asks():
    p = prompt.strip()
    return any(p.endswith(q) or q in p for q in QUESTION)

# 0-b-2) ⭐ 아이디어 포착 레인 (2026-07-16, 대표님 "맨날 이렇게 누수가 되는것이 스트레스네")
# 문제: 대표님은 아이디어를 **제안형·회상형**으로 말한다 — "~하자", "~하면 좋겠어",
#   "~보고 싶었거든", "~생각했어". 이 말투엔 WORK 동사('추가/구현/만들어')가 없어서
#   위 `not has(WORK)` 통과로 **전량 유실**됐고, "~하자 했는데 ...있나?"는 QUESTION에도 걸려
#   이중으로 샜다. 실유실 사례: reset 버튼(대표님 재지적으로 발견), 상황판 탭 순환, 공격 지도.
# 해법: 순수 질문("이거 뭐야?")과 아이디어("~하면 좋겠어")를 분리해, 아이디어만 BACKLOG로 적재.
#   - READY가 아니라 **BACKLOG**로 넣는다: 지나가듯 한 말에 에이전트가 즉시 착수하면 안 된다.
#     대표님이 나중에 훑어보고 올리는 대기열이다(포착이 목적, 실행 강제가 아님).
#   - QUESTION보다 **먼저** 판정한다: "~하자 했는데 있나?"를 잡으려면 순서가 앞서야 한다.
# 어미 중심으로 잡는다 — 앞 동사가 뭐든('하면/보여주면/붙이면/넣으면...') 걸리도록
# '~면 좋겠'처럼 조각으로 둔다. 특정 동사를 나열하면 반드시 빠지는 게 생긴다
# (2026-07-16: '하면 좋겠'만 넣었다가 "보여주면 좋겠어"를 놓쳐 실패).
IDEA = ['면 좋겠', '면 좋을', '으면 해', '했으면', '좋겠어', '좋겠네', '좋겠다',
        '하자', '넣자', '만들자', '붙이자', '해보자', '가자',
        '보고 싶', '하고 싶', '생각했어', '생각중', '생각이야', '아이디어',
        '어때', '어떨까', '하는게 좋', '하는 게 좋',
        '필요할듯', '필요할 듯', '필요해 보', '있으면 좋', '있었으면']
# 아이디어 신호가 있어도 이것만 있으면 단순 의견/평가라 적재하지 않는다.
IDEA_EXCLUDE = ['좋아', '맞아', '그래', '고마워', '수고']

def is_idea():
    p = prompt.strip()
    if len(p) < 12:
        return False
    if not any(k in p for k in IDEA):
        return False
    # 순수 감탄/동의는 제외
    if p in IDEA_EXCLUDE:
        return False
    return True

if is_idea():
    try:
        REG_I = ".claude/issue-db/registry.json"
        reg_i = json.load(open(REG_I))
        raw = prompt.strip().replace('\n', ' ')
        title_i = ('[아이디어] ' + raw)[:80]
        # 중복 방지: 같은 제목이 이미 있으면 재적재 안 함
        dup = any(i.get('title') == title_i for i in reg_i.get('issues', []))
        if not dup:
            def num_i(iid):
                try: return int(''.join(c for c in str(iid).split('-')[-1] if c.isdigit()) or 0)
                except: return 0
            nums_i = [num_i(i.get('id', '')) for i in reg_i.get('issues', [])]
            nxt_i = (max(nums_i) if nums_i else 0) + 1
            while any(i.get('id') == f'ISS-{nxt_i:03d}' for i in reg_i['issues']):
                nxt_i += 1
            now_i = datetime.datetime.now().isoformat()
            reg_i['issues'].append({
                'id': f'ISS-{nxt_i:03d}', 'title': title_i, 'type': 'IDEA',
                'status': 'BACKLOG', 'priority': 'P3', 'assign_to': 'product-manager',
                'depth': 0, 'created_at': now_i, 'updated_at': now_i,
                'payload': {'origin': 'intent-gate:idea', 'raw_prompt': raw,
                            'note': '대표님 제안형 발화 자동 포착. BACKLOG라 자동 착수 안 함 — '
                                    '검토 후 READY로 올려야 실행된다.'},
            })
            json.dump(reg_i, open(REG_I, 'w'), indent=2, ensure_ascii=False)
            print(f"[아이디어 포착] {f'ISS-{nxt_i:03d}'} BACKLOG 등재 — 유실 방지. "
                  f"지금 실행할지는 대표님 지시를 따르되, 기록은 남았다.")
    except Exception:
        pass  # 포착 실패가 대화를 막으면 안 된다(보수)
    # 아이디어는 적재만 하고 통과 — 실작업 이슈화는 아래 WORK 로직이 별도 판정.

if asks():
    sys.exit(0)
# 실작업형 동사(이것이 있으면 이슈화)
WORK = ['추가', '구현', '만들어', '만들어줘', '생성해', '개발',
        '수정', '고쳐', '버그', 'fix', '리팩터', '리팩토링', 'refactor',
        '바꿔줘', '변경해', '교체', '삭제해', '제거해', '연동', '통합해',
        'feature', 'implement', '기능']

def has(words):
    return any(w in low or w in prompt for w in words)

# 우선순위: harness 메타 '명령'(시작/업데이트 등)이면 통과 — 자체 파이프라인이 처리
if has(HARNESS_META_CMD):
    sys.exit(0)
# 메타/조회형이면 통과(이슈화 X)
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
