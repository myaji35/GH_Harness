# harness-status

Claude Code 2.1.289 mod showing read-only harness status in the status line, AbovePrompt band, and `/hstatus`.

- Shows the main-loop model from `$.session.model()` (shortened, e.g. `Opus 5.5`) first in the status line and as `모델 …` in `/hstatus`; refreshed at session start and after each main turn, so `/model` switches appear after the next turn.
- Finds `.claude/issue-db/registry.json` by walking up from the session working directory (nearest wins, stopping at `$HOME` or `/`) on session start and after main turns when its modification time changes. Shows the latest `IN_PROGRESS` issue and count.
- Reads `opus_budget_state.daily.cost_usd` and `daily.limit_usd`, written by `opus-budget-check.sh` (estimated per-dispatch cost of opus/fable subagents, limit = Hard Cap). Until that hook records once, both appear as `—`. The recorded budget date appears in the detailed view to avoid presenting an old daily record as today's spending.
- Reads `$.session.usage().context.percent` when available.
- Reads the last line of the newest dated log under `~/Library/Logs/insuregraph-night/` on session start and every 30 minutes. An unavailable log is omitted.
- Reads `df -k /Volumes/E_SSD` at session start, every five minutes, and after main turns (skipping a lookup within 60 seconds of the last successful one). The status line begins with a 10-cell free-space bar; `/hstatus` and the AbovePrompt band use a 20-cell bar and show free and total capacity. The band appears whenever free space is below 20%, even without an active issue. It is green at 20% or more, yellow below 20%, and red below 10%. An unavailable or unmounted disk appears as `E_SSD 없음`.
- Toasts once per session for each downward crossing of 20%, 10%, and 5%; the notified thresholds live in `$.state`.

Unknown or unreadable values appear as `—`; no information is written back to either source.
