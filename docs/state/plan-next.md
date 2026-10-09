# Open items after 3.0.0

Template-owned working document (not copied into projects). 3.0.0 shipped: `.agentflow/CHANGELOG.md`, `docs/state/decisions.md`. The 3.0.0 plan is in git as `state/plan-3.0.0.md` at `53a7f01`; earlier plans at `5f74ce3`.

## 1. Pilot

The human installs AgentFlow 3.0.0 into NelliRadar (`D:\OneDrive\AI\TelegramBot\NelliRadar_bot`: `00_PRD/` 00-09, `docs/infra-requests.md`, `state/owner-tasks.md`, no AgentFlow yet) with the skill `integrate-agentflow`, works a few days, and brings feedback. It checks the install procedure (brownfield with moving `00_PRD/` to `docs/product/`), the launcher with the real CLIs and `-Wait`, models per task, the product layer, and the risk scale at once: Stages 3-6 of `docs/plan.md`.

## 2. Open questions

1. The fork `vcherstar/AgentFlow` (author Vladimir, 23 commits ahead of the GitHub `main` as of 2026-10-08) has its own `.agentflow/` layout, `install.py`, `paths.py`, `.agentflow/tests/` (11 test files), autonomous orchestration (`tick.py`, conductor), TypeSafe routing, and several repositories per memory; its versions 2.2.0-2.10.0 differ in content from ours. Probably the colleague whose `launch.ps1` and `tests/` were asked about: talk to the author before reusing anything (MIT, with attribution). If `tests/` comes in, `dev/test_gate_spec.py` moves there; the 2.2.0 and 2.3.0 launcher matrices were never committed (cases in `state/plan-2.2-3.0.md`, D3, at `5f74ce3`).
2. Should `-Cleanup` also remove the worktree and branch (today the Orchestrator does it by Git rule 6)?
3. Optional stall detector for `-Wait` (a fast classifier on a silent worker's log tail): decide after the pilot; needs from the human how often workers hung on a question, and whether project logs may go to an external service (decisions, 2026-10-07).
4. Push to GitHub after the pilot (the human's order of 2026-10-09: merge on disk, pilot, feedback); the public `main` is still `f3a8b0c` (2.1.0 without the Refresh button).
5. The skill `integrate-memory` stays a separate function (the human, 2026-10-09). The old template `ai-project-memory-pankin` stays where it is; moving it to `_templates/old/` was offered and not answered.

## 3. Later

- The platform project (04) names the deploy session per product project in its own contracts; it already reads the product projects' request files.
- Dashboard: owner tasks view; `Spec`, `Model`, and `Risk` columns if the data contract fits.
- Optional independent spec review by a fresh session before G2 / G3.
