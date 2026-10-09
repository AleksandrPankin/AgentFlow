# Session Handoff

## As of

2026-10-09. `main` = 3.0.0 on disk (fast-forward from `release/3.0.0`), tags `v2.4.0` and `v3.0.0`; pushed to GitHub (`main` and both tags).

## Goal

Keep AgentFlow small while its rules are enforced by the tools. 3.0.0 splits every project into `.agentflow/` (the machine, replaced as a whole on update) and `docs/` (the project's knowledge, never touched by an update), and installs by an LLM procedure instead of copying.

## Verified state

- `python dev/test_gate_spec.py`: 58 cases pass on the 3.0.0 layout (spec lint, preflight with `Spec:` and `Risk:`, verify, ledger, stage, tester verify on a real worktree).
- Launcher smoke run in a throwaway 3.0.0 project: `run-task.ps1` parses, `-Manual` creates the worktree and `docs/tasks/.runtime/T-001.json`, `-Status`, `-MarkFinished`, `dashboard/build.py` writes `out/`.
- `.gitignore` block: only `*.verify.json` of `docs/tasks/.runtime/` is visible to git (checked with temporary files).
- Relative links and anchors of all 38 tracked Markdown files resolve (scratch check).
- Not verified: `install.md` and the skill `integrate-agentflow` on a real project; the real CLIs (codex, claude, agy) with `-Wait`.

## Files in flight

None after this commit. Changed this session: everything moved into `.agentflow/` or `docs/` (see `.agentflow/CHANGELOG.md` 3.0.0); new `.agentflow/install.md`; new user-level skill `C:\Users\pankin\.claude\skills\integrate-agentflow\SKILL.md` (outside this repository); `docs/state/plan-3.0.0.md` became `docs/state/plan-next.md`.

## Assumptions

- Projects run on Windows with PowerShell 7 and Python 3; `dev/test_gate_spec.py` needs Python 3.12+.

## Open problems

- `docs/state/known-issues.md` and `docs/state/plan-next.md` (the fork `vcherstar/AgentFlow`, `-Cleanup`, stall detector).
- Live projects run 2.x or no AgentFlow; check `AgentFlow version` before judging feedback.

## Files to read first

1. `.agentflow/protocol.md`
2. `docs/state/current-step.md`
3. `docs/state/plan-next.md`
4. `requests/` (local inbox from other projects' agents, git-ignored)
