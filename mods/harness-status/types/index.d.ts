export type HarnessIssue = { id: string; title: string; updatedAt: string }
export type HarnessBudget = { date: string | null; costUsd: number | null; limitUsd: number | null }
export type HarnessNight = { date: string; time: string; result: '완료' | '실패' | '진행' }
export type HarnessDisk = { totalKb: number; availableKb: number; percent: number; checkedAt: number }
export type HarnessSnapshot = {
  issueCount: number | null
  latestIssue: HarnessIssue | null
  budget: HarnessBudget | null
  registryMtimeMs: number | null
  night: HarnessNight | null
  contextPercent: number | null
  disk: HarnessDisk | null
  diskNotifiedThresholds: number[]
  /** Main-loop model as `$.session.model()` returns it; null when unavailable. */
  model?: string | null
  /** registry.json path found by walking up from cwd; null when none. */
  registryPath?: string | null
}

declare module 'claude-code' {
  interface PluginState {
    'harness-status': { snapshot: HarnessSnapshot }
  }
}
