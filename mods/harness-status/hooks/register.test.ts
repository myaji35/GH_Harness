import { expect, test } from 'claude-code/testing'
import { ancestorDirs, detailText, diskBar, findRegistry, notifyDiskThresholds, parseDf, parseNight, parseRegistry,
  shortModelName, shortText } from './register'

test('latest active issue and unknown daily limit are factual', () => {
  const parsed = parseRegistry(JSON.stringify({
    issues: [
      { id: 'ISS-1', title: 'older', status: 'IN_PROGRESS', updated_at: '2026-10-01' },
      { id: 'ISS-2', title: 'latest issue title', status: 'IN_PROGRESS', updated_at: '2026-10-04' },
      { id: 'ISS-3', title: 'done', status: 'COMPLETED' },
    ],
    opus_budget_state: { daily: { date: '2026-07-15', cost_usd: 0.23 } },
  }))
  expect(parsed.issueCount).toBe(2)
  expect(parsed.latestIssue?.id).toBe('ISS-2')
  expect(parsed.budget?.limitUsd).toBe(null)
  expect(detailText({ ...parsed, registryMtimeMs: 1, night: null, contextPercent: null, disk: null, diskNotifiedThresholds: [] }))
    .toContain('예산(2026-07-15) $0.23/—')
})

test('nightly result comes only from the latest dated log line', () => {
  expect(parseNight('2026-10-04', '2026-10-04 07:00:00 실패\n2026-10-04 07:50:10 완료'))
    .toEqual({ date: '2026-10-04', time: '07:50', result: '완료' })
  expect(parseNight('2026-10-04', '2026-10-04 08:00:00 unrelated')).toBe(null)
})

test('df parses free KB and rejects absent or invalid mounts', () => {
  expect(parseDf('Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/disk4 2000000 1280000 720000 64% /Volumes/E_SSD\n'))
    .toEqual({ totalKb: 2000000, availableKb: 720000, percent: 36 })
  expect(parseDf('df: /Volumes/E_SSD: No such file or directory')).toBe(null)
  expect(parseDf('disk 0 0 0 100% /Volumes/E_SSD')).toBe(null)
  expect(parseDf('disk 10000 1000 9000 10% /')).toBe(null)
})

test('free-space bars show 0, 36, and 100 percent', () => {
  expect(diskBar(0, 10)).toBe('░░░░░░░░░░')
  expect(diskBar(36, 10)).toBe('▓▓▓▓░░░░░░')
  expect(diskBar(100, 10)).toBe('▓▓▓▓▓▓▓▓▓▓')
  expect(diskBar(36, 20)).toBe('▓▓▓▓▓▓▓░░░░░░░░░░░░░')
  const detail = detailText({ issueCount: 0, latestIssue: null, budget: null, registryMtimeMs: null,
    night: null, contextPercent: null, disk: { totalKb: 2_000_000, availableKb: 720_000, percent: 36, checkedAt: 1 },
    diskNotifiedThresholds: [] })
  expect(detail.includes('E_SSD ▓▓▓▓▓▓▓░░░░░░░░░░░░░ 36% 남음 (여유')).toBe(true)
})

test('each downward disk threshold toasts once per session', () => {
  const toasts: string[] = []
  let notified: number[] = []
  notified = notifyDiskThresholds(25, 9, notified, text => toasts.push(text))
  notified = notifyDiskThresholds(9, 8, notified, text => toasts.push(text))
  notified = notifyDiskThresholds(8, 4, notified, text => toasts.push(text))
  notified = notifyDiskThresholds(25, 4, notified, text => toasts.push(text))
  expect(notified).toEqual([20, 10, 5])
  expect(toasts.length).toBe(3)
})

test('registry is found by walking up from a nested cwd, stopping at home', async () => {
  expect(ancestorDirs('/Volumes/GH_APFS/0001_NURI/nuriCell/3D', '/Users/me'))
    .toEqual(['/Volumes/GH_APFS/0001_NURI/nuriCell/3D', '/Volumes/GH_APFS/0001_NURI/nuriCell', '/Volumes/GH_APFS/0001_NURI',
      '/Volumes/GH_APFS', '/Volumes', '/'])
  expect(ancestorDirs('/Users/me/proj/sub/', '/Users/me')).toEqual(['/Users/me/proj/sub', '/Users/me/proj', '/Users/me'])
  const files: Record<string, number> = { '/Volumes/GH_APFS/0001_NURI/.claude/issue-db/registry.json': 42 }
  const tried: string[] = []
  const stat = async (path: string) => {
    tried.push(path)
    const mtimeMs = files[path]
    if (mtimeMs === undefined) throw new Error('ENOENT')
    return { kind: 'file', mtimeMs }
  }
  expect(await findRegistry('/Volumes/GH_APFS/0001_NURI/nuriCell/3D', '/Users/me', stat))
    .toEqual({ path: '/Volumes/GH_APFS/0001_NURI/.claude/issue-db/registry.json', mtimeMs: 42 })
  expect(tried.length).toBe(3)
  // The nearest registry wins over a parent's.
  files['/Volumes/GH_APFS/0001_NURI/nuriCell/.claude/issue-db/registry.json'] = 7
  expect((await findRegistry('/Volumes/GH_APFS/0001_NURI/nuriCell/3D', '/Users/me', stat))?.mtimeMs).toBe(7)
  // Nothing above home is searched; nothing found is null.
  expect(await findRegistry('/Users/me/a', '/Users/me', stat)).toBe(null)
  expect(tried.includes('/Users/.claude/issue-db/registry.json')).toBe(false)
})

test('model ids shorten to family and version and lead the status text', () => {
  expect(shortModelName('claude-opus-5-5')).toBe('Opus 5.5')
  expect(shortModelName('claude-fable-5-1[1m]')).toBe('Fable 5.1')
  expect(shortModelName('Opus 5.5 (1M context)')).toBe('Opus 5.5')
  expect(shortModelName('claude-sonnet-4-5-20250929')).toBe('Sonnet 4.5')
  expect(shortModelName('claude-opus-5-20251101')).toBe('Opus 5')
  expect(shortModelName('claude-3-5-haiku-20241022')).toBe('Haiku 3.5')
  expect(shortModelName('sonnet')).toBe('Sonnet')
  expect(shortModelName('')).toBe(null)
  const s = { issueCount: 1, latestIssue: { id: 'ISS-397', title: 't', updatedAt: '' }, budget: null,
    registryMtimeMs: 1, night: null, contextPercent: 11, disk: null, diskNotifiedThresholds: [], model: 'Opus 5.5' }
  expect(shortText(s).startsWith('Opus 5.5 · E_SSD 없음 · ISS-397')).toBe(true)
  expect(detailText(s).startsWith('모델 Opus 5.5 · ')).toBe(true)
  expect(shortText({ ...s, model: null }).startsWith('E_SSD')).toBe(true)
})

test('budget written by the fixed hook shows cost and hard cap', () => {
  const parsed = parseRegistry(JSON.stringify({ issues: [],
    opus_budget_state: { daily: { date: '2026-10-22', cost_usd: 0.43, calls: 2, limit_usd: 20 } } }))
  expect(detailText({ ...parsed, registryMtimeMs: 1, night: null, contextPercent: null, disk: null,
    diskNotifiedThresholds: [] })).toContain('예산(2026-10-22) $0.43/$20')
})
