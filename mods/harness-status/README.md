# harness-status

Claude Code 2.1.289 mod showing read-only harness status in the status line, AbovePrompt band, and `/hstatus`.

- Reads `.claude/issue-db/registry.json` from the session working directory on session start and after main turns when its modification time changes. Shows the latest `IN_PROGRESS` issue and count.
- Reads `opus_budget_state.daily.cost_usd` and `daily.limit_usd`. The current registry has no daily limit field, so the limit appears as `—`. The recorded budget date appears in the detailed view to avoid presenting an old daily record as today's spending.
- Reads `$.session.usage().context.percent` when available.
- Reads the last line of the newest dated log under `~/Library/Logs/insuregraph-night/` on session start and every 30 minutes. An unavailable log is omitted.

Unknown or unreadable values appear as `—`; no information is written back to either source.
