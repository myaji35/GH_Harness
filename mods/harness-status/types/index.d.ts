export type HarnessIssue = { id: string; title: string; updatedAt: string }
export type HarnessBudget = { date: string | null; costUsd: number | null; limitUsd: number | null }
export type HarnessNight = { date: string; time: string; result: '완료' | '실패' | '진행' }
export type HarnessSnapshot = {
  issueCount: number | null
  latestIssue: HarnessIssue | null
  budget: HarnessBudget | null
  registryMtimeMs: number | null
  night: HarnessNight | null
  contextPercent: number | null
}

declare module 'claude-code' {
  interface PluginState {
    'harness-status': { snapshot: HarnessSnapshot }
  }
}
