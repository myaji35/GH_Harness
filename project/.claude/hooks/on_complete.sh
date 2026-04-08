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

if issue_type == 'FEATURE_PLAN':
    # 기획 완료 → CEO + Eng 2중 검토 병렬 진행 (USER_STORY 직행 X)
    feature_name = result.get('feature_name', issue_id)
    add_issue(
        f"[Plan:CEO검토] {feature_name} 전략 검토",
        'PLAN_CEO_REVIEW', 'P1', 'plan-ceo-reviewer',
        {'source_issue': issue_id, 'source_plan': result, 'feature': feature_name}
    )
    add_issue(
        f"[Plan:Eng검토] {feature_name} 실행가능성 검토",
        'PLAN_ENG_REVIEW', 'P1', 'plan-eng-reviewer',
        {'source_issue': issue_id, 'source_plan': result, 'feature': feature_name}
    )

elif issue_type in ('PLAN_CEO_REVIEW', 'PLAN_ENG_REVIEW'):
    # 검토 결과 분석 → REJECT면 재기획, AUGMENT/SCOPE_EXPANSION이면 보강 후 USER_STORY, APPROVE/HOLD면 USER_STORY 직행
    verdict = result.get('verdict', 'APPROVE')
    passed = result.get('passed', True)
    source_plan = target_issue.get('payload', {}).get('source_plan', {})
    feature = target_issue.get('payload', {}).get('feature', issue_id)

    if verdict == 'REJECT' or not passed:
        # 재기획 트리거
        add_issue(
            f"[Plan:재기획] {feature} — {verdict} 사유로 재작성",
            'FEATURE_PLAN', 'P0', 'product-manager',
            {'source_issue': issue_id, 'rejection_reason': result, 'previous_plan': source_plan}
        )
    else:
        # 통과 → 양쪽 검토가 모두 끝났는지 확인
        parent_plan_id = target_issue.get('payload', {}).get('source_issue')
        sibling_done = False
        other_type = 'PLAN_ENG_REVIEW' if issue_type == 'PLAN_CEO_REVIEW' else 'PLAN_CEO_REVIEW'
        for iss in registry['issues']:
            if (iss.get('payload', {}).get('source_issue') == parent_plan_id
                and iss.get('type') == other_type
                and iss.get('status') == 'DONE'):
                sibling_done = True
                break

        if sibling_done:
            # 양쪽 검토 통과 → 보강 항목 + 원본 스토리로 USER_STORY 생성
            stories = source_plan.get('stories', [])
            extra_stories = result.get('suggested_stories', []) + result.get('augmentations', [])
            for story in stories:
                s_type = story.get('type', 'USER_STORY')
                s_assign = story.get('assign_to', 'agent-harness')
                s_priority = story.get('priority', 'P1')
                s_title = story.get('title', 'User Story')
                add_issue(
                    f"[Story] {s_title}",
                    s_type, s_priority, s_assign,
                    {
                        'acceptance_criteria': story.get('acceptance_criteria', []),
                        'source_issue': parent_plan_id,
                        'feature': source_plan.get('feature_name', feature),
                        'reviewed': True
                    }
                )
            for ex in extra_stories[:2]:  # 보강은 최대 2개만
                add_issue(
                    f"[Story:보강] {ex.get('title', ex.get('add', 'augmentation'))}",
                    'USER_STORY', 'P2', 'agent-harness',
                    {'source_issue': parent_plan_id, 'augmentation': ex}
                )
        else:
            print(f"[Plan] {issue_type} 통과 — 형제 검토 대기 중")

elif issue_type == 'USER_STORY':
    # 사용자 스토리 완료 → UI 필요 여부에 따라 분기
    needs_ui = result.get('needs_ui', False)
    if needs_ui:
        add_issue(
            f"[Plan:UX설계] {result.get('title', issue_id)} UI 설계",
            'UX_DESIGN', 'P1', 'ux-harness',
            {'source_issue': issue_id, 'acceptance_criteria': result.get('acceptance_criteria', [])}
        )
    else:
        add_issue(
            f"[Plan:구현] {result.get('title', issue_id)}",
            'GENERATE_CODE', 'P1', 'agent-harness',
            {'source_issue': issue_id, 'acceptance_criteria': result.get('acceptance_criteria', [])}
        )

elif issue_type == 'UX_DESIGN':
    # UX 설계 완료 → 코드 생성
    add_issue(
        f"[Plan:구현] {issue_id} UX 설계 기반 구현",
        'GENERATE_CODE', 'P1', 'agent-harness',
        {
            'source_issue': issue_id,
            'ux_design': result.get('components', []),
            'layout': result.get('page_layout', ''),
            'action': 'implement_from_ux_design'
        }
    )

elif issue_type == 'UX_FLOW':
    # 플로우 설계 완료 → UX_DESIGN으로 컴포넌트화
    add_issue(
        f"[Plan:UX설계] {issue_id} 플로우 기반 컴포넌트 설계",
        'UX_DESIGN', 'P1', 'ux-harness',
        {
            'source_issue': issue_id,
            'flow': result.get('steps', []),
            'edge_cases': result.get('edge_cases', [])
        }
    )

elif issue_type in ('GENERATE_CODE', 'REFACTOR', 'FIX_BUG', 'QUALITY_IMPROVEMENT', 'BIZ_FIX', 'SCENARIO_FIX', 'DESIGN_FIX'):
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

    # UI 관련 파일이면 UX 리뷰 + Brand Guard + Browser QA 추가
    ui_files = [f for f in all_files if any(ext in f for ext in ['.tsx', '.jsx', '.vue', '.html', '.css', '.svelte'])]
    if ui_files:
        add_issue(
            f"[Plan:UX리뷰] {issue_id} UI 변경 검증",
            'UI_REVIEW', 'P1', 'ux-harness',
            {'files': ui_files, 'source_issue': issue_id}
        )
        # Brand Guard — 프로젝트 아젠다 표현 + Action Clarity 검증
        add_issue(
            f"[Plan:브랜드검증] {issue_id} 아젠다 표현 + Action Clarity",
            'BRAND_GUARD', 'P1', 'brand-guardian',
            {'files': ui_files, 'source_issue': issue_id}
        )
        # Browser QA — gstack browse로 실제 콘솔 에러 캡처
        add_issue(
            f"[Plan:브라우저QA] {issue_id} 콘솔 에러 + 스크린샷 검증",
            'BROWSER_QA', 'P1', 'agent-harness',
            {'files': ui_files, 'source_issue': issue_id, 'action': 'run_browse_qa'}
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
        # 발산 엔진은 DEPLOY_READY에서 단일 발화 (비용 절감) — RUN_TESTS는 누적만
        registry.setdefault('pending_opportunity_signals', []).append({
            'source_issue': issue_id,
            'source_type': 'RUN_TESTS',
            'result': {'passed': test_passed, 'total': test_total, 'coverage': coverage}
        })

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
        # 발산 엔진은 DEPLOY_READY에서 단일 발화 — BIZ_VALIDATE는 누적만
        registry.setdefault('pending_opportunity_signals', []).append({
            'source_issue': issue_id,
            'source_type': 'BIZ_VALIDATE',
            'result': {'biz_coverage': biz_coverage}
        })
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
    # 발산 엔진 — 배포 완료 시 누적된 모든 통과 신호를 한 번에 분석 (단일 발화)
    pending = registry.get('pending_opportunity_signals', [])
    add_issue(
        f"[Plan:기회발굴] {issue_id} 배포 완료 — 누적 신호 {len(pending)}개 종합 분석",
        'OPPORTUNITY_SCOUT', 'P2', 'opportunity-scout',
        {
            'source_issue': issue_id,
            'source_type': 'DEPLOY_READY',
            'source_result': {'deployed': True},
            'accumulated_signals': pending  # RUN_TESTS + BIZ_VALIDATE 통과 신호 누적
        }
    )
    # 누적 시그널 초기화
    registry['pending_opportunity_signals'] = []

elif issue_type == 'OPPORTUNITY_SCOUT':
    # 기회 발굴 결과 → OPPORTUNITY 이슈들을 product-manager로 위임
    opportunities = result.get('opportunities', [])
    if not opportunities:
        # 강제 산출 위반 → 재시도
        add_issue(
            f"[Plan:재발산] {issue_id} 기회 0개 — 발산 재시도 필수",
            'OPPORTUNITY_SCOUT', 'P2', 'opportunity-scout',
            {
                'source_issue': target_issue.get('payload', {}).get('source_issue'),
                'source_type': target_issue.get('payload', {}).get('source_type'),
                'retry': True
            }
        )
    else:
        for opp in opportunities[:3]:
            add_issue(
                f"[기회] {opp.get('title', 'opportunity')}",
                'FEATURE_PLAN', opp.get('priority', 'P2'), 'product-manager',
                {
                    'opportunity': opp,
                    'source_issue': issue_id,
                    'lens': opp.get('lens'),
                    'success_signal': opp.get('success_signal'),
                    'auto_discovered': True
                }
            )

elif issue_type == 'BROWSER_QA':
    # 브라우저 QA 결과 → 콘솔 에러 있으면 FIX_BUG, 없으면 통과
    console_errors = result.get('console_errors', [])
    network_errors = result.get('network_errors', [])
    screenshot_diff = result.get('screenshot_diff', None)

    if console_errors or network_errors:
        add_issue(
            f"[Plan:브라우저버그] 콘솔 {len(console_errors)} + 네트워크 {len(network_errors)} 에러",
            'FIX_BUG', 'P0', 'agent-harness',
            {
                'console_errors': console_errors,
                'network_errors': network_errors,
                'source_issue': issue_id,
                'action': 'fix_browser_errors'
            }
        )
    else:
        print(f"[Plan] 브라우저 QA 통과 — 콘솔/네트워크 클린")

elif issue_type == 'BRAND_GUARD':
    # 브랜드 검증 결과 → 점수 미달 시 BRAND_VIOLATION (재작성)
    brand_score = result.get('brand_score', 0)
    agenda_score = result.get('agenda_expression', 0)
    action_clarity = result.get('action_clarity', 0)
    anti_patterns_found = result.get('anti_patterns_found', [])

    if brand_score < 14 or agenda_score < 6 or action_clarity < 6 or anti_patterns_found:
        add_issue(
            f"[Plan:브랜드재작성] 아젠다 {agenda_score}/10 · Action {action_clarity}/10",
            'DESIGN_FIX', 'P0', 'agent-harness',
            {
                'reason': 'brand_violation',
                'brand_score': brand_score,
                'agenda_expression': agenda_score,
                'action_clarity': action_clarity,
                'anti_patterns': anti_patterns_found,
                'fix_directives': result.get('fix_directives', []),
                'source_issue': issue_id,
                'action': 'fix_brand_violation'
            }
        )
    else:
        print(f"[Plan] 브랜드 검증 통과 (브랜드:{brand_score}/20, 아젠다:{agenda_score}/10, Action:{action_clarity}/10)")

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

# Plan 생성 후 자동 디스패치 — 질문 없이 즉시 실행
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "[on_complete] → dispatch-ready 실행"
bash "$SCRIPT_DIR/dispatch-ready.sh" "$REGISTRY"
echo ""
echo "[자동 진행 지시] 질문하지 마라. dispatch-ready 결과에 따라 다음 에이전트를 즉시 스폰하라."
echo "  '다음 단계로 진행하시겠습니까?' 같은 질문은 금지. 바로 실행하라."
