#!/bin/bash
# on_complete Hook 핸들러
# 이슈 완료 시: 결과 분석 → Plan 수립 → 파생 이슈 자동 생성 → 디스패치
#
# 핵심 원리:
#   단순 1:1 매핑이 아니라, result 데이터를 분석하여 "다음에 뭘 해야 하는지" 판단
#   테스트 실패 → FIX_BUG Plan / 커버리지 부족 → IMPROVE_COVERAGE Plan
#   점수 낮음 → QUALITY_IMPROVEMENT Plan / 점수 높음 → DEPLOY_READY Plan

REGISTRY=".claude/issue-db/registry.json"
ISSUE_ID="$1"
ISSUE_TYPE="$2"
RESULT="$3"

echo "[Hook:on_complete] 이슈 완료: $ISSUE_ID ($ISSUE_TYPE)"

python3 << PYEOF
import json, datetime, sys

try:
    with open('$REGISTRY', 'r') as f:
        registry = json.load(f)
except:
    print("registry.json 읽기 실패")
    sys.exit(1)

issue_id = '$ISSUE_ID'
issue_type = '$ISSUE_TYPE'
result_raw = '''$RESULT'''

now = datetime.datetime.now().isoformat()
new_issues = []
next_num = registry['stats']['total_issues'] + 1

def add_issue(title, itype, priority, assign_to, payload=None):
    global next_num
    # 중복 체크
    for iss in registry['issues']:
        if iss.get('title') == title and iss.get('status') in ('READY', 'IN_PROGRESS'):
            return
    iss = {
        'id': f'ISS-{next_num:03d}',
        'title': title,
        'type': itype,
        'status': 'READY',
        'priority': priority,
        'assign_to': assign_to,
        'depth': target_issue.get('depth', 0) + 1,
        'retry_count': 0,
        'parent_id': issue_id,
        'depends_on': [],
        'created_at': now,
        'payload': payload or {},
        'result': None,
        'spawn_rules': []
    }
    if iss['depth'] <= 3:
        new_issues.append(iss)
        next_num += 1
        print(f"[Plan] {iss['id']} [{priority}] {itype} — {title} → {assign_to}")
    else:
        print(f"[깊이 제한] {title} (depth={iss['depth']})")

# 완료 이슈 찾기
target_issue = None
for issue in registry['issues']:
    if issue['id'] == issue_id:
        target_issue = issue
        break

if not target_issue:
    print(f"[오류] {issue_id} 찾을 수 없음")
    sys.exit(1)

# 이슈 상태 업데이트
target_issue['status'] = 'DONE'
target_issue['completed_at'] = now
registry['stats']['completed'] = registry['stats'].get('completed', 0) + 1

# result 파싱 시도
result = {}
try:
    result = json.loads(result_raw) if result_raw.strip() else {}
except:
    result = {'raw': result_raw}

target_issue['result'] = result

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 결과 분석 → Plan 수립 → 파생 이슈 생성
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

print(f"\n[분석] {issue_type} 결과 기반 Plan 수립:")

if issue_type in ('GENERATE_CODE', 'REFACTOR', 'FIX_BUG', 'QUALITY_IMPROVEMENT', 'BIZ_FIX', 'SCENARIO_FIX', 'DESIGN_FIX'):
    # 코드 변경 완료 → 테스트 + 도메인 분석 + UX 리뷰 병렬
    files_changed = target_issue.get('payload', {}).get('files_changed', [])
    files = target_issue.get('payload', {}).get('files', [])
    all_files = list(set(files_changed + files))

    add_issue(
        f"[Plan:테스트] {issue_id} 변경사항 검증",
        'RUN_TESTS', 'P1', 'test-harness',
        {'files': all_files, 'source_issue': issue_id, 'scope': 'changed'}
    )

    # 도메인 분석 → 비즈니스 검증 → 시나리오 실행 체인
    add_issue(
        f"[Plan:도메인분석] {issue_id} 비즈니스 규칙/시나리오 도출",
        'DOMAIN_ANALYZE', 'P1', 'domain-analyst',
        {'files': all_files, 'source_issue': issue_id}
    )

    # UI 관련 파일이면 UX 리뷰도 추가
    ui_files = [f for f in all_files if any(ext in f for ext in ['.tsx', '.jsx', '.vue', '.html', '.css', '.svelte'])]
    if ui_files:
        add_issue(
            f"[Plan:UX리뷰] {issue_id} UI 변경 검증",
            'UI_REVIEW', 'P1', 'ux-harness',
            {'files': ui_files, 'source_issue': issue_id}
        )

elif issue_type in ('RUN_TESTS', 'RETEST'):
    # 테스트 결과 분석 → 실패면 FIX, 성공이면 SCORE
    test_passed = result.get('passed', True)
    test_total = result.get('total', 0)
    test_failed_count = result.get('failed_count', 0)
    failed_tests = result.get('failed_tests', [])
    coverage = result.get('coverage', None)

    if not test_passed or test_failed_count > 0:
        # 테스트 실패 → FIX_BUG Plan
        add_issue(
            f"[Plan:버그수정] 테스트 실패 {test_failed_count}건 수정",
            'FIX_BUG', 'P0', 'agent-harness',
            {
                'failed_tests': failed_tests,
                'source_issue': issue_id,
                'action': 'fix_failing_tests'
            }
        )
    else:
        # 테스트 전체 통과
        if coverage is not None and coverage < 80:
            # 커버리지 부족 → 커버리지 개선 Plan
            add_issue(
                f"[Plan:커버리지] {coverage}% → 80% 달성",
                'IMPROVE_COVERAGE', 'P2', 'test-harness',
                {'current_coverage': coverage, 'target': 80, 'source_issue': issue_id}
            )

        # 점수 평가 진행
        add_issue(
            f"[Plan:품질평가] {issue_id} 품질 점수 산출",
            'SCORE', 'P1', 'eval-harness',
            {
                'test_result': {
                    'passed': test_passed,
                    'total': test_total,
                    'coverage': coverage
                },
                'source_issue': issue_id
            }
        )

elif issue_type == 'DOMAIN_ANALYZE':
    # 도메인 분석 완료 → biz-validator + scenario-player에 결과 전달
    rules = result.get('rules', [])
    scenarios = result.get('scenarios', [])
    domain = result.get('domain', 'unknown')

    # 정적 검증: biz-validator
    add_issue(
        f"[Plan:비즈니스검증] {domain} 규칙 {len(rules)}개 정적 검증",
        'BIZ_VALIDATE', 'P1', 'biz-validator',
        {
            'rules': rules,
            'scenarios': scenarios,
            'domain': domain,
            'source_issue': issue_id
        }
    )

    # 동적 검증: scenario-player (시나리오 10개 이상이면)
    if len(scenarios) > 0:
        add_issue(
            f"[Plan:시나리오실행] {domain} 시나리오 {len(scenarios)}개 E2E 실행",
            'SCENARIO_PLAY', 'P1', 'scenario-player',
            {
                'scenarios': scenarios,
                'domain': domain,
                'source_issue': issue_id
            }
        )

elif issue_type in ('SCENARIO_PLAY', 'E2E_VERIFY', 'FLOW_REPLAY'):
    # 시나리오 실행 결과 분석
    total = result.get('total_scenarios', 0)
    passed = result.get('passed', 0)
    failed = result.get('failed', 0)
    results_list = result.get('results', [])

    failed_scenarios = [r for r in results_list if r.get('status') == 'FAIL']

    if failed_scenarios:
        for fs in failed_scenarios[:3]:
            fail_detail = fs.get('failed_at', {})
            add_issue(
                f"[Plan:시나리오수정] {fs.get('name', 'unknown')} 실패",
                'SCENARIO_FIX', 'P0', 'agent-harness',
                {
                    'scenario': fs,
                    'error': fail_detail,
                    'source_issue': issue_id,
                    'action': 'fix_scenario_failure'
                }
            )
    elif total > 0 and passed == total:
        print(f"[Plan] 시나리오 전체 통과 ({passed}/{total})")
        registry.setdefault('knowledge', {}).setdefault('success_patterns', []).append({
            'pattern': f'e2e_all_pass_{total}',
            'context': f'{issue_id} all scenarios passed',
            'frequency': 1,
            'discovered_at': now
        })

    if total > 0 and failed / total > 0.5:
        add_issue(
            f"[Plan:근본분석] 시나리오 실패율 {failed}/{total} — 근본 원인 분석",
            'SYSTEMIC_ISSUE', 'P1', 'meta-agent',
            {'pass_rate': passed/total, 'source_issue': issue_id}
        )

elif issue_type in ('BIZ_VALIDATE', 'SCENARIO_GAP'):
    # 비즈니스 로직 검증 결과 분석
    biz_coverage = result.get('coverage_rate', 0)
    gaps = result.get('gaps', [])
    critical_gaps = [g for g in gaps if g.get('level') == 'CRITICAL']
    major_gaps = [g for g in gaps if g.get('level') == 'MAJOR']

    if critical_gaps:
        # CRITICAL 갭 → 즉시 수정
        for gap in critical_gaps:
            add_issue(
                f"[Plan:비즈수정] {gap.get('scenario', 'unknown')}",
                'BIZ_FIX', 'P0', 'agent-harness',
                {
                    'gap': gap,
                    'source_issue': issue_id,
                    'action': 'fix_business_logic'
                }
            )
    elif major_gaps and len(major_gaps) >= 3:
        # MAJOR 갭 다수 → 재검증 필요
        add_issue(
            f"[Plan:시나리오갭] MAJOR 갭 {len(major_gaps)}건 일괄 수정",
            'BIZ_FIX', 'P1', 'agent-harness',
            {
                'gaps': major_gaps,
                'source_issue': issue_id,
                'action': 'fix_major_gaps'
            }
        )
    elif biz_coverage < 70:
        # 커버리지 낮음 → 설계 문제 의심
        add_issue(
            f"[Plan:설계검토] 비즈니스 시나리오 커버리지 {biz_coverage}%",
            'SYSTEMIC_ISSUE', 'P1', 'meta-agent',
            {'biz_coverage': biz_coverage, 'source_issue': issue_id}
        )
    else:
        # 비즈니스 검증 통과 → SCORE로 진행
        add_issue(
            f"[Plan:품질평가] {issue_id} 비즈니스 검증 통과 — 점수 산출",
            'SCORE', 'P1', 'eval-harness',
            {'biz_coverage': biz_coverage, 'source_issue': issue_id}
        )
        if biz_coverage >= 90:
            registry.setdefault('knowledge', {}).setdefault('success_patterns', []).append({
                'pattern': f'biz_coverage_{biz_coverage}',
                'context': f'{issue_id} full scenario coverage',
                'frequency': 1,
                'discovered_at': now
            })

elif issue_type == 'SCORE':
    # 점수 결과 분석
    score = result.get('score', 0)
    prev_score = result.get('prev_score', None)
    breakdown = result.get('breakdown', {})

    if score >= 70:
        # 배포 가능
        add_issue(
            f"[Plan:배포] 품질 {score}점 — 배포 준비",
            'DEPLOY_READY', 'P1', 'cicd-harness',
            {'score': score, 'breakdown': breakdown, 'source_issue': issue_id}
        )
        if score >= 90:
            # 고품질 → 성공 패턴 학습
            registry.setdefault('knowledge', {}).setdefault('success_patterns', []).append({
                'pattern': f'score_{score}',
                'context': f'{issue_id} chain',
                'frequency': 1,
                'discovered_at': now
            })
            print(f"[학습] 고품질 패턴 기록 (score={score})")
    else:
        # 품질 부족 → 개선 Plan
        worst = min(breakdown.items(), key=lambda x: x[1]) if breakdown else ('unknown', 0)
        add_issue(
            f"[Plan:품질개선] 점수 {score}점 — {worst[0]} 집중 개선",
            'QUALITY_IMPROVEMENT', 'P0', 'agent-harness',
            {
                'score': score,
                'worst_area': worst[0] if breakdown else None,
                'breakdown': breakdown,
                'source_issue': issue_id,
                'action': 'improve_quality'
            }
        )

    # 회귀 감지
    if prev_score is not None and score < prev_score - 10:
        add_issue(
            f"[Plan:회귀분석] 점수 {prev_score}→{score} (-{prev_score - score})",
            'REGRESSION_CHECK', 'P0', 'eval-harness',
            {'prev_score': prev_score, 'current_score': score, 'source_issue': issue_id}
        )

elif issue_type == 'DEPLOY_READY':
    # 배포 완료 → 파이프라인 종료, 학습 기록
    print(f"[Plan:완료] 배포 성공 — 파이프라인 사이클 종료")
    registry.setdefault('knowledge', {}).setdefault('success_patterns', []).append({
        'pattern': 'full_pipeline_success',
        'context': f'{issue_id} deploy completed',
        'frequency': 1,
        'discovered_at': now
    })

elif issue_type in ('UI_REVIEW', 'UX_FIX'):
    # UX 리뷰 결과 분석
    ux_passed = result.get('passed', True)
    ux_issues = result.get('issues', [])

    if not ux_passed and ux_issues:
        add_issue(
            f"[Plan:UX수정] UX 이슈 {len(ux_issues)}건 수정",
            'UX_FIX', 'P1', 'agent-harness',
            {'ux_issues': ux_issues, 'source_issue': issue_id, 'action': 'fix_ux'}
        )
    else:
        # UX 규칙 통과 → 디자인 감각 리뷰 진행
        ui_files = target_issue.get('payload', {}).get('files', [])
        add_issue(
            f"[Plan:디자인리뷰] {issue_id} 시각적 완성도 검증",
            'DESIGN_REVIEW', 'P1', 'design-critic',
            {'files': ui_files, 'source_issue': issue_id}
        )

elif issue_type in ('DESIGN_REVIEW', 'VISUAL_AUDIT'):
    # 디자인 감각 리뷰 결과 분석
    total_score = result.get('total_score', 0)
    critical_issues = result.get('critical_issues', [])
    ai_slop = result.get('ai_slop_detected', False)

    if ai_slop:
        add_issue(
            f"[Plan:AI슬롭제거] AI 생성 느낌 제거",
            'DESIGN_FIX', 'P0', 'agent-harness',
            {'reason': 'ai_slop', 'source_issue': issue_id, 'action': 'fix_ai_slop'}
        )
    elif total_score < 42 or critical_issues:
        for ci in critical_issues[:3]:
            add_issue(
                f"[Plan:디자인수정] {ci.get('dimension', '')} — {ci.get('problem', '')[:40]}",
                'DESIGN_FIX', 'P1', 'agent-harness',
                {
                    'design_issue': ci,
                    'source_issue': issue_id,
                    'action': 'fix_design'
                }
            )
    else:
        # 디자인 통과 → SCORE로 진행
        print(f"[Plan] 디자인 리뷰 통과 ({total_score}/70)")
        if total_score >= 63:
            registry.setdefault('knowledge', {}).setdefault('success_patterns', []).append({
                'pattern': f'design_score_{total_score}',
                'context': f'{issue_id} excellent design',
                'frequency': 1,
                'discovered_at': now
            })

elif issue_type in ('SYSTEMIC_ISSUE', 'PATTERN_ANALYSIS'):
    # Meta Agent 분석 결과 → 구체적 실행 이슈 생성
    recommendations = result.get('recommendations', [])
    for rec in recommendations[:3]:
        rec_type = rec.get('type', 'REFACTOR')
        rec_title = rec.get('title', f'[Meta] {issue_id} 권고 실행')
        rec_assign = rec.get('assign_to', 'agent-harness')
        add_issue(rec_title, rec_type, 'P1', rec_assign, {
            'source_issue': issue_id,
            'recommendation': rec
        })

elif issue_type == 'ROLLBACK':
    # 롤백 후 → 원인 분석 Plan
    add_issue(
        f"[Plan:원인분석] 롤백 원인 분석 및 재수정",
        'FIX_BUG', 'P0', 'agent-harness',
        {'source_issue': issue_id, 'action': 'fix_after_rollback'}
    )

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Plan 요약 출력
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

if new_issues:
    print(f"\n📋 Plan 수립 완료: {len(new_issues)}개 이슈 생성")
    for ni in new_issues:
        registry['issues'].append(ni)
        registry['stats']['total_issues'] = registry['stats'].get('total_issues', 0) + 1
else:
    print(f"\n✅ 파이프라인 사이클 완료 — 추가 이슈 없음")

# Hook 이력 기록
registry.setdefault('hooks', {}).setdefault('on_complete', []).append({
    'issue_id': issue_id,
    'issue_type': issue_type,
    'plan_created': len(new_issues),
    'timestamp': now
})

with open('$REGISTRY', 'w') as f:
    json.dump(registry, f, indent=2, ensure_ascii=False)

print(f"[on_complete] 처리 완료")
PYEOF

# Plan 생성 후 자동 디스패치
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "[on_complete] → dispatch-ready 실행"
bash "$SCRIPT_DIR/dispatch-ready.sh" "$REGISTRY"
