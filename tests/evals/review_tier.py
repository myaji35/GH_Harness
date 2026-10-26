"""변경 파일 경로 → 리뷰 위험 등급(low/medium/high). global/policy/REVIEW.md §1 과 같은 규칙.
사용: python3 review_tier.py <파일경로>...   (git diff --name-only 출력을 그대로 넘겨도 된다)
"""
import re
import sys

HIGH = [
    r'(^|/)config/deploy[^/]*\.ya?ml$', r'(^|/)Dockerfile$', r'(^|/)\.kamal/', r'(^|/)db/migrate/',
    r'(^|/)\.github/workflows/', r'(^|/)\.claude/hooks/', r'(^|/)project/\.claude/hooks/', r'(^|/)\.claude/settings\.json$',
    r'(auth|session|password|permission|role_authorization|credential|secret)', r'(payment|billing|charge|spend)',
    r'(^|/)config/compliance/', r'(^|/)\.env',
]
LOW = [r'\.md$', r'(^|/)docs/', r'(^|/)test/', r'(^|/)tests/', r'(^|/)spec/', r'\.txt$']


def tier(path):
    p = path.strip().lower()
    if any(re.search(r, p) for r in HIGH):
        return 'high'
    if any(re.search(r, p) for r in LOW):
        return 'low'
    return 'medium'


def overall(paths):
    order = {'low': 0, 'medium': 1, 'high': 2}
    return max((tier(p) for p in paths if p.strip()), key=order.get, default='low')


if __name__ == '__main__':
    print(overall(sys.argv[1:] or sys.stdin.read().split()))
