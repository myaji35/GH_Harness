import { expect, test } from 'claude-code/testing'
import { detailText, parseNight, parseRegistry } from './register'

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
  expect(detailText({ ...parsed, registryMtimeMs: 1, night: null, contextPercent: null }))
    .toContain('예산(2026-07-15) $0.23/—')
})

test('nightly result comes only from the latest dated log line', () => {
  expect(parseNight('2026-10-04', '2026-10-04 07:00:00 실패\n2026-10-04 07:50:10 완료'))
    .toEqual({ date: '2026-10-04', time: '07:50', result: '완료' })
  expect(parseNight('2026-10-04', '2026-10-04 08:00:00 unrelated')).toBe(null)
})
