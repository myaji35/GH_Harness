import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'
import type { HarnessBudget, HarnessIssue, HarnessNight, HarnessSnapshot } from '../types/index'

const snapshot = atom({ plugin: 'harness-status', key: 'snapshot' } as const, {
  issueCount: null, latestIssue: null, budget: null, registryMtimeMs: null,
  night: null, contextPercent: null,
} as HarnessSnapshot)

function object(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
    ? value as Record<string, unknown> : null
}

function finite(value: unknown): number | null {
  return typeof value === 'number' && Number.isFinite(value) ? value : null
}

export function parseRegistry(raw: string): Pick<HarnessSnapshot, 'issueCount' | 'latestIssue' | 'budget'> {
  const data = object(JSON.parse(raw))
  if (!data) return { issueCount: null, latestIssue: null, budget: null }
  const issues = Array.isArray(data.issues) ? data.issues : null
  const active: HarnessIssue[] = (issues ?? []).flatMap(value => {
    const issue = object(value)
    if (!issue || issue.status !== 'IN_PROGRESS' || typeof issue.id !== 'string') return []
    return [{ id: issue.id, title: typeof issue.title === 'string' ? issue.title : '—',
      updatedAt: typeof issue.updated_at === 'string' ? issue.updated_at :
        typeof issue.created_at === 'string' ? issue.created_at : '' }]
  })
  active.sort((a, b) => b.updatedAt.localeCompare(a.updatedAt))
  const budgetState = object(data.opus_budget_state)
  const daily = object(budgetState?.daily)
  const budget: HarnessBudget | null = budgetState ? {
    date: typeof daily?.date === 'string' ? daily.date : null,
    costUsd: finite(daily?.cost_usd),
    limitUsd: finite(daily?.limit_usd),
  } : null
  return { issueCount: issues ? active.length : null, latestIssue: active[0] ?? null, budget }
}

async function refreshRegistry($: EngineInterface, force = false): Promise<void> {
  const path = `${await $.session.cwd()}/.claude/issue-db/registry.json`
  try {
    const stat = await $.fs.stat(path)
    const old = await read($, snapshot)
    if (!force && stat.mtimeMs === old.registryMtimeMs) return
    const parsed = parseRegistry(await $.fs.read(path))
    await update($, snapshot, old => ({ ...old, ...parsed, registryMtimeMs: stat.mtimeMs }))
  } catch {
    await update($, snapshot, old => ({ ...old, issueCount: null, latestIssue: null,
      budget: null, registryMtimeMs: null }))
  }
}

export function parseNight(date: string, raw: string): HarnessNight | null {
  const last = raw.trimEnd().split(/\r?\n/).at(-1) ?? ''
  const time = last.match(/\b(\d{2}:\d{2})(?::\d{2})?\b/)?.[1]
  const result = /실패|에러|오류|failed|error/i.test(last) ? '실패'
    : /완료|성공|completed|success/i.test(last) ? '완료'
    : /진행|실행 중|시작|running|started/i.test(last) ? '진행' : null
  return time && result ? { date, time, result } : null
}

async function refreshNight($: EngineInterface): Promise<void> {
  let night: HarnessNight | null = null
  try {
    const home = await $.env.get('HOME')
    if (home) {
      const dir = `${home}/Library/Logs/insuregraph-night`
      const dates = (await $.fs.list(dir)).filter(entry => entry.kind === 'file' &&
        /^\d{4}-\d{2}-\d{2}\.log$/.test(entry.name)).sort((a, b) => b.name.localeCompare(a.name))
      if (dates[0]) night = parseNight(dates[0].name.slice(0, 10), await $.fs.read(`${dir}/${dates[0].name}`))
    }
  } catch { /* An absent or unreadable log has no status. */ }
  await update($, snapshot, old => ({ ...old, night }))
}

async function refreshContext($: EngineInterface): Promise<void> {
  let contextPercent: number | null = null
  try { contextPercent = finite((await $.session.usage()).context.percent) } catch { /* unavailable */ }
  await update($, snapshot, old => ({ ...old, contextPercent }))
}

function money(value: number | null): string { return value === null ? '—' : `$${value}` }
function budgetText(value: HarnessBudget | null): string {
  return `예산${value?.date ? `(${value.date})` : ''} ${money(value?.costUsd ?? null)}/${money(value?.limitUsd ?? null)}`
}
function shortText(s: HarnessSnapshot): string {
  const parts = [s.latestIssue?.id ?? '이슈 —', budgetText(s.budget)]
  if (s.contextPercent !== null) parts.push(`컨텍스트 ${Math.round(s.contextPercent)}%`)
  if (s.night) parts.push(`야간 ${s.night.time} ${s.night.result}`)
  return parts.join(' · ')
}
export function detailText(s: HarnessSnapshot): string {
  const issue = s.latestIssue
    ? `${s.latestIssue.id} ${s.latestIssue.title.slice(0, 20)}${s.issueCount !== null && s.issueCount > 1 ? ` (진행 중 ${s.issueCount}건)` : ''}`
    : s.issueCount === 0 ? '진행 중 이슈 없음' : '진행 중 이슈 —'
  const parts = [issue, budgetText(s.budget)]
  if (s.contextPercent !== null) parts.push(`컨텍스트 ${Math.round(s.contextPercent)}%`)
  if (s.night) parts.push(`야간 ${s.night.date} ${s.night.time} ${s.night.result}`)
  return parts.join(' · ')
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({ name: 'hstatus', description: '하네스 상태 표시' })
    await refreshRegistry($, true)
    await refreshNight($)
    await refreshContext($)
    $.ui.status(shortText(await read($, snapshot)))
    $.clock.every(30 * 60 * 1000, async () => {
      await refreshNight($)
      $.ui.status(shortText(await read($, snapshot)))
    })
    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    if (e.agentId === undefined) {
      await refreshRegistry($)
      await refreshContext($)
      $.ui.status(shortText(await read($, snapshot)))
    }
    return next(e)
  })

  on('command.run', { command: 'hstatus' }, async $ => {
    return { text: detailText(await read($, snapshot)) }
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const s = await read($, snapshot)
    if (e.props.hasSurvey || !s.latestIssue) return next(e)
    const { Box, Text } = $.ui.resolve(e)
    const line = e.props.bodyColumns < 80 ? shortText(s) : detailText(s)
    return <Box><Text wrap="truncate-end">{line}</Text></Box>
  })
}
