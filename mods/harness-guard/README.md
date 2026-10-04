# harness-guard mod

Claude Code 2.1.289 function-hook version of five existing PreToolUse shell hooks. It registers one `tool.call` handler. The default `shadow` mode evaluates each call, writes its verdict, reasons, and elapsed milliseconds to `~/.claude/harness-core/logs/mod-guard-shadow.jsonl`, then calls `next(e)`. `enforce` returns `{ deny: message }` for deny decisions and otherwise calls `next(e)`; RTK rewrites are passed to `next` in that mode.

| Existing hook | Ported rule |
| --- | --- |
| `freeze-guard.sh` | On Write/Edit, block a path outside `FREEZE_DIR` while the freeze file exists. A freeze with an issue in the registry is active only for `IN_PROGRESS` or `BACKGROUND_RUNNING`. |
| `sandbox-enforce.sh` | Bash block patterns for dangerous deletion, destructive device writes, unsafe chmod, pipe-to-shell, and `sudo rm`; warning/T2 patterns for force push, hard reset, cleanup, SQL deletion, deployment deletion, and publishing. `HARNESS_SANDBOX_BYPASS=1/2` keeps the shell semantics. |
| `secret-guard.sh` | On Bash commands containing `git commit` or `git push`, inspect staged filenames first, then added diff lines, excluding test/spec paths and placeholder values. After Write/Edit completes, warn about a secret in the edited file. |
| `rtk-guard.sh` | Ask `rtk hook claude` for a rewrite of likely supported commands; pass through if RTK is absent or fails. |
| `health-gate.sh` | On commit with a registry, run available typecheck, tsc, lint, Rubocop, and TODO checks, record score history, and warn only if the score drops at least five points. |

## Configuration

Load with `claude --plugin-dir mods/harness-guard`. The default is `shadow`. To enforce, put this in user settings (`~/.claude/settings.json`), or choose **Guard mode → enforce** in `/config`:

```json
{"pluginConfigs":{"harness-guard":{"options":{"mode":"enforce"}}}}
```

Keep the existing shell hooks installed while comparing shadow logs. Shadow health scores and regression comparisons use `.claude/knowledge-db/health-history.mod-shadow.jsonl`; the shell health-gate continues using `.claude/knowledge-db/health-history.jsonl`. When switching to `enforce`, disable the shell `health-gate.sh` hook at the same time, since enforce mode uses the shared history file. To roll back, disable this mod or remove its `--plugin-dir`, then re-enable the shell health-gate if it was disabled.

## Verification

`test/capture-expected.sh` creates a temporary git repository, executes each real shell hook with stdin JSON, and records 38 fixture verdicts in `test/fixtures.json` (`source: shell`). `test/fixtures.ts` is generated from the same capture for the Claude Code test runner, which cannot import JSON modules. The test compares every fixture with the mod's corresponding decision function. `._*` AppleDouble files are ignored and removed before test commands because the CLI otherwise mistakes them for tests.

## Known differences

- The classic sandbox hook expects a top-level `command` field while the other hooks read a `tool_input` envelope. Sandbox fixtures use the script's top-level shape. The mod sees `e.command` directly, so it detects dangerous commands consistently; a classic call with an envelope can miss them.
- The mod uses a 5-second sub-budget for health checks and 1.2-second per-process caps to keep the complete decision below 10 seconds. The shell worker allows 45 seconds overall and 20 seconds per check. A slow check can therefore be skipped or timed out and yield a different score.
- The supplied Claude Code API type exposes `$.fs.read` and `$.fs.write`, but no append method. Shadow logs and health history are read and rewritten with `$.fs.write`; simultaneous Claude sessions can lose an appended line. Shell append is atomic at the file descriptor level. Shadow health history is separate from the shell file; only enforce mode reads and writes the shell file.
- In enforce mode the mod calls `request-user-confirm.sh` for WARN+T2 before denying. The shell sandbox also calls `decision-trace.sh` for block/warn events; the mod uses its JSONL decision record instead, so it does not add a legacy trace line. While both shell and mod are enabled, the T2 helper can be called twice.
- Shell `source` accepts arbitrary code in freeze files. The mod reads literal `FREEZE_DIR` and `FREEZE_ISSUE` assignments, which covers generated freeze files without executing arbitrary shell code.
- The post-tool secret warning is reproduced after a Write/Edit `tool.call` completes. While the existing `PostToolUse` shell hook remains enabled, the warning can appear twice.

An internal error is recorded as a warning and passed through. The original freeze, secret, and health hooks also pass on parse/check failures; sandbox's `set -e` can exit nonzero for some host command failures. The mod's narrow filesystem/process calls catch expected missing-file or missing-command errors and do not block on those failures.
