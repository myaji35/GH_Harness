#!/bin/bash
# hermes-ctl.sh — Hermes 무인 운영 제어 (start/stop/status/run)
#
# 사용법:
#   hermes-ctl.sh start [분]   cron 등록 (기본 30분 간격) + 킬스위치 해제
#   hermes-ctl.sh stop         킬스위치 ON + cron 제거 → 즉시 정지
#   hermes-ctl.sh status       운영 상태·오늘 호출 수·마지막 실행 조회
#   hermes-ctl.sh run          지금 1 tick 수동 실행

set -uo pipefail

AOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_ROOT="$(cd "$AOS_DIR/../.." && pwd)"
REGISTRY="$HARNESS_ROOT/.claude/issue-db/registry.json"
KILL="$AOS_DIR/hermes.stop"
RUN="$AOS_DIR/hermes-run.sh"
CRON_TAG="# AGENT-OS-HERMES"

SUB="${1:-status}"
shift || true

case "$SUB" in
  start)
    INTERVAL="${1:-30}"
    rm -f "$KILL"
    # 기존 Hermes cron 제거 후 신규 등록 (다른 cron 보존)
    ( crontab -l 2>/dev/null | grep -v "$CRON_TAG"; \
      echo "*/$INTERVAL * * * * /bin/bash '$RUN' >/dev/null 2>&1 $CRON_TAG" ) | crontab -
    # registry interval 기록
    python3 -c "
import json,tempfile,os,shutil
p='$REGISTRY'; d=json.load(open(p,encoding='utf-8'))
d.setdefault('hermes_state',{})['interval_min']=$INTERVAL
d['hermes_state']['started_at']=__import__('datetime').datetime.now(__import__('datetime').timezone.utc).isoformat()
fd,t=tempfile.mkstemp(dir=os.path.dirname(p))
json.dump(d,os.fdopen(fd,'w',encoding='utf-8'),ensure_ascii=False,indent=2); shutil.move(t,p)
" 2>/dev/null || true
    echo "🤖 Hermes 무인 운영 시작 — ${INTERVAL}분 간격 cron 등록."
    echo "   구독 토큰(claude -p) 사용 · API 비용 없음 · 정지: agent-os hermes stop"
    bash "$RUN" >/dev/null 2>&1 || true
    ;;
  stop)
    touch "$KILL"
    crontab -l 2>/dev/null | grep -v "$CRON_TAG" | crontab - 2>/dev/null || true
    bash "$AOS_DIR/hub/hub-render.sh" >/dev/null 2>&1 || true
    echo "🛑 Hermes 정지 — 킬스위치 ON, cron 제거됨. 재시작: agent-os hermes start"
    ;;
  run)
    echo "▶ Hermes 1 tick 수동 실행..."
    bash "$RUN"
    ;;
  status)
    echo "═══ Hermes 운영 상태 ═══"
    if [ -f "$KILL" ]; then echo "상태: 🛑 정지됨 (킬스위치 ON)"
    elif crontab -l 2>/dev/null | grep -q "$CRON_TAG"; then echo "상태: 🤖 운영 중 (cron 등록됨)"
    else echo "상태: ⚪ 미운영 (cron 없음)"; fi
    crontab -l 2>/dev/null | grep "$CRON_TAG" | sed 's/^/cron: /' || true
    if [ -f "$REGISTRY" ] && command -v python3 >/dev/null 2>&1; then
      python3 -c "
import json,datetime
d=json.load(open('$REGISTRY',encoding='utf-8'))
runs=d.get('hermes_runs',[]); st=d.get('hermes_state',{})
today=datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%d')
calls=sum(r.get('claude_calls',0) for r in runs if str(r.get('ts','')).startswith(today))
print(f'총 실행: {len(runs)}회')
print(f'오늘 claude 호출(구독): {calls}회 / 상한 {__import__(\"os\").environ.get(\"HERMES_DAILY_CALL_CAP\",\"30\")}')
print(f'간격: {st.get(\"interval_min\",30)}분')
print(f'마지막 실행: {st.get(\"last_run\",\"없음\")}')
" 2>/dev/null || true
    fi
    ;;
  *)
    echo "[hermes-ctl] 사용법: hermes {start [분]|stop|status|run}" >&2
    exit 1
    ;;
esac
