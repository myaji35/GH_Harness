import { test, expect, mock } from 'claude-code/testing'
import type { EngineInterface } from 'claude-code'
import { sandbox, freeze, secretGuard, secretPost, rtk, health } from '../hooks/register'
import { fixtures as fixturesData } from './fixtures'

type Case = { id: string; hook: string; command: string | null; file_path: string | null; setup: string; bypass: string; expected: string; source: string }

test('all captured shell verdicts match the mod decision', async $ => {
  const fixtures = fixturesData as unknown as Case[]
  expect(fixtures.length >= 25).toBe(true)
  for (const fixture of fixtures) {
    const fake = {
      env: { get: async (name: string) => name === 'HARNESS_SANDBOX_BYPASS' ? fixture.bypass : undefined },
      session: { cwd: async () => '/fixture/repo' },
      clock: { now: async () => 0 },
      fs: {
        exists: async (path: string) => {
          if (path.includes('harness-freeze-')) return fixture.setup !== 'absent'
          if (path === '.claude/issue-db/registry.json') return fixture.hook === 'freeze' || fixture.hook === 'health'
          if (fixture.id === 'health_drop' && path === 'package.json') return true
          if (fixture.id.startsWith('secret_post_')) return true
          return false
        },
        read: async (path: string) => {
          if (path.includes('harness-freeze-')) return `FREEZE_DIR=${fixture.id === 'freeze_inside' ? fixture.file_path?.slice(0, fixture.file_path.lastIndexOf('/')) : '/fixture/repo/allowed'}\nFREEZE_ISSUE=${fixture.setup === 'no_issue' ? '' : fixture.setup === 'ready' ? 'ISS-B' : 'ISS-A'}\n`
          if (path === '.claude/issue-db/registry.json') return JSON.stringify({ issues: [{id:'ISS-A',status:'IN_PROGRESS'},{id:'ISS-B',status:'READY'}] })
          if (fixture.id === 'health_drop' && path === 'package.json') return JSON.stringify({scripts:{typecheck:'false'}})
          if (fixture.id === 'health_drop' && path === '.claude/knowledge-db/health-history.jsonl') return '{"score":100,"truncated":false}\n'
          if (fixture.id === 'secret_post_value') return 'API_KEY=\"supersecretvalue123456\"'
          if (fixture.id === 'secret_post_plain') return 'base'
          return ''
        },
        stat: async (path: string) => {
          if (path.includes('request-user-confirm.sh')) return { kind: 'file' }
          return { kind: 'directory', realPath: path }
        },
        write: async () => {},
      },
      process: { run: async (argv: string[]) => {
        if (fixture.id === 'health_drop' && argv[0] === 'npm') return {exitCode:1,stdout:'',stderr:''}
        if (argv[0] === 'rtk') return { exitCode: 0, stdout: fixture.id === 'rtk_target' ? JSON.stringify({hookSpecificOutput:{updatedInput:{command:'rtk ls -la'}}}) : '', stderr: '' }
        if (argv[0] === 'git' && argv.includes('--name-only')) return { exitCode: 0, stdout: fixture.setup === 'secret_name' ? '.env\n' : '', stderr: '' }
        if (argv[0] === 'git') return { exitCode: 0, stdout: fixture.setup === 'secret_value' ? '+API_KEY="supersecretvalue123456"\n' : fixture.setup === 'test_value' ? '' : '', stderr: '' }
        throw new Error('not installed')
      } },
    } as unknown as EngineInterface
    const actual = fixture.hook === 'sandbox' ? await sandbox(fake, fixture.command || '')
      : fixture.hook === 'freeze' ? await freeze(fake, fixture.file_path || '')
      : fixture.hook === 'secret' && fixture.tool === 'Write' ? await secretPost(fake, fixture.file_path || '')
      : fixture.hook === 'secret' ? await secretGuard(fake, fixture.command || '')
      : fixture.hook === 'rtk' ? await rtk(fake, fixture.command || '')
      : await health(fake, fixture.command || '', 'enforce')
    if (actual.verdict !== fixture.expected) throw new Error(`${fixture.id}: expected ${fixture.expected}, got ${actual.verdict}`)
  }
})

test('shadow health reads and writes only its own history', async $ => {
  const shared = '.claude/knowledge-db/health-history.jsonl'
  const shadow = '.claude/knowledge-db/health-history.mod-shadow.jsonl'
  const reads: string[] = []
  const writes: { path: string; text: string }[] = []
  const fake = {
    clock: { now: async () => 0 },
    fs: {
      exists: async (path: string) => path === '.claude/issue-db/registry.json' || path === 'package.json',
      read: async (path: string) => {
        reads.push(path)
        if (path === 'package.json') return JSON.stringify({ scripts: { typecheck: 'false' } })
        if (path === shadow) return '{"score":100,"truncated":false}\n'
        if (path === shared) return '{"score":20,"truncated":false}\n'
        return ''
      },
      write: async (path: string, text: string) => { writes.push({ path, text }) },
    },
    process: { run: async (argv: string[]) => {
      if (argv[0] === 'npm') return { exitCode: 1, stdout: '', stderr: '' }
      throw new Error('not installed')
    } },
  } as unknown as EngineInterface
  const result = await health(fake, 'git commit -m test', 'shadow')
  expect(result.verdict).toBe('warn')
  expect(reads.includes(shadow)).toBe(true)
  expect(reads.includes(shared)).toBe(false)
  expect(writes.length).toBe(1)
  expect(writes[0].path).toBe(shadow)
  expect(writes[0].text.includes('"score":70')).toBe(true)
})

test('shadow passes a denied sandbox pattern to the next hook', { options: { mode: 'shadow' } }, async ($, on) => {
  mock.clock(on)
  mock.env(on, { HARNESS_SANDBOX_BYPASS: '0' })
  on('tool.call', { tool: 'Bash' }, () => ({ deny: 'downstream marker' }))
  const result = await $.tool.call({ tool: 'Bash', command: 'rm -rf /' })
  expect(result.deny).toBe('downstream marker')
})

test('enforce denies a sandbox pattern before the next hook', { options: { mode: 'enforce' } }, async ($, on) => {
  mock.clock(on)
  mock.env(on, { HARNESS_SANDBOX_BYPASS: '0' })
  on('tool.call', { tool: 'Bash' }, () => ({ deny: 'downstream marker' }))
  const result = await $.tool.call({ tool: 'Bash', command: 'rm -rf /' })
  expect(result.deny?.includes('[Sandbox BLOCK]')).toBe(true)
})
