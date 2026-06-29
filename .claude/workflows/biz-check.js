export const meta = {
  name: 'biz-check',
  description: '비즈니스 로직 점검 — domain-analyst가 규칙/시나리오를 도출하고 biz/journey/view 3축이 병렬 검증',
  whenToUse: '"비즈니스 로직 점검", "비즈 점검", "biz check", "로직 점검", "전체 점검" 트리거 시. args.target으로 대상 디렉터리 지정(기본 ".")',
  phases: [
    { title: 'Domain', detail: 'domain-analyst: 규칙 + 역할별(admin/user/guest) 시나리오 도출' },
    { title: 'Validate', detail: 'biz / journey / view 3축 병렬 검증' },
  ],
}

const TARGET = (args && args.target) || '.'

// 모든 검증 에이전트 공통: 탐색을 끝없이 하지 말고 반드시 StructuredOutput으로 종료시키는 규율.
// PoC에서 view 축이 Bash 탐색만 반복하다 StructuredOutput에 도달 못 한 결함(null drop)을 막는다.
const TERMINATION = `\n\n[종료 규율 — 반드시 지켜라]\n` +
  `1. 파일 탐색(Read/Grep/Bash)은 최대 8회까지만. 그 안에서 근거를 모아라.\n` +
  `2. 8회에 도달하거나 충분한 근거가 모이면 즉시 StructuredOutput을 호출해 결과를 반환하라.\n` +
  `3. 너의 StructuredOutput 호출이 곧 최종 반환값이다. 호출하지 않으면 이 축의 결과는 누락된다.\n` +
  `4. findings는 "[심각도][규칙ID 또는 영역] 구체적 갭 설명" 형식으로 작성.`

const DOMAIN_SCHEMA = {
  type: 'object',
  required: ['rules', 'scenarios'],
  properties: {
    rules: { type: 'array', items: { type: 'string' } },
    role_breakdown: {
      type: 'object',
      properties: { admin: { type: 'integer' }, user: { type: 'integer' }, guest: { type: 'integer' } },
    },
    scenarios: { type: 'array', items: { type: 'string' } },
  },
}

const FINDINGS_SCHEMA = {
  type: 'object',
  required: ['axis', 'critical', 'high', 'medium', 'findings'],
  properties: {
    axis: { type: 'string', description: 'biz | journey | view 중 자신의 축 이름을 그대로 기입' },
    critical: { type: 'integer' },
    high: { type: 'integer' },
    medium: { type: 'integer' },
    score: { type: 'integer', description: 'journey 축만 0-40 합산 점수. biz/view는 -1' },
    findings: { type: 'array', items: { type: 'string' } },
  },
}

phase('Domain')
log(`대상: ${TARGET} — domain-analyst 모드로 도메인 규칙/시나리오 도출`)
const domain = await agent(
  `너는 domain-analyst(opus) 역할이다. 대상 디렉터리 "${TARGET}"의 코드/문서/registry를 분석해 ` +
  `이 프로젝트의 핵심 비즈니스 규칙과 역할별(admin/user/guest) 시나리오를 도출하라. ` +
  `실제 파일을 읽고 근거 기반으로 도출할 것. 규칙은 "BR-NNN [유형, 우선순위, roles:x] 내용" 형식, ` +
  `시나리오는 "역할: 행동→기대결과" 형식.` + TERMINATION,
  { label: 'domain-analyst', phase: 'Domain', schema: DOMAIN_SCHEMA, agentType: 'check-harness' }
)

const ctx = `[도메인 규칙 ${domain.rules.length}개]\n${domain.rules.join('\n')}\n\n` +
  `[시나리오 ${domain.scenarios.length}개]\n${domain.scenarios.join('\n')}`

phase('Validate')
log('도메인 결과를 biz/journey/view 3축에 전달 — 병렬 검증')

// view 축은 탐색량이 많아 effort:high로 상향(PoC에서 종료 미달의 주원인).
const AXES = [
  {
    key: 'biz',
    effort: 'medium',
    prompt: `너는 biz-validator(sonnet)다. axis="biz". 아래 도메인 규칙/시나리오 대비 "${TARGET}" 코드의 ` +
      `비즈니스 로직 갭을 정적 검증하라. 각 규칙(BR-NNN)이 실제 코드/hook에서 집행(enforce)되는지 확인하고, ` +
      `미집행·시나리오 미커버·엣지케이스 누락을 critical/high/medium으로 분류하라.\n\n${ctx}`,
  },
  {
    key: 'journey',
    effort: 'medium',
    prompt: `너는 journey-validator(sonnet)다. axis="journey". "${TARGET}"의 사용자 여정을 검증하라. ` +
      `역할 커버리지 / 인팩트(다음 행동 명확성) / 온보딩(빈 상태·첫 사용) / 행동유도(CTA) 4개 축을 각 10점씩 ` +
      `채점해 score(0-40)에 합산하라.\n\n${ctx}`,
  },
  {
    key: 'view',
    effort: 'high',
    prompt: `너는 code-quality(sonnet)의 VIEW_AUDIT 모드다. axis="view". "${TARGET}"의 뷰/라우트/구조를 감사하라. ` +
      `레이아웃 일관성, 라우트-뷰 매핑 누락, 자산 누락, 파셜 중복을 critical/high/medium으로 분류하라. ` +
      `(이 프로젝트에 UI 뷰가 없으면 운영 산출물 구조 — hook/agent/registry 일관성 — 으로 대체 감사하라.)\n\n${ctx}`,
  },
]

const results = await parallel(
  AXES.map((a) => () =>
    agent(a.prompt + TERMINATION, {
      label: `check:${a.key}`,
      phase: 'Validate',
      schema: FINDINGS_SCHEMA,
      agentType: 'check-harness',
      effort: a.effort,
    })
      .then((r) => (r ? { ...r, key: a.key } : { key: a.key, missing: true }))
  )
)

// silent drop 금지(CLAUDE.md "no silent caps") — 누락 축을 명시적으로 보고.
const ok = results.filter((r) => r && !r.missing)
const missing = results.filter((r) => r && r.missing).map((r) => r.key)

return {
  target: TARGET,
  domain: {
    rule_count: domain.rules.length,
    roles: domain.role_breakdown || {},
    scenario_count: domain.scenarios.length,
  },
  axes: ok.map((r) => ({
    key: r.key,
    critical: r.critical,
    high: r.high,
    medium: r.medium,
    score: r.score,
    top_findings: (r.findings || []).slice(0, 5),
  })),
  missing_axes: missing, // 비어있어야 정상. 값이 있으면 해당 축 재실행 필요.
}
