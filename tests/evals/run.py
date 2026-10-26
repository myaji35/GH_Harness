"""GH_Harness 골든 평가 — 하네스 hook·모드·라우팅을 바꾼 뒤 점수가 떨어지지 않았는지 본다.
사용: python3 tests/evals/run.py [--json]
각 사례는 임시 프로젝트 폴더에서 실제 hook 을 실행해 판정한다(저장소의 registry 는 건드리지 않는다).
"""
import json
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '../..'))
HOOKS = os.path.join(ROOT, 'project/.claude/hooks')
sys.path.insert(0, os.path.dirname(__file__))
from review_tier import overall  # noqa: E402

cases = json.load(open(os.path.join(os.path.dirname(__file__), 'cases/golden.json')))
results = []


def record(group, name, ok, detail=''):
    results.append(dict(group=group, name=name, ok=bool(ok), detail=detail))


def temp_project(issues):
    d = tempfile.mkdtemp(prefix='harness-eval-')
    os.makedirs(f'{d}/.claude/issue-db')
    os.symlink(HOOKS, f'{d}/.claude/hooks')
    # 실제 registry 와 같은 최소 골격(stats·hooks·knowledge) — 없으면 hook 이 KeyError 로 죽는다
    json.dump({'version': 'eval', 'issues': issues, 'stats': {'total_issues': 0, 'completed': 0, 'failed': 0, 'evolved': 0},
               'hooks': {k: [] for k in ('on_create', 'on_start', 'on_complete', 'on_fail', 'on_learn')},
               'knowledge': {'success_patterns': [], 'failure_patterns': [], 'meta_observations': []}},
              open(f'{d}/.claude/issue-db/registry.json', 'w'))
    return d


def env():
    e = dict(os.environ)
    e.pop('FACTORY_RUNNER', None)
    e['HARNESS_EVAL'] = '1'
    return e


for c in cases['intent']:
    d = temp_project([])
    subprocess.run(['bash', f'{HOOKS}/intent-gate.sh'], input=json.dumps({'prompt': c['prompt'], 'session_id': 'eval'}),
                   cwd=d, capture_output=True, text=True, timeout=30, env=env())
    made = len(json.load(open(f'{d}/.claude/issue-db/registry.json')).get('issues', [])) > 0
    record('intent', c['prompt'][:40], made == c['issue'], f"기대 이슈={c['issue']} 실제={made}")

for c in cases['route']:
    out = subprocess.run(['bash', f'{HOOKS}/axis-router.sh', c['type']], capture_output=True, text=True, timeout=10).stdout.strip()
    record('route', c['type'], out == c['expect'], f"기대 {c['expect']} 실제 {out}")

for c in cases['fold']:
    d = temp_project([{'id': 'ISS-001', 'title': 'eval', 'type': c['type'], 'status': 'READY',
                       'priority': 'P2', 'assign_to': c['assign_to'], 'payload': {}}])
    p = subprocess.run(['bash', f'{HOOKS}/dispatch-ready.sh'], cwd=d, capture_output=True, text=True, timeout=60, env=env())
    out = p.stdout + p.stderr
    # 대표님 지시 이슈면 '즉시 스폰', 자동 파생이면 '담당(예정)' 으로 나온다 — 둘 다 같은 담당·모델을 보인다
    m = re.search(r'(\S+) 에이전트를 model=(\S+)', out) or re.search(r'담당(?:\(예정\))?: (\S+) \(model: (\w+)', out)
    agent, model = (m.group(1), m.group(2)) if m else ('', '')
    iss = json.load(open(f'{d}/.claude/issue-db/registry.json'))['issues'][0]
    if c.get('no_fold'):
        record('fold', f"{c['assign_to']} 유지", '[Fold]' not in out, '접지 않아야 하는 에이전트')
        continue
    ok = agent == c['agent']
    if c.get('mode_key'):
        ok = ok and iss.get('payload', {}).get(c['mode_key']) == c['mode']
    if c.get('model'):
        ok = ok and model == c['model']
    record('fold', f"{c['assign_to']}→{c['agent']}", ok, f"스폰 {agent or '?'} model={model or '?'} payload={iss.get('payload')}")

for c in cases['review_tier']:
    got = overall(c['paths'])
    record('review_tier', ','.join(c['paths'])[:50], got == c['expect'], f"기대 {c['expect']} 실제 {got}")

# 스킬 형식(Agent Skills 표준): SKILL.md + name(=폴더명) + description
sk = os.path.join(ROOT, 'global/skills')
for name in sorted(os.listdir(sk)):
    if name.startswith('.') or name.startswith('._') or not os.path.isdir(f'{sk}/{name}'):
        continue
    f = f'{sk}/{name}/SKILL.md'
    text = open(f).read() if os.path.isfile(f) else ''
    fm = re.match(r'^---\n(.*?)\n---', text, re.S)
    n = re.search(r'^name:\s*(.+)$', fm.group(1), re.M).group(1).strip() if fm and re.search(r'^name:', fm.group(1), re.M) else ''
    desc = bool(fm and re.search(r'^description:\s*\S', fm.group(1), re.M))
    record('skill_format', name, os.path.isfile(f) and n == name and desc,
           'OK' if os.path.isfile(f) else 'SKILL.md 없음' + ('' if n == name else f' name={n!r}') + ('' if desc else ' description 없음'))

score = sum(r['ok'] for r in results)
if '--json' in sys.argv:
    print(json.dumps(dict(score=score, total=len(results), results=results), ensure_ascii=False, indent=1))
else:
    for g in dict.fromkeys(r['group'] for r in results):
        rs = [r for r in results if r['group'] == g]
        print(f"\n[{g}] {sum(r['ok'] for r in rs)}/{len(rs)}")
        for r in rs:
            if not r['ok']:
                print(f"  ✗ {r['name']} — {r['detail']}")
    print(f"\n총점 {score}/{len(results)}")
sys.exit(0 if score == len(results) else 1)
