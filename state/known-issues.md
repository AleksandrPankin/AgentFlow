# Known Issues

Errors, dead ends, and constraints of the AgentFlow template. Each entry: date, issue, when to look again.

- 2026-10-03 - Claude as Tester cannot be sandboxed on Windows: review isolation is detected after the attempt (attempt `error`), not prevented. Reopen if Claude Code gets a Bash sandbox on Windows.
- 2026-10-03 - `limitHit` is a text match ("usage limit", "rate limit", "quota") on the last 50 log lines; a task whose output mentions these words can be misread. Reopen if a tool reports limits in a structured way.
- 2026-10-03 - Attempt records and logs are not committed (verify records are, since 2.4.0): on a fresh clone an old task's verify cannot be re-run, while its acceptance evidence stays in `T-NNN.verify.json`.
- 2026-10-03 - `## Checks` commands run in PowerShell on Windows and `sh` elsewhere; a command written for another shell fails verify.
- 2026-10-03 - Antigravity IDE cannot be automated: its attempts are `-Manual` and end with `-MarkFinished`.
- 2026-10-06 - `-Wait` wakes the Orchestrator only while its session is open; a closed session sees finished tasks at the next start. 2.2.0 is verified in a sandbox with placeholder processes, not yet with real codex / claude / agy windows (Stage 3 pilot). Reopen after the pilot.
- 2026-10-06 - Shell heredocs on Windows mangle backslash escapes (`\t`, `\b`, `\a`) and Cyrillic when used to edit files: edit with the editor tool or a script file instead.
- 2026-10-09 - Spec items are found only in one format: a heading `### <ID> — <title>` and `- **Статус:** <STATUS>` (AC: `- **Source:** FR-###`). A hand-edited block in another format is invisible to `gate.py` (preflight then says "not found"); files `05`-`09` are never scanned. Reopen if live projects keep breaking the format.
- 2026-10-09 - Cyrillic in `gate.py` output is mangled in a Windows console without UTF-8; machine messages stay English, Cyrillic only in file content.
- 2026-10-09 - The human's acts are recorded by agents: the production `Approval:` line by the Deployer, chat answers in the owner journal by the Orchestrator (channel `chat`, quoted verbatim). Such a record is as reliable as the session that wrote it; `approve.ps1` was rejected for the same reason (decisions 2026-10-03). `gate.py spec` checks only that `APPROVED (OWN-###)` names a done owner task, not what the human answered. Reopen if a tool offers a confirmation only the human can produce.
- 2026-10-09 - The 2.2.0 and 2.3.0 sandbox matrices (launcher `-Wait`, auto-close, trust, models) were never committed; only `dev/test_gate_spec.py` (2.4.0) can be re-run. Reopen with the `tests/` question of 3.0.0.
