#!/bin/bash
# Jev 섀도 대기열 처리 / report — intent-gate 판정에는 관여하지 않는다.
set -euo pipefail
python3 - "$@" <<'PY'
import datetime
import fcntl
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.request

D = os.environ.get('JEV_SHADOW_DIR') or os.path.expanduser('~/.claude/jev-shadow')
API_KEY = ''
API_BASE = ''
API_MODEL = ''
CRITERIA = {
    'work': '지금 코드·설정·파일·문서를 만들거나 고치라는 실행 지시 (승인·착수 지시 포함)',
    'query': '질문, 조회, 설명·의견·리서치·보고 요청 — 산출물 변경을 지시하지 않음',
    'rule': '앞으로 지킬 규칙·습관을 정하는 메타 지시',
    'idea': '제안·아이디어·바람 표현이며 지금 당장 실행하라는 지시는 아님',
    'none': '위 어디에도 해당하지 않음(잡담, 알림, 판단 불가)',
}


def now():
    return datetime.datetime.now().isoformat(timespec='seconds')


def record_key(rec):
    return hashlib.sha1((rec['ts'] + rec['prompt']).encode('utf-8')).hexdigest()


def read_jsonl(name):
    try:
        with open(os.path.join(D, name), encoding='utf-8') as f:
            for line in f:
                try:
                    rec = json.loads(line)
                except ValueError:
                    # append 중인 마지막 줄은 다음 실행에서 다시 읽는다.
                    continue
                if isinstance(rec, dict):
                    yield rec
    except FileNotFoundError:
        return


def error_lines():
    try:
        with open(os.path.join(D, 'errors.log'), encoding='utf-8') as f:
            return f.readlines()
    except FileNotFoundError:
        return []


def log_error(key, kind, message):
    message = str(message)
    if API_KEY:
        message = message.replace(API_KEY, '<redacted>')
    message = ' '.join(message.split())[:200]
    with open(os.path.join(D, 'errors.log'), 'a', encoding='utf-8') as f:
        f.write(f'{now()} {key} {kind} {message}\n')


def load_access():
    providers = (
        ('KSS_TYPESAFE_API_KEY', 'https://api.typesafe.ai', 'jev-latest'),
        ('KSS_AI_GATEWAY_API_KEY', 'https://ai-gateway.vercel.sh/typesafe', 'typesafe-ai/jev'),
    )

    def access(key, base, model):
        return (key, os.environ.get('TYPESAFE_API_BASE') or base,
                os.environ.get('JEV_MODEL') or model)

    for name, base, model in providers:
        key = os.environ.get(name, '').strip()
        if key:
            return access(key, base, model)
    try:
        with open('/Volumes/E_SSD/02_GitHub.nosync/.env', encoding='utf-8') as f:
            lines = f.readlines()
        for name, base, model in providers:
            for line in lines:
                line = line.strip()
                if line.startswith(name + '='):
                    key = line.split('=', 1)[1].strip().strip('\"\'')
                    if key:
                        return access(key, base, model)
    except FileNotFoundError:
        pass
    return ('', '', '')


def rate(correct, total):
    return f'{correct / total:.2%}' if total else 'N/A'


def agrees(rec):
    return (rec['rule'] == 'work') == (rec['jev_intent'] == 'work')


def report(queue, results):
    rows = list(results.values())
    count = len(rows)
    print(f'처리 건수: {count} / 대기 건수: {len(queue.keys() - results.keys())}'
          f' / 에러 건수: {len(error_lines())}')
    print('\n혼동행렬 (rule 행 × jev 열)')
    print(f'{"rule / jev":<14} {"WORK":>10} {"NOT_WORK":>10}')
    for rule_work, title in ((True, 'WORK'), (False, 'NOT_WORK')):
        cells = [sum((r['rule'] == 'work') == rule_work and
                     (r['jev_intent'] == 'work') == jev_work for r in rows)
                 for jev_work in (True, False)]
        print(f'{title:<14} {cells[0]:>10} {cells[1]:>10}')
    print(f'일치율: {rate(sum(agrees(r) for r in rows), count)}')
    print('\njev_conf 구간별 건수 / 일치율')
    for title, low, high in (('<0.5', 0, 0.5), ('0.5-0.9', 0.5, 0.9),
                             ('0.9-0.99', 0.9, 0.99), ('>=0.99', 0.99, float('inf'))):
        group = [r for r in rows if low <= r['jev_conf'] < high]
        print(f'{title:<10} {len(group):>6} / {rate(sum(agrees(r) for r in group), len(group))}')

    if os.path.exists(os.path.join(D, 'labels.jsonl')):
        labels = {r['key']: r['label'] for r in read_jsonl('labels.jsonl')
                  if isinstance(r.get('key'), str) and r.get('label') in CRITERIA}
        labeled = [r for r in rows if r['key'] in labels]
        high_conf = [r for r in labeled if r['jev_conf'] >= 0.99]

        def accuracy(group, field):
            correct = sum((r[field] == 'work') == (labels[r['key']] == 'work') for r in group)
            return rate(correct, len(group))

        print(f'\n라벨 평가 (처리 완료·라벨 보유 {len(labeled)}건)')
        print(f'rule 정확도: {accuracy(labeled, "rule")}')
        print(f'jev 정확도: {accuracy(labeled, "jev_intent")}')
        print(f'jev_conf>=0.99 정확도: {accuracy(high_conf, "jev_intent")}')
        print(f'jev_conf>=0.99 커버리지 (라벨 평가 대상 중): '
              f'{rate(len(high_conf), len(labeled))} ({len(high_conf)}/{len(labeled)})')

    print('\n불일치 상위 20건 (jev_conf 내림차순)')
    mismatches = sorted((r for r in rows if not agrees(r)),
                        key=lambda r: r['jev_conf'], reverse=True)
    for r in mismatches[:20]:
        prompt = queue.get(r['key'], {}).get('prompt', '')[:60]
        print(f'{r["key"]} rule={r["rule"]} jev_intent={r["jev_intent"]}'
              f' jev_conf={r["jev_conf"]} prompt={json.dumps(prompt, ensure_ascii=False)}')
    average = f'{sum(r["latency_ms"] for r in rows) / count:.2f}' if count else 'N/A'
    tokens = sum(r['input_tokens'] for r in rows)
    print(f'\n평균 latency_ms: {average}')
    print(f'총 input_tokens: {tokens}')
    print(f'추정비용: {tokens / 1e6 * 0.042:.8f} USD')


def probability(value):
    return type(value) in (int, float) and 0 <= value <= 1


def evaluate(rec):
    body = {
        'model': API_MODEL,
        'state': {'발화': rec['prompt']},
        'questions': {
            'intent': {
                'type': 'choice',
                'instructions': '이 발화는 개발 하네스 운영자(대표님)가 AI 코딩 에이전트에게 한 말이다. 발화의 주된 의도를 고르라.',
                'criteria': CRITERIA,
            },
            'is_work': {
                'type': 'noul',
                'instructions': '이 발화가 지금 코드·설정·파일 변경 작업을 실행하라는 지시인가?',
            },
        },
    }
    request = urllib.request.Request(
        API_BASE.rstrip('/') + '/v1/systemone',
        data=json.dumps(body, ensure_ascii=False).encode('utf-8'),
        headers={'Authorization': 'Bearer ' + API_KEY, 'Content-Type': 'application/json'},
        method='POST',
    )
    started = time.monotonic()
    for attempt in range(2):
        try:
            with urllib.request.urlopen(request, timeout=10) as response:
                data = json.load(response)
            break
        except urllib.error.HTTPError as exc:
            exc.close()
            if exc.code in (429, 529) and attempt == 0:
                time.sleep(2)
                continue
            raise

    # 필수 응답이 없거나 잘못되면 실패로 남긴다. 기본값으로 결과를 꾸미지 않는다.
    intent = data['answers']['intent']
    is_work = data['answers']['is_work']['noul']
    choice = intent['choice']
    probs = intent['probabilities']
    confidence = intent['confidence']
    tokens = data['usage']['input_tokens']
    if (choice not in CRITERIA or not isinstance(probs, dict)
            or (not probs or not set(probs) <= set(CRITERIA))
            or not all(probability(p) for p in probs.values())
            or not probability(confidence) or not probability(is_work)
            or type(tokens) is not int or tokens < 0):
        raise ValueError('invalid API response fields')
    return {
        'key': record_key(rec), 'ts': rec['ts'], 'project': rec['project'],
        'rule': rec['rule'], 'idea': rec['idea'], 'prompt_len': len(rec['prompt']),
        'jev_intent': choice, 'jev_probs': probs, 'jev_conf': confidence,
        'jev_is_work': is_work, 'latency_ms': round((time.monotonic() - started) * 1000, 2),
        'input_tokens': tokens, 'checked_at': now(),
        'via': 'gateway' if 'ai-gateway.vercel.sh' in API_BASE else 'typesafe',
    }


def main():
    global API_KEY, API_BASE, API_MODEL
    if sys.argv[1:] not in ([], ['report']):
        print('Usage: jev-shadow.sh [report]', file=sys.stderr)
        return 2
    os.makedirs(D, exist_ok=True)
    with open(os.path.join(D, '.lock'), 'a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return 0
        queue = {record_key(r): r for r in read_jsonl('queue.jsonl')
                 if isinstance(r.get('ts'), str) and isinstance(r.get('prompt'), str)}
        results = {r['key']: r for r in read_jsonl('results.jsonl')
                   if isinstance(r.get('key'), str)}
        if sys.argv[1:] == ['report']:
            report(queue, results)
            return 0

        API_KEY, API_BASE, API_MODEL = load_access()
        if not API_KEY:
            today = datetime.date.today().isoformat()
            if not any(line.startswith(today + 'T') and line.split()[2:3] == ['no_key']
                       for line in error_lines()):
                log_error('-', 'no_key', 'KSS_TYPESAFE_API_KEY / KSS_AI_GATEWAY_API_KEY not configured')
            return 0

        attempted = 0
        for key, rec in queue.items():
            if key in results:
                continue
            if attempted >= 50:
                break
            attempted += 1
            try:
                result = evaluate(rec)
                with open(os.path.join(D, 'results.jsonl'), 'a', encoding='utf-8') as f:
                    f.write(json.dumps(result, ensure_ascii=False) + '\n')
                results[key] = result
            except urllib.error.HTTPError as exc:
                log_error(key, exc.code, exc.reason)
                if exc.code == 401:
                    break
            except Exception as exc:
                log_error(key, type(exc).__name__, exc)
    return 0


try:
    sys.exit(main())
except Exception as exc:
    # worker 자체 실패도 훅의 stdout/stderr로 전파하지 않는다.
    try:
        log_error('-', type(exc).__name__, exc)
    except Exception:
        pass
    sys.exit(0)
PY
