# Session Log

Chronological log of work on the AgentFlow template.

## 2026-05-21

- Base AI Project Memory: protocol, handoff, current-step, decisions, known-issues, session-log.

## 2026-10-01

- Team layer: roles, Task Files, Task Ledger, `/start-role`, protocol sections "Roles and memory ownership", "Starting a role session", "Task lifecycle", "Planning levels", "Git rules", `AGENTS.md`, `roles/tool-routing.md`.

## 2026-10-02

- Launcher and ledger defects from migrating a live project fixed; preflight, `## Checks`, production opt-in added.

## 2026-10-03

- FPF audit of all files; refactor to 2.0.0 in five commits: P0 enforcement, P1 state and evidence, P2 rule order and contradictions, P3 template vs project, P4 English machine-facing text. Details: `CHANGELOG.md`, `state/decisions.md`.

## 2026-10-04

- 2.1.0: template-owned read-only dashboard (`dashboard/`), Russian interface, local server with Refresh; merged into `main`.

## 2026-10-06

- `requests/` (proposals from other projects' agents) git-ignored. Two Calbot requests, the human's messages, and a colleague's `.agentflow/` layout merged into `state/plan-2.2-3.0.md` (2.2.0 wake-up, 2.3.0 model per task, 3.0.0 one folder). Stage 2 closed; Stage 3 is now 2.2.0 and its pilot.
- 2.2.0: `-Wait`, `gate.py result`, auto-close of agy windows, agy folder trust, `-Cleanup`; sandbox matrix 30x stable. 2.3.0: `Model:` / `Effort:`, `tools/models.json` (verified against installed CLI help and vendor catalogs), `-Limits`. Both on `release/2.3.0`.

## 2026-10-07

- Discussed a fast classifier with confidence scores (TypeSafe "Jeff", OpenRouter jev-router, from a video the human shared): not for the template core; possible optional stall detector for `-Wait`, decided after the Calbot pilot. Note in `state/plan-2.2-3.0.md`, section 9.

## 2026-10-09

- The human's product-definition pack (9 files, `D:\OneDrive\AI\01_Templates\000_AI-First\`), research notes, an integration review, and a live project's `09_GAPS_REVIEW.md` / `state/owner-tasks.md` checked against FPF; findings and decisions in `state/plan-2.4.0.md`. The human decided: Russian docs with Latin IDs, non-blocking final word with owner tasks, Vision and Brief separate, `gate.py` check now, `templates/product/`, deploy through the platform project with the human's yes for production.
- 2.4.0 on `release/2.4.0` (from `release/2.3.0`, not committed yet): `templates/product/` (00-09), `templates/owner-tasks.md`, protocol sections "Owner tasks" and "Product definition", `Spec:` in Task Files, `gate.py spec` and preflight checks (sandbox matrix 28 cases pass), roles, GUIDE, README, CHANGELOG, decisions; Stage 5 added, 3.0.0 moved to Stage 6. Committed `5f74ce3`.
- Plans folded: `state/plan-2.2-3.0.md` and `state/plan-2.4.0.md` removed (in git at `5f74ce3`); 3.0.0, open questions, and later items in `state/plan-3.0.0.md`; the classifier decision of 2026-10-07 moved to `state/decisions.md`; Stage exit criteria written out in `docs/project-plan.md`. Committed `5ad3392`.
- The 2.4.0 sandbox matrix kept as `dev/test_gate_spec.py` (template-only folder `dev/`, 28 cases, passes from the repository). Committed `b6a8857`.
- FPF re-check of the whole template at `f8d7cd1` (local `FPF-Spec/`); eleven findings beyond P0-P4 and S1-S18, three confirmed in a sandbox. The human took 1-7, 10, 11: Vision / Brief ceiling, `APPROVED (OWN-###)`, priority list (`5ab2946`); Spec re-check in verify and stage, explicit main branch (`4f16568`); verify records committed, journal channel, trust-boundary known issue (`b055fe9`); label rule, decisions in date order (`02bd5d5`); merged branches deleted; Stage 4 marked current. Not taken: 8 (code check of the Orchestrator's commits), 9 (verify fails on self-written tests). `dev/test_gate_spec.py`: 46 cases pass, sandboxes now removed on Windows.
- One risk scale `Risk: low | risky | critical` (FPF has no criticality levels, only the demand to declare a scale): Tester proves tests fail without the change for risky / critical; critical needs an acceptance test task on another tool or model; preflight and verify check it. `dev/test_gate_spec.py`: 58 cases pass.
- A scratch check of the `.gitignore` rule created and then deleted `tasks/.runtime/` in the template folder; whether it existed before (it would be local, never committed) was not checked.
- `main` fast-forwarded to `53a7f01` (2.4.0) on disk, tag `v2.4.0`; nothing pushed. Found on GitHub: one fork, `vcherstar/AgentFlow`, 23 commits ahead with its own `.agentflow/` layout and tests (`docs/state/plan-next.md`).
- 3.0.0 on `release/3.0.0`: the human rejected two `docs` folders and an install script; the layout became `.agentflow/` (machine) and `docs/` (project knowledge), install by `.agentflow/install.md` modelled on the skill `integrate-memory`, new skill `integrate-agentflow` (user level, `~/.claude/skills/`). Files moved with `git mv` by a scratch script (one mapping for moves, relative links, and textual paths), two roots in `gate.py`, `ledger.py`, `run-task.ps1`, dashboard; blocks with markers in `AGENTS.md`, `CLAUDE.md`, `.gitignore`. Checks: `dev/test_gate_spec.py` 58 cases, launcher and dashboard smoke run in a throwaway project, links in 38 Markdown files.
