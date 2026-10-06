# Known Issues

Errors, dead ends, and constraints of the AgentFlow template. Each entry: date, issue, when to look again.

- 2026-10-03 - Claude as Tester cannot be sandboxed on Windows: review isolation is detected after the attempt (attempt `error`), not prevented. Reopen if Claude Code gets a Bash sandbox on Windows.
- 2026-10-03 - `limitHit` is a text match ("usage limit", "rate limit", "quota") on the last 50 log lines; a task whose output mentions these words can be misread. Reopen if a tool reports limits in a structured way.
- 2026-10-03 - Runtime state is not committed: on a fresh clone `ledger.py set --status done` needs `gate.py verify` to run again.
- 2026-10-03 - `## Checks` commands run in PowerShell on Windows and `sh` elsewhere; a command written for another shell fails verify.
- 2026-10-03 - Antigravity IDE cannot be automated: its attempts are `-Manual` and end with `-MarkFinished`.
- 2026-10-06 - `-Wait` wakes the Orchestrator only while its session is open; a closed session sees finished tasks at the next start. 2.2.0 is verified in a sandbox with placeholder processes, not yet with real codex / claude / agy windows (Stage 3 pilot). Reopen after the pilot.
- 2026-10-06 - Shell heredocs on Windows mangle backslash escapes (`\t`, `\b`, `\a`) and Cyrillic when used to edit files: edit with the editor tool or a script file instead.
