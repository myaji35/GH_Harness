#!/bin/bash
# prove-it-works 모니터링 리포트 — 도입(2026-10-18) 전후 2주 비교
#   bash .claude/hooks/proof-report.sh [START_DATE] [DAYS]
# 지표:
#   ① proof 판정 분포 (ok / rejected / warn)        ← .claude/knowledge-db/proof-metrics.jsonl
#   ② 되돌아옴 비율 = 완료된 코드 이슈 중 후속 수정 이슈(FIX_BUG 등)가 source_issue 로 붙은 비율
#      도입 전 DAYS 일 vs 도입 후 DAYS 일                ← .claude/issue-db/registry.json

python3 - "${1:-2026-10-18}" "${2:-14}" << 'PYEOF'
import json, sys, datetime, os

start = datetime.datetime.fromisoformat(sys.argv[1])
days = int(sys.argv[2])
before = (start - datetime.timedelta(days=days), start)
after = (start, start + datetime.timedelta(days=days))
CODE = {'GENERATE_CODE', 'FIX_BUG', 'BIZ_FIX', 'REFACTOR', 'STYLE_FIX', 'UX_FIX',
        'DESIGN_FIX', 'SCENARIO_FIX', 'QUALITY_IMPROVEMENT'}
REWORK = {'FIX_BUG', 'STYLE_FIX', 'BIZ_FIX', 'SCENARIO_FIX', 'UX_FIX', 'DESIGN_FIX', 'QUALITY_IMPROVEMENT', 'REGRESSION_CHECK'}

def ts(value):
    try:
        t = datetime.datetime.fromisoformat(str(value).replace('Z', '+00:00'))
        return t.replace(tzinfo=None) if t.tzinfo is None else t.astimezone().replace(tzinfo=None)
    except (TypeError, ValueError):
        return None

print(f"━━━ prove-it-works 리포트 · {os.path.basename(os.getcwd())} ━━━")
print(f"도입일 {start.date()} · 비교 구간 각 {days}일")

counts = {}
mpath = '.claude/knowledge-db/proof-metrics.jsonl'
if os.path.exists(mpath):
    for line in open(mpath):
        try:
            row = json.loads(line)
        except ValueError:
            continue
        t = ts(row.get('ts'))
        if t and after[0] <= t < after[1]:
            counts[row.get('outcome')] = counts.get(row.get('outcome'), 0) + 1
total = sum(counts.values())
print(f"① proof 판정 {total}건: " + (" / ".join(f"{k} {v}" for k, v in sorted(counts.items())) or "기록 없음"))
if total:
    print(f"   거부율 {counts.get('rejected', 0) * 100 // total}%  (높으면 에이전트가 형식을 모름 → 문서·프롬프트 보강)")

try:
    issues = json.load(open('.claude/issue-db/registry.json')).get('issues', [])
except (OSError, ValueError):
    print("② registry 읽기 실패"); sys.exit(0)
children = {}
for iss in issues:
    src = (iss.get('payload') or {}).get('source_issue')
    if src and iss.get('type') in REWORK:
        children.setdefault(src, []).append(iss)

def rework_rate(window):
    done = [i for i in issues if i.get('type') in CODE and i.get('status') in ('DONE', 'COMPLETED')
            and (t := ts(i.get('completed_at') or i.get('updated_at'))) and window[0] <= t < window[1]]
    back = [i for i in done if children.get(i['id'])]
    return len(done), len(back)

for label, window in (("도입 전", before), ("도입 후", after)):
    n, b = rework_rate(window)
    print(f"② {label}: 코드 이슈 완료 {n}건 중 되돌아옴 {b}건" + (f" ({b * 100 // n}%)" if n else ""))
print("판단: 도입 후 되돌아옴 비율이 낮아지고 거부율이 안정(<20%)이면 유지·다음 원칙(explain-the-number) 추가,")
print("      거부율만 높고 되돌아옴 변화 없으면 HARNESS_PROOF_MODE=warn 로 낮추고 원인 분석.")
PYEOF
