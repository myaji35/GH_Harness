import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'
import type { HarnessBudget, HarnessDisk, HarnessIssue, HarnessNight, HarnessSnapshot } from '../types/index'

const snapshot = atom({ plugin: 'harness-status', key: 'snapshot' } as const, {
  issueCount: null, latestIssue: null, budget: null, registryMtimeMs: null,
  night: null, contextPercent: null, disk: null, diskNotifiedThresholds: [],
  model: null, registryPath: null,
} as HarnessSnapshot)

export function parseDf(raw: string): Pick<HarnessDisk, 'totalKb' | 'availableKb' | 'percent'> | null {
  const columns = raw.trim().split(/\r?\n/).at(-1)?.trim().split(/\s+/) ?? []
  const totalKb = Number(columns[1])
  const availableKb = Number(columns[3])
  if (columns.length < 6 || columns.at(-1) !== '/Volumes/E_SSD' || !Number.isSafeInteger(totalKb) || totalKb <= 0 ||
      !Number.isSafeInteger(availableKb) || availableKb < 0 || availableKb > totalKb) return null
  return { totalKb, availableKb, percent: availableKb / totalKb * 100 }
}

export function diskBar(percent: number, width: number): string {
  const filled = Math.max(0, Math.min(width, Math.round(percent / 100 * width)))
  return '▓'.repeat(filled) + '░'.repeat(width - filled)
}

function size(kb: number): string {
  const gb = kb / 1024 / 1024
  return gb >= 1024 ? `${(gb / 1024).toFixed(1)}T` : `${Math.round(gb)}G`
}

function diskText(disk: HarnessDisk | null, width: number, detailed = false): string {
  if (!disk) return 'E_SSD 없음'
  const pct = Math.round(disk.percent)
  return `E_SSD ${diskBar(disk.percent, width)} ${pct}% 남음 ` +
    (detailed ? `(여유 ${size(disk.availableKb)} / 전체 ${size(disk.totalKb)})` : `(${size(disk.availableKb)})`)
}

export function crossedDiskThresholds(previous: number | null, current: number, notified: number[]): number[] {
  return [20, 10, 5].filter(level => previous !== null && previous >= level && current < level && !notified.includes(level))
}

export function notifyDiskThresholds(previous: number | null, current: number, notified: number[], toast: (text: string) => void): number[] {
  const crossed = crossedDiskThresholds(previous, current, notified)
  for (const level of crossed) toast(`E_SSD 여유 ${Math.round(current)}% — ${level}% 경계 아래로 하락`)
  return [...notified, ...crossed]
}

async function refreshDisk($: EngineInterface): Promise<void> {
  const old = await read($, snapshot)
  const now = await $.clock.now()
  if (old.disk && now - old.disk.checkedAt < 60_000) return
  let disk: HarnessDisk | null = null
  try {
    const result = await $.process.run(['df', '-k', '/Volumes/E_SSD'], { timeoutMs: 3000 })
    const parsed = result.exitCode === 0 ? parseDf(result.stdout) : null
    if (parsed) disk = { ...parsed, checkedAt: now }
  } catch { /* Unmounted or unavailable disk. */ }
  const crossed = disk ? crossedDiskThresholds(old.disk?.percent ?? null, disk.percent, old.diskNotifiedThresholds ?? []) : []
  await update($, snapshot, current => ({ ...current, disk,
    diskNotifiedThresholds: [...(current.diskNotifiedThresholds ?? []), ...crossed] }))
  if (disk) notifyDiskThresholds(old.disk?.percent ?? null, disk.percent, old.diskNotifiedThresholds ?? [], text => $.ui.toast(text))
}

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

const REGISTRY_REL = '.claude/issue-db/registry.json'

/** Directories from `start` up to (and including) `home`, or the filesystem root when `start` is outside home. */
export function ancestorDirs(start: string, home: string | null): string[] {
  const trim = (p: string) => p.length > 1 ? p.replace(/\/+$/, '') : p
  let dir = trim(start)
  const stop = home ? trim(home) : null
  const dirs: string[] = []
  while (dir) {
    dirs.push(dir)
    if (dir === '/' || dir === stop) break
    const cut = dir.lastIndexOf('/')
    dir = cut <= 0 ? '/' : dir.slice(0, cut)
  }
  return dirs
}

/** First `<dir>/.claude/issue-db/registry.json` that is a file, walking up from `start`. */
export async function findRegistry(start: string, home: string | null,
    stat: (path: string) => Promise<{ kind: string; mtimeMs: number }>): Promise<{ path: string; mtimeMs: number } | null> {
  for (const dir of ancestorDirs(start, home)) {
    const path = `${dir === '/' ? '' : dir}/${REGISTRY_REL}`
    try {
      const s = await stat(path)
      if (s.kind === 'file') return { path, mtimeMs: s.mtimeMs }
    } catch { /* not here; keep walking up */ }
  }
  return null
}

async function refreshRegistry($: EngineInterface, force = false): Promise<void> {
  try {
    const home = (await $.env.get('HOME')) ?? null
    const found = await findRegistry(await $.session.cwd(), home, path => $.fs.stat(path))
    if (!found) throw new Error('no registry')
    const old = await read($, snapshot)
    if (!force && found.mtimeMs === old.registryMtimeMs && found.path === old.registryPath) return
    const parsed = parseRegistry(await $.fs.read(found.path))
    await update($, snapshot, old => ({ ...old, ...parsed, registryMtimeMs: found.mtimeMs, registryPath: found.path }))
  } catch {
    await update($, snapshot, old => ({ ...old, issueCount: null, latestIssue: null,
      budget: null, registryMtimeMs: null, registryPath: null }))
  }
}

/** `claude-opus-5-5` / `claude-fable-5-1[1m]` / `opus` → `Opus 5.5` / `Fable 5.1` / `Opus`; unknown spellings pass through. */
export function shortModelName(raw: string | null | undefined): string | null {
  const text = (raw ?? '').trim()
  if (!text) return null
  const cap = (f: string | undefined) => f ? f.charAt(0).toUpperCase() + f.slice(1).toLowerCase() : ''
  const m = text.match(/(opus|sonnet|haiku|fable)[-\s]?(\d{1,2})(?!\d)(?:[-.](\d{1,2})(?!\d))?/i)
  if (m) return `${cap(m[1])} ${m[2]}${m[3] ? `.${m[3]}` : ''}`
  const legacy = text.match(/(\d{1,2})[-.](\d{1,2})-(opus|sonnet|haiku)/i)
  if (legacy) return `${cap(legacy[3])} ${legacy[1]}.${legacy[2]}`
  const family = text.match(/^(opus|sonnet|haiku|fable)$/i)
  if (family) return cap(family[1])
  return text.replace(/\[[^\]]*\]$/, '')
}

async function refreshModel($: EngineInterface): Promise<void> {
  let model: string | null = null
  try { model = shortModelName(await $.session.model()) } catch { /* unavailable */ }
  await update($, snapshot, old => ({ ...old, model }))
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
export function shortText(s: HarnessSnapshot): string {
  const parts = [...(s.model ? [s.model] : []), diskText(s.disk, 10), s.latestIssue?.id ?? '이슈 —', budgetText(s.budget)]
  if (s.contextPercent !== null) parts.push(`컨텍스트 ${Math.round(s.contextPercent)}%`)
  if (s.night) parts.push(`야간 ${s.night.time} ${s.night.result}`)
  return parts.join(' · ')
}
export function detailText(s: HarnessSnapshot): string {
  const issue = s.latestIssue
    ? `${s.latestIssue.id} ${s.latestIssue.title.slice(0, 20)}${s.issueCount !== null && s.issueCount > 1 ? ` (진행 중 ${s.issueCount}건)` : ''}`
    : s.issueCount === 0 ? '진행 중 이슈 없음' : '진행 중 이슈 —'
  const parts = [...(s.model ? [`모델 ${s.model}`] : []), diskText(s.disk, 20, true), issue, budgetText(s.budget)]
  if (s.contextPercent !== null) parts.push(`컨텍스트 ${Math.round(s.contextPercent)}%`)
  if (s.night) parts.push(`야간 ${s.night.date} ${s.night.time} ${s.night.result}`)
  return parts.join(' · ')
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({ name: 'hstatus', description: '하네스 상태 표시' })
    await refreshModel($)
    await refreshRegistry($, true)
    await refreshNight($)
    await refreshContext($)
    await refreshDisk($)
    $.ui.status(shortText(await read($, snapshot)))
    $.clock.every(30 * 60 * 1000, async () => {
      await refreshNight($)
      $.ui.status(shortText(await read($, snapshot)))
    })
    $.clock.every(5 * 60 * 1000, async () => {
      await refreshDisk($)
      $.ui.status(shortText(await read($, snapshot)))
    })
    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    if (e.agentId === undefined) {
      await refreshModel($)
      await refreshRegistry($)
      await refreshContext($)
      await refreshDisk($)
      $.ui.status(shortText(await read($, snapshot)))
    }
    return next(e)
  })

  on('command.run', { command: 'hstatus' }, async $ => {
    return { text: detailText(await read($, snapshot)) }
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const s = await read($, snapshot)
    if (e.props.hasSurvey || (!s.latestIssue && (s.disk?.percent ?? 100) >= 20)) return next(e)
    const { Box, Text } = $.ui.resolve(e)
    const color = !s.disk ? undefined : s.disk.percent < 10 ? 'red' : s.disk.percent < 20 ? 'yellow' : 'green'
    return <Box><Text color={color} wrap="truncate-end">{detailText(s)}</Text></Box>
  })
}
