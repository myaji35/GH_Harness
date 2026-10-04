import type { Register, EngineInterface, ToolCallInput } from 'claude-code'

type Verdict = 'allow' | 'deny' | 'warn'
type Decision = { verdict: Verdict; reason: string; hook: string; message?: string; rewrite?: string }
const allow = (hook: string, reason = 'no matching rule'): Decision => ({ verdict: 'allow', reason, hook })
const deny = (hook: string, reason: string, message: string): Decision => ({ verdict: 'deny', reason, message, hook })
const warn = (hook: string, reason: string): Decision => ({ verdict: 'warn', reason, hook })
const HOME_LOG = '/.claude/harness-core/logs/mod-guard-shadow.jsonl'
let logQueue: Promise<void> = Promise.resolve()
const commandPatterns = [
  ['rm[\\s]+-[rRf]{1,3}[\\s]+/([\\s]|$)', /rm\s+-[rRf]{1,3}\s+\/(\s|$)/],
  ['rm[\\s]+-[rRf]{1,3}[\\s]+~([\\s]|$|/)', /rm\s+-[rRf]{1,3}\s+~(\s|$|\/)/],
  ['rm[\\s]+-[rRf]{1,3}[\\s]+\\*', /rm\s+-[rRf]{1,3}\s+\*/],
  [':[\\s]*\\(\\)[\\s]*\\{', /:\s*\(\)\s*\{/],
  ['mkfs\\.', /mkfs\./], ['dd[[:space:]]+.*of=/dev/', /dd\s+.*of=\/dev\//],
  ['chmod[[:space:]]+-R[[:space:]]+777[[:space:]]+/', /chmod\s+-R\s+777\s+\//],
  ['curl[[:space:]].*\\|[[:space:]]*(sh|bash|zsh)([[:space:]]|$)', /curl\s+.*\|\s*(sh|bash|zsh)(\s|$)/],
  ['wget[[:space:]].*\\|[[:space:]]*(sh|bash|zsh)([[:space:]]|$)', /wget\s+.*\|\s*(sh|bash|zsh)(\s|$)/],
  ['sudo[[:space:]]+rm', /sudo\s+rm/],
] as const
const warnPatterns = [
  [/git\s+push\s+(-f|--force)/, 'EXTERNAL', 'git push -f 히스토리 덮어쓰기'],
  [/git\s+reset\s+--hard/, 'EXTERNAL', '로컬 변경 소실 위험'],
  [/git\s+clean\s+-f/, 'EXTERNAL', '추적되지 않은 파일 삭제'],
  [/DROP\s+TABLE/, 'SECURITY', 'DB 테이블 파괴'],
  [/DROP\s+DATABASE/, 'SECURITY', 'DB 삭제'],
  [/TRUNCATE\s+/, 'SECURITY', '데이터 전량 삭제'],
  [/kubectl\s+delete/, 'EXTERNAL', '쿠버네티스 리소스 삭제'],
  [/kamal\s+(app\s+)?remove/, 'EXTERNAL', '배포 삭제'],
  [/npm\s+publish/, 'EXTERNAL', 'npm 레지스트리 배포'],
  [/pip\s+upload/, 'EXTERNAL', 'pip 레지스트리 배포'],
] as const
const filenameSecret = /(^|\/)\.deploy_credentials$|(^|\/)\.env$|(^|\/)\.env\.(production|prod|local|staging)$|(^|\/)SECURITY_CREDENTIALS\.md$|(^|\/)(config\/)?master\.key$|(^|\/)credentials\.json$|\.pem$|\.p12$|(^|\/)id_(rsa|ed25519)$|(^|\/)service-account.*\.json$|\.gcp-key\.json$/
const secret = /AIza[0-9A-Za-z_-]{35}|sk-ant-[A-Za-z0-9_-]{20,}|sk-[A-Za-z0-9]{20,}|gh[pousr]_[A-Za-z0-9]{30,}|AKIA[0-9A-Z]{16}|EAA[A-Za-z0-9]{50,}|(api[_-]?key|secret|token|password|passwd|pwd|ssh_pass[a-z_]*)["' ]*[=:]\s*["'][^\s"']{8,}|sshpass\s+-p\s*["'][^"']{6,}["']|(로그인|계정|비밀번호|접속)[^\n]{0,12}[`"'][^`"' ]{3,}[`"']\s*\/\s*[`"'][^`"' ]{6,}[`"']/gi
const placeholder = /your_|<.*>|\$\{|\$\(|\$[a-z_]|xxxx|example|placeholder|changeme|redacted|_here/i
function hits(text: string): string[] {
  return [...text.matchAll(secret)].map(m => m[0]).filter(s => /^EAA[A-Za-z0-9]{50,}$/i.test(s) || !placeholder.test(s))
}
const limit = (s: string) => s.slice(0, 200)
async function run($: EngineInterface, argv: string[], timeoutMs = 1200) {
  return $.process.run(argv, { timeoutMs })
}
export async function sandbox($: EngineInterface, command: string): Promise<Decision> {
  const bypass = await $.env.get('HARNESS_SANDBOX_BYPASS')
  if (bypass === '2') return allow('sandbox', 'bypass=2')
  for (const [label, pattern] of commandPatterns) if (pattern.test(command)) {
    if (bypass === '1') return warn('sandbox', `bypass=1: ${label}`)
    return deny('sandbox', label, `🛑 [Sandbox BLOCK] 명령 거부\n    패턴: ${label}\n    명령: ${limit(command)}\n    정책: GH_Harness/global/policy/SANDBOX_POLICY.md\n    우회: 필요 시 HARNESS_SANDBOX_BYPASS=1 후 재실행 (위험)`)
  }
  for (const [pattern, category, reason] of warnPatterns) if (pattern.test(command)) {
    const confirm = await $.fs.stat('/Users/gangseungsig/.claude/harness-core/hooks/request-user-confirm.sh').catch(() => undefined)
    if (confirm) return deny('sandbox', `${category}: ${reason}; T2 confirmation required`, `⚠️ [Sandbox WARN] ${category} — ${reason}\n    명령: ${limit(command)}\n    → T2 컨펌 요청 (request-user-confirm.sh)`)
    return warn('sandbox', `${category}: ${reason}; T2 hook absent`)
  }
  return allow('sandbox')
}
export async function freeze($: EngineInterface, filePath: string): Promise<Decision> {
  const cwd = await $.session.cwd()
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(cwd))
  const key = [...new Uint8Array(digest)].map(b => b.toString(16).padStart(2, '0')).join('').slice(0, 12)
  const freezeFile = `/tmp/harness-freeze-${key}.env`
  if (!(await $.fs.exists(freezeFile))) return allow('freeze', 'no freeze file')
  const contents = await $.fs.read(freezeFile)
  const dir = contents.match(/^\s*(?:export\s+)?FREEZE_DIR=(.*)$/m)?.[1]?.trim().replace(/^['"]|['"]$/g, '') || ''
  const issue = contents.match(/^\s*(?:export\s+)?FREEZE_ISSUE=(.*)$/m)?.[1]?.trim().replace(/^['"]|['"]$/g, '') || ''
  if (!dir || !filePath) return allow('freeze', 'empty freeze dir or file path')
  if (issue && await $.fs.exists('.claude/issue-db/registry.json')) {
    try {
      const registry = JSON.parse(await $.fs.read('.claude/issue-db/registry.json')) as { issues?: {id?: string; status?: string}[] }
      const status = registry.issues?.find(i => i.id === issue)?.status
      if (status !== 'IN_PROGRESS' && status !== 'BACKGROUND_RUNNING') return allow('freeze', 'stale freeze')
    } catch { return allow('freeze', 'registry unreadable, shell hook treats as stale') }
  }
  const absolute = dir.startsWith('/') ? dir : `${cwd}/${dir}`
  const resolved = (await $.fs.stat(absolute, { resolve: true }).catch(() => undefined))?.realPath || absolute
  if (filePath.startsWith(`${resolved}/`) || filePath.startsWith(`${dir}/`)) return allow('freeze', 'within freeze directory')
  return deny('freeze', 'outside freeze directory', `🔒 [Harness Freeze] 편집 차단: ${filePath}\n    허용 디렉터리: ${resolved}\n    해제: rm ${freezeFile}`)
}
export async function secretGuard($: EngineInterface, command: string): Promise<Decision> {
  if (!command.includes('git commit') && !command.includes('git push')) return allow('secret', 'not commit/push')
  const names = await run($, ['git', 'diff', '--cached', '--name-only'])
  const blocked = names.stdout.split('\n').filter(n => filenameSecret.test(n) && !/example|template|sample|\.enc$/i.test(n))
  if (blocked.length) return deny('secret', 'staged secret filename', `🚨 [Harness Secret-Guard] 커밋 차단: 시크릿 파일이 staged 되었습니다\n${blocked.map(x => `      - ${x}`).join('\n')}\n\n    조치: git rm --cached <파일> 로 추적 해제 후 .gitignore에 등록하세요.\n    근거: 2026-07-15 .deploy_credentials 공개 유출 (Vultr root 비번 5개월 노출).`)
  const diff = await run($, ['git', 'diff', '--cached', '--', '.', ':(exclude)tests/*', ':(exclude)test/*', ':(exclude)spec/*', ':(exclude)*_test.sh', ':(exclude)*_test.rb', ':(exclude)*_spec.rb', ':(exclude)*.test.ts', ':(exclude)*.spec.ts'])
  const added = diff.stdout.split('\n').filter(line => line.startsWith('+') && !line.startsWith('+++')).join('\n')
  if (hits(added).length) return deny('secret', 'staged secret value', '🚨 [Harness Secret-Guard] 커밋 차단: staged 변경에 시크릿(API 키) 평문 감지\n    조치: 키를 환경변수/kamal secrets로 옮기고 .gitignore 처리 후 재커밋하세요.')
  return allow('secret', 'no staged secret')
}
export async function secretPost($: EngineInterface, filePath: string): Promise<Decision> {
  if (!filePath || !(await $.fs.exists(filePath))) return allow('secret-post', 'file absent')
  try {
    if (hits(await $.fs.read(filePath)).length) return warn('secret-post', `⚠️  [Harness Secret-Guard] ${filePath} 에 시크릿(API 키) 평문 감지 → 환경변수로 옮기세요. 커밋 시 secret-guard가 차단합니다.`)
  } catch { /* shell file read failure is nonblocking */ }
  return allow('secret-post', 'no secret in edited file')
}
export async function rtk($: EngineInterface, command: string): Promise<Decision> {
  if (!/^(?:ls|cat|grep|rg|git|find|head|tail|wc|sed|awk|du|df|ps|docker|kubectl)(?:\s|$)/.test(command.trim())) return allow('rtk', 'not an RTK target command')
  try {
    const input = JSON.stringify({ tool_name: 'Bash', tool_input: { command } })
    const result = await $.process.run(['rtk', 'hook', 'claude'], { stdin: input, timeoutMs: 1000 })
    if (result.exitCode !== 0) return allow('rtk', 'rtk failed; shell hook exits without rewrite')
    const rewrite = (JSON.parse(result.stdout) as {hookSpecificOutput?: {updatedInput?: {command?: string}}}).hookSpecificOutput?.updatedInput?.command
    return rewrite ? { ...warn('rtk', 'RTK auto-rewrite'), rewrite } : allow('rtk', 'no rewrite')
  } catch { return allow('rtk', 'rtk absent or invalid output') }
}
export async function health($: EngineInterface, command: string, mode: 'shadow' | 'enforce'): Promise<Decision> {
  if (!command.includes('git commit') || !(await $.fs.exists('.claude/issue-db/registry.json'))) return allow('health', 'no commit or registry')
  let score = 100
  const checks: Record<string, { penalty: number; detail: string }> = {}
  const skipped: string[] = []
  let ran = 0
  let truncated = false
  const started = await $.clock.now()
  const check = async (name: string, argv: string[], penaltyOf: (output: string, exit: number) => [number, string]) => {
    const remaining = 5000 - ((await $.clock.now()) - started)
    if (remaining < 700) { skipped.push(`${name} (시간 예산 초과)`); truncated = true; return }
    try {
      const result = await $.process.run(argv, { timeoutMs: Math.min(1200, remaining - 150) })
      const [penalty, detail] = penaltyOf(result.stdout + result.stderr, result.exitCode)
      checks[name] = { penalty, detail }
      score -= penalty
      ran++
    } catch { skipped.push(name) }
  }
  if (await $.fs.exists('package.json')) {
    try {
      const pkg = JSON.parse(await $.fs.read('package.json')) as { scripts?: Record<string, string> }
      const script = pkg.scripts?.typecheck ? 'typecheck' : pkg.scripts?.['type-check'] ? 'type-check' : ''
      if (script) await check('typecheck', ['npm', 'run', script], (_out, exit) => [exit === 0 ? 0 : 30, `exit=${exit}`])
      else skipped.push('typecheck')
    } catch { skipped.push('typecheck') }
  } else skipped.push('typecheck')
  if (await $.fs.exists('tsconfig.json')) {
    await check('tsc', ['npx', '--no-install', 'tsc', '--noEmit'], (output, exit) => {
      const errors = Math.min(30, (output.match(/error TS[0-9]+:/gi) || []).length)
      return [errors, `errors=${errors},exit=${exit}`]
    })
  } else skipped.push('tsc')
  // A missing executable is skipped by process.run, like command -v in the shell hook.
  const lintBefore = ran
  await check('ruff', ['ruff', 'check', '.', '--output-format', 'concise'], (output, exit) => {
    const warnings = (output.match(/:[0-9]+:[0-9]+:/g) || []).length
    return [Math.min(20, Math.floor(warnings / 5) * 2), `warnings=${warnings},exit=${exit}`]
  })
  if (ran === lintBefore) await check('eslint', ['eslint', '.'], (output, exit) => {
    const warnings = (output.match(/warning|problems? \(/gi) || []).length
    return [Math.min(20, Math.floor(warnings / 5) * 2), `warnings=${warnings},exit=${exit}`]
  })
  if (await $.fs.exists('Gemfile')) await check('rubocop', ['bundle', 'exec', 'rubocop', '--format', 'simple'], (output, exit) => {
    const offenses = Number([...output.matchAll(/([0-9]+) offenses? detected/g)].at(-1)?.[1] || 0)
    return [Math.min(20, Math.floor(offenses / 5) * 2), `offenses=${offenses},exit=${exit}`]
  })
  else skipped.push('rubocop')
  await check('todo_markers', ['rg', '-n', '--hidden', '--glob', '!.git/**', '--glob', '!node_modules/**', '--glob', '!.venv/**', '--glob', '!venv/**', '--glob', '!vendor/**', '--glob', '!dist/**', '--glob', '!build/**', '--glob', '!.next/**', '--glob', '!target/**', '--glob', '!__pycache__/**', '--glob', '!*.min.js', '--glob', '!*.lock', 'TODO|FIXME|HACK', '.'], output => {
    const count = output ? output.trimEnd().split('\n').length : 0
    return [Math.min(10, Math.floor(count / 10)), `count=${count}`]
  })
  if (!ran) return allow('health', 'no available checks')
  score = Math.max(0, score)
  const path = mode === 'shadow'
    ? '.claude/knowledge-db/health-history.mod-shadow.jsonl'
    : '.claude/knowledge-db/health-history.jsonl'
  const prior = await $.fs.read(path).catch(() => '')
  let previous: number | undefined
  for (const line of prior.split('\n')) {
    try { const record = JSON.parse(line) as { score?: number; truncated?: boolean }; if (!record.truncated && typeof record.score === 'number') previous = record.score } catch { /* bad history line */ }
  }
  await $.fs.write(path, prior + JSON.stringify({ at: new Date().toISOString(), score, checks, skipped, truncated }) + '\n').catch(() => {})
  const drop = previous === undefined ? 0 : previous - score
  if (drop >= 5) {
    const items = Object.entries(checks).filter(([, item]) => item.penalty > 0).map(([name, item]) => `${name}(-${item.penalty})`).join(', ') || '상세 검사 결과'
    return warn('health', `⚠️ [health-gate] 점수 하락: 이전 ${previous} → 현재 ${score} (-${drop}). 감점 항목: ${items} / 회귀 가능성을 확인하고 커밋하라.`)
  }
  return allow('health', `score ${score}; no regression of 5 or more`)
}

async function logShadow($: EngineInterface, record: unknown): Promise<void> {
  const home = await $.env.get('HOME')
  if (!home) return
  const path = home + HOME_LOG
  logQueue = logQueue.catch(() => {}).then(async () => {
    const prior = await $.fs.read(path).catch(() => '')
    await $.fs.write(path, prior + JSON.stringify(record) + '\n')
  })
  await logQueue
}
async function decide($: EngineInterface, e: ToolCallInput, mode: 'shadow' | 'enforce'): Promise<Decision[]> {
  if (e.tool === 'Write' || e.tool === 'Edit') return [await freeze($, e.file_path)]
  if (e.tool !== 'Bash') return []
  const results: Decision[] = []
  for (const check of [() => sandbox($, e.command), () => secretGuard($, e.command), () => rtk($, e.command), () => health($, e.command, mode)]) {
    const result = await check()
    results.push(result)
    if (result.verdict === 'deny') break
  }
  return results
}
export const register: Register = (on, options) => {
  on('tool.call', async ($, e, next) => {
    const started = await $.clock.now()
    let decisions: Decision[]
    try { decisions = await decide($, e, options.mode === 'enforce' ? 'enforce' : 'shadow') }
    catch (error) {
      // A failed classic hook is ignored by the host unless it explicitly exits nonzero.
      const message = error instanceof Error ? error.message : String(error)
      decisions = [warn('internal', `guard error: ${message}`)]
    }
    const selected = decisions.find(d => d.verdict === 'deny')
    const preElapsedMs = (await $.clock.now()) - started
    if (options.mode !== 'enforce') {
      const ran = await next(e)
      let postElapsedMs = 0
      if ((e.tool === 'Write' || e.tool === 'Edit') && ran.deny === undefined) {
        const postStarted = await $.clock.now()
        decisions.push(await secretPost($, e.file_path).catch(() => allow('secret-post', 'scan failed')))
        postElapsedMs = (await $.clock.now()) - postStarted
      }
      await logShadow($, { at: new Date().toISOString(), tool: e.tool, toolUseId: e.tool_use_id, verdict: selected ? 'deny' : decisions.some(d => d.verdict === 'warn') ? 'warn' : 'allow', reasons: decisions.map(d => ({ hook: d.hook, verdict: d.verdict, reason: d.reason })), elapsedMs: preElapsedMs + postElapsedMs }).catch(() => {})
      return ran
    }
    if (selected?.hook === 'sandbox' && selected.reason.includes('T2 confirmation required')) {
      const category = selected.reason.split(':', 1)[0]
      await $.process.run(['bash', '/Users/gangseungsig/.claude/harness-core/hooks/request-user-confirm.sh', '-', category, `명령 실행 승인 필요: ${selected.reason}`], { timeoutMs: 1000 }).catch(() => {})
    }
    if (selected) return { deny: selected.message || selected.reason }
    const warnings = decisions.filter(d => d.verdict === 'warn').map(d => d.reason)
    if (warnings.length) $.ui.status(warnings.join('; '))
    const rewrite = decisions.find(d => d.rewrite)?.rewrite
    const ran = e.tool === 'Bash' && rewrite ? await next({ ...e, command: rewrite }) : await next(e)
    if ((e.tool === 'Write' || e.tool === 'Edit') && ran.deny === undefined) {
      const post = await secretPost($, e.file_path).catch(() => allow('secret-post', 'scan failed'))
      if (post.verdict === 'warn') $.ui.status(post.reason)
    }
    return ran
  })
}
