#!/bin/bash
# hermes-run.sh — Hermes 무인 운영 루프 (Agent OS · cron이 호출)
#
# 하네스 버전 Hermes를 Claude Code(claude -p) 기반으로 무인 운영한다.
# 영상1(Tech Bridge)의 "Hermes가 Claude Code를 백그라운드에서 호출" 구조.
#
# ⭐ 비용 원칙 (대표님 확정):
#   - claude -p = 대표님 Claude '구독 토큰' 사용 → 별도 API 비용 없음.
#   - API 키(ANTHROPIC_API_KEY 등)는 절대 사용하지 않는다. (Gemini 유출 사고 방어)
#   - 안전장치 = '비용 상한'이 아니라 '호출 횟수 상한 + 킬스위치 + 레이트리밋 대기'.
#
# 매 실행(cron tick)이 하는 일:
#   1. 킬스위치(hermes.stop) 확인 → 있으면 즉시 종료
#   2. hub 재렌더 (읽기 전용, 호출 0)
#   3. 일일 호출 상한 확인 → 여유 있으면 READY 이슈 1건에 claude -p 자문
#   4. hermes_runs[] 에 기록 (append)
#
# 사용법: hermes-run.sh          (cron/수동 1 tick)
# exit 0 = 정상, 4 = 킬스위치, 5 = trust 미승인

set -uo pipefail

AOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_ROOT="$(cd "$AOS_DIR/../.." && pwd)"
REGISTRY="$HARNESS_ROOT/.claude/issue-db/registry.json"
KILL="$AOS_DIR/hermes.stop"
LOG="$AOS_DIR/hermes.log"

# 일일 호출 상한 (구독 레이트리밋 보호용 — 비용 아님)
DAILY_CALL_CAP="${HERMES_DAILY_CALL_CAP:-30}"

ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }
log() { echo "[$(ts)] $*" >> "$LOG"; echo "[hermes-run] $*"; }

# --- 1. 킬스위치 ------------------------------------------------------
if [ -f "$KILL" ]; then
  log "🛑 킬스위치 감지 (hermes.stop) — 실행 중단."
  # hub는 여전히 '정지됨' 배지를 위해 재렌더
  bash "$AOS_DIR/hub/hub-render.sh" >/dev/null 2>&1 || true
  exit 4
fi

# --- API 키 사용 차단 (구독 전용 강제) --------------------------------
# claude -p가 실수로 API 키 경로를 타지 않도록 환경에서 제거
unset ANTHROPIC_API_KEY 2>/dev/null || true

# --- 2. hub 재렌더 (읽기 전용) ----------------------------------------
bash "$AOS_DIR/hub/hub-render.sh" >/dev/null 2>&1 && RENDER_OK=1 || RENDER_OK=0

# --- 3. 오늘 호출 횟수 확인 -------------------------------------------
TODAY="$(date -u +%Y-%m-%d)"
CALLS_TODAY=0
if [ -f "$REGISTRY" ] && command -v python3 >/dev/null 2>&1; then
  CALLS_TODAY="$(python3 -c "
import json
d=json.load(open('$REGISTRY',encoding='utf-8'))
print(sum(r.get('claude_calls',0) for r in d.get('hermes_runs',[]) if str(r.get('ts','')).startswith('$TODAY')))
" 2>/dev/null || echo 0)"
fi

ACTION="render"
DETAIL="hub 재렌더"
CLAUDE_CALLS=0

# --- 4. 자문 대상 이슈 있으면 claude -p 호출 --------------------------
if [ "$CALLS_TODAY" -ge "$DAILY_CALL_CAP" ]; then
  log "일일 호출 상한($DAILY_CALL_CAP) 도달 — 이번 tick은 렌더만."
  DETAIL="상한 도달, 렌더만"
elif command -v claude >/dev/null 2>&1; then
  # READY 상태의 자문 필요 이슈 1건 추출
  TARGET="$(python3 -c "
import json
d=json.load(open('$REGISTRY',encoding='utf-8'))
for i in d.get('issues',[]):
    if i.get('status')=='READY':
        print(i.get('id',''))
        break
" 2>/dev/null || echo "")"

  if [ -n "$TARGET" ]; then
    TITLE="$(python3 -c "
import json
d=json.load(open('$REGISTRY',encoding='utf-8'))
print(next((i.get('title','') for i in d.get('issues',[]) if i.get('id')=='$TARGET'),''))
" 2>/dev/null)"
    log "READY 이슈 $TARGET 자문 (claude -p, 구독): $TITLE"
    # 자문만 — 무검증 자동수정/커밋은 하지 않는다 (읽기+제안까지만)
    ADVICE="$(cd "$HARNESS_ROOT" && timeout 120 claude -p "다음 하네스 이슈에 대해 '다음 실행 단계 3줄'만 한국어로 제안하세요(코드 수정 금지, 제안만): [$TARGET] $TITLE" 2>/dev/null || true)"
    CLAUDE_CALLS=1
    ACTION="advise"
    DETAIL="$TARGET 자문"
    # 제안을 이슈 payload에 기록 (자동 수정 아님)
    if [ -n "$(echo "$ADVICE" | tr -d '[:space:]')" ]; then
      python3 -c "
import json,tempfile,os,shutil
p='$REGISTRY'; d=json.load(open(p,encoding='utf-8'))
for i in d.get('issues',[]):
    if i.get('id')=='$TARGET':
        i.setdefault('hermes_advice',[]).append({'ts':'$(ts)','advice':'''$ADVICE'''[:800]})
fd,t=tempfile.mkstemp(dir=os.path.dirname(p))
json.dump(d,os.fdopen(fd,'w',encoding='utf-8'),ensure_ascii=False,indent=2); shutil.move(t,p)
" 2>/dev/null || true
    fi
  else
    DETAIL="READY 이슈 없음, 렌더만"
  fi
fi

# --- 5. hermes_runs 기록 ---------------------------------------------
if [ -f "$REGISTRY" ] && command -v python3 >/dev/null 2>&1; then
  python3 -c "
import json,tempfile,os,shutil
p='$REGISTRY'; d=json.load(open(p,encoding='utf-8'))
d.setdefault('hermes_runs',[]).append({
  'ts':'$(ts)','action':'$ACTION','detail':'''$DETAIL''',
  'claude_calls':$CLAUDE_CALLS,'render_ok':bool($RENDER_OK),'token_source':'subscription'})
d.setdefault('hermes_state',{})['last_run']='$(ts)'
d['hermes_state']['interval_min']=d['hermes_state'].get('interval_min',30)
fd,t=tempfile.mkstemp(dir=os.path.dirname(p))
json.dump(d,os.fdopen(fd,'w',encoding='utf-8'),ensure_ascii=False,indent=2); shutil.move(t,p)
" 2>/dev/null || true
fi

# hub를 최종 상태로 한 번 더 렌더(배지 갱신)
bash "$AOS_DIR/hub/hub-render.sh" >/dev/null 2>&1 || true
log "완료 (action=$ACTION, claude_calls=$CLAUDE_CALLS, 오늘누적=$((CALLS_TODAY+CLAUDE_CALLS)))"
