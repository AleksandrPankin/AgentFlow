# Session Handoff

## As of

2026-10-09, `main@2749d7e` (2.1.0); `release/2.3.0` holds 2.2.0 and 2.3.0; `release/2.4.0` (from `release/2.3.0`) holds 2.4.0 (`5f74ce3`), the plan cleanup, `dev/test_gate_spec.py`, and the FPF re-check fixes (`5ab2946`, `4f16568`, `b055fe9`, `02bd5d5`). Nothing merged into `main` since 2.1.0.

## Goal

Keep AgentFlow small while its rules are enforced by the tools, not only written down. 2.4.0 adds the product definition layer and the owner task queue.

## Verified state

- 2.0.0 (P0-P4) and 2.1.0 (dashboard) are on `main`: `git branch --merged main`, `CHANGELOG.md`.
- 2.2.0 and 2.3.0 on `release/2.3.0`: their sandbox matrices passed on 2026-10-06 (`6f57e65`, `3e83936`), but the matrices were not kept and `gate.py` changed since, so this cannot be re-checked now. Real CLIs not yet run.
- 2.4.0 with the FPF re-check fixes: `python dev/test_gate_spec.py` passes 46 cases (spec lint, preflight, and verify, ledger, stage on a real worktree) at `02bd5d5`; relative links and anchors of all tracked Markdown resolve (38 files, scratch check). No end-to-end run with real tools.

## Files in flight

None; working tree clean after this memory update is committed. Changed this session: `tools/gate.py` (Vision / Brief ceiling, `APPROVED (OWN-###)`, priorities, Spec re-check in verify and stage, explicit main branch), `dev/test_gate_spec.py`, protocol, `templates/product/03`, `05`, `06`, `07`, `templates/owner-tasks.md`, `.gitignore` (verify records committed), GUIDE, CHANGELOG 2.4.0 (bullets and migration), decisions (date order), known-issues. Merged branches `fix/launcher-defects` and `refactor/fpf-audit` deleted; `backup/old-history` kept (not merged).

## Assumptions

- Projects run on Windows with PowerShell 7 and Python 3; `dev/test_gate_spec.py` needs Python 3.12+ (`rmtree` `onexc`).

## Open problems

- See `state/known-issues.md` and `state/plan-3.0.0.md`, sections 2-3.
- The human copies the 2.4.0 layer into a live project by hand and brings feedback; live projects run older AgentFlow versions (check `AgentFlow version` before judging feedback). The 2.4.0 migration now also asks for `APPROVED (OWN-###)`, FR / NFR priorities, the Vision / Brief status, and the `.gitignore` change.
- The platform project (04) still names deploy sessions per project in its own contracts; it reads the product projects' request files already.
- Reminder for the human: ask the colleague where his `launch.ps1` and `tests/` come from (blocks 3.0.0 only).

## Files to read first

1. `docs/ai-handoff-protocol.md`
2. `state/current-step.md`
3. `state/plan-3.0.0.md`
4. `requests/` (local inbox from other projects' agents, git-ignored)
