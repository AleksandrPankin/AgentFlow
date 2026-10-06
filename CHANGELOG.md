# Changelog

What changed in each AgentFlow version. Why it changed: `state/decisions.md`. The version of an installed project: `AgentFlow version:` in its `AGENTS.md`.

## 2.2.0 - 2026-10-06

- `tools/run-task.ps1 -Wait [T-NNN,...] [-PollSec 30] [-TimeoutMin N] [-GraceSec 20]`: blocks until a task finishes and prints one line (`T-NNN finished: attempt=... result=... Change|Verdict|Deployment=...`); no model, no network. Exit 0 finished, 3 timeout, 4 nothing to wait for. The Orchestrator runs it in the host tool's background mode and is woken when it exits, instead of polling `-Status`.
- `tools/gate.py result T-NNN`: Result class by keyword from the last `## Result` heading at line start: `completed`, `incomplete` (no valid role field), `blocked`, `failed`, `none`. Tolerant of Markdown decoration; a pasted format line (`completed | blocked`) does not count; `formatOk` tells whether strict verify will read the same. `-Status` shows the class.
- Interactive tools (Antigravity CLI) keep their window after the work: `-Wait` closes it as `exited` once the Result has a stable Outcome (a Developer only with a clean worktree at `Change`), so `gate.py verify` passes without the human. `-Stop` records `exited` when a valid Outcome exists, `error` otherwise.
- Antigravity CLI folder trust: the launcher adds the worker folder to `trustedWorkspaces` before the start and removes it with the new `-Cleanup T-NNN` (automatic for tester checkouts); other entries and keys are kept. Override path: `AGENTFLOW_AGY_SETTINGS`.
- Protocol: Runtime state rule 3 (waiting, finished, classes, closing), Launching workers rule 4 (pre-approved folder), Git rules rule 6 (`-Cleanup`), lifecycle row `incomplete`. Roles: Orchestrator waits with `-Wait`; workers add the `Outcome:` line last. Tool routing: how each host waits. GUIDE: keep the Orchestrator session open while workers run.

Migration from 2.1.x: replace `tools/`, `docs/ai-handoff-protocol.md`, `roles/`, `GUIDE.md`. No Task File or ledger changes. Remove project-level interim watchers and manual trust steps (Calbot: `AGENTS.md`, Tool routing).

## 2.1.0 - 2026-10-04

- New template-owned `dashboard/`: a read-only view for the human built from the ledger, Task Files, and git (`python dashboard/build.py` -> `dashboard/out/index.html`, `out/graph.html`). Task table with filters over every axis, task card, Gantt, timeline, dependency, successor and check links. Interface in Russian (it is human-facing); ledger statuses are shown as Russian labels.
- `dashboard/serve.py`: local server with a Refresh button in the page header that rebuilds both pages; the dashboard is rebuilt on demand only.
- `dashboard/snapshot.py`: local versions of the dashboard sources with rollback; `dashboard/UI-RULES.md`: rules for changing the interface; `dashboard/README.md`: files and the data contract.
- Protocol: new section "Dashboard"; `dashboard/` added to the template-owned list. `.gitignore` gets `dashboard/out/` and `dashboard/versions/`.
- Orchestrator role: rebuild the dashboard when the human asks or a Stage closes.

Migration from 2.0.x: copy `dashboard/`, append the two `.gitignore` lines, replace `docs/ai-handoff-protocol.md` and `roles/orchestrator.md`. No Task File or ledger changes.

## 2.0.0 - 2026-10-03

- Tester review isolation: a disposable checkout of the `Verifies` commit; the launcher fails the attempt if the checked branch, worktree, or Task File changed. Codex is the first choice for Tester tasks.
- Every attempt goes through `tools/run-task.ps1`; `-Manual` gates and prepares sessions a human starts (Antigravity IDE, Deployer, live Tester on prod).
- Production approval: the human gives it in the Deployer session; the Deployer records `Approval: source=human target=prod sha=<SHA> at=<time>`.
- New `tools/gate.py`: preflight, end-of-attempt check, `verify` (acceptance evidence), `stage` (Stage check on the main branch).
- Attempt history in `tasks/.runtime/T-NNN.json`, one log per attempt; global launch lock.
- State families: Task state, Process state, Outcome, role result (Change / Verdict / Deployment), Stage state. Acceptance is the ledger transition `review -> done`, allowed only after a passing verify.
- `tools/ledger.py`: enforced transitions, `Updated` column, `done` needs a passing verify, `rejected` / `cancelled` need notes.
- Template and project separated: ownership list and install / update procedure in the protocol; the template's own `state/` and `docs/project-plan.md` are not copied; guide moved to `GUIDE.md`.
- Machine-facing instructions in English; human communication in Russian.

Migration from 1.x:

- Task File fields: `Checks: T-xxx, commit <SHA>` -> `Verifies: T-xxx @ <SHA>`; `Environment:` -> `Target:`; deployer `Deploys: <SHA>`; `Prod approved by human:` removed; section `## Environment setup` -> `## Setup`; section `## Review before merge` -> field `Independent check: tester | none - <reason>`.
- Result: `Status:` -> `Outcome: completed | blocked | failed` plus `Change:` (developer), `Verdict:` and `Criteria:` (tester), `Deployment:` (deployer).
- Ledger: `rework` -> `rejected` (successor in Notes); the `Updated` column is added automatically.
- Process states: `completed` -> `exited`, `failed` -> `error`.
- Stage status: `done` -> `closed`, `pending` -> `planned`; `Result:` -> `Exit criteria:`.
- Finish or re-issue open tasks after updating: a running 1.x attempt has no attempt history.

## 1.2.0 - 2026-10-02

- Launch preflight with project `## Preflight` deny / require rules, `## Checks` section, production opt-in through `AGENTFLOW_TARGET`.

## 1.1.0 - 2026-10-02

- Launcher and ledger defects found migrating a live project fixed.

## 1.0.0 - 2026-10-01

- Team layer: four roles, Task Files, Task Ledger, `/start-role`, tool routing, `tools/run-task.ps1`, `tools/ledger.py`, on top of the base AI Project Memory (2026-05-21).
