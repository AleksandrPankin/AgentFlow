# Session Handoff

## As of

2026-10-07, `main@2749d7e` (2.1.0); `release/2.3.0` holds 2.2.0 and 2.3.0. `refactor/fpf-audit` and `fix/launcher-defects` are merged into `main`.

## Goal

Keep AgentFlow small while its rules are enforced by the tools, not only written down.

## Verified state

- 2.0.0 (P0-P4) and 2.1.0 (dashboard) are on `main`: `git branch --merged main`, `CHANGELOG.md`.
- Launcher, gate, and ledger checked in a throwaway sandbox repository for 2.0.0. Not yet run with the real codex / claude / agy CLIs.
- 2.2.0 (wake on worker finish, closing agy, folder trust) and 2.3.0 (model and effort per task, `-Limits`) on branch `release/2.3.0`: sandbox matrices pass (placeholder processes; real launcher with fake CLIs). Not merged; real CLIs not yet run.

## Assumptions

- Projects run on Windows with PowerShell 7 and Python 3.

## Open problems

- See `state/known-issues.md` and section 9 of `state/plan-2.2-3.0.md`.
- Open discussion: optional stall detector (fast classifier on a silent worker's log tail) for `-Wait`. Waiting for the human: how often workers hung on a question in Calbot / web-3d, and whether project logs may go to an external service. Decide after the Stage 3 pilot.
- Reminder for the human: ask the colleague where his `launch.ps1` and `tests/` come from (blocks 3.0.0 only).

## Files to read first

1. `docs/ai-handoff-protocol.md`
2. `state/current-step.md`
3. `state/plan-2.2-3.0.md`
4. `requests/` (local inbox from other projects' agents, git-ignored)
