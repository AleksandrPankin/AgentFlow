# Session Handoff

## As of

2026-10-03, branch `refactor/fpf-audit` (not merged into main).

## Goal

Keep AgentFlow small while its rules are enforced by the tools, not only written down.

## Verified state

- 2.0.0 refactor done in five commits on `refactor/fpf-audit` (P0-P4); see `CHANGELOG.md`.
- Launcher, gate, and ledger checked in a throwaway sandbox repository: launch gate, `-Manual`, review isolation, end check, verify, ledger transitions, Stage check (all passed). Not yet run with the real codex / claude / agy CLIs.

## Assumptions

- Projects run on Windows with PowerShell 7 and Python 3.

## Open problems

- See `state/known-issues.md`.

## Files to read first

1. `docs/ai-handoff-protocol.md`
2. `state/current-step.md`
3. `CHANGELOG.md`
