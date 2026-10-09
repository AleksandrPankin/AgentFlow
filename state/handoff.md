# Session Handoff

## As of

2026-10-09, `main@2749d7e` (2.1.0); `release/2.3.0` holds 2.2.0 and 2.3.0; `release/2.4.0` (from `release/2.3.0`) holds 2.4.0 (`5f74ce3`) and the plan cleanup.

## Goal

Keep AgentFlow small while its rules are enforced by the tools, not only written down. 2.4.0 adds the product definition layer and the owner task queue.

## Verified state

- 2.0.0 (P0-P4) and 2.1.0 (dashboard) are on `main`: `git branch --merged main`, `CHANGELOG.md`.
- 2.2.0 and 2.3.0 on `release/2.3.0`: sandbox matrices pass (placeholder processes, fake CLIs). Real CLIs not yet run.
- 2.4.0: `gate.py spec` and the Product definition preflight pass a 28-case sandbox matrix (the script was a session scratch file; the cases are in `state/plan-2.4.0.md`, section 6, at `5f74ce3`); relative links and anchors of all Markdown resolve. No end-to-end run with real tools.

## Files in flight

None. `state/plan-2.2-3.0.md` and `state/plan-2.4.0.md` were folded into `state/plan-3.0.0.md` (3.0.0, open questions, later items) and removed; both stay in git at `5f74ce3`.

## Assumptions

- Projects run on Windows with PowerShell 7 and Python 3.

## Open problems

- See `state/known-issues.md` and `state/plan-3.0.0.md`, sections 2-3.
- The human copies the 2.4.0 layer into a live project by hand and brings feedback; live projects run older AgentFlow versions (check `AgentFlow version` before judging feedback).
- The platform project (04) still names deploy sessions per project in its own contracts; it reads the product projects' request files already.
- Reminder for the human: ask the colleague where his `launch.ps1` and `tests/` come from (blocks 3.0.0 only).

## Files to read first

1. `docs/ai-handoff-protocol.md`
2. `state/current-step.md`
3. `state/plan-3.0.0.md`
4. `requests/` (local inbox from other projects' agents, git-ignored)
