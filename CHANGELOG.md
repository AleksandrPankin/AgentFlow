# Changelog

What changed in each AgentFlow version. Why it changed: `state/decisions.md`. The version of an installed project: `AgentFlow version:` in its `AGENTS.md`.

## 2.4.0 - 2026-10-09

- Product definition (optional, active when `docs/product/00_INDEX.md` exists): new `templates/product/` with Vision, Brief, PRD, Architecture (`AR01`-`AR10`, ADRs in `decisions/`), readiness review `09_REVIEW.md` (the agent's report for the human), and explanations for the human `05`-`08` (gates, authority, document rules, traceability example). Russian content, Latin IDs and statuses. Protocol: new section "Product definition" (files, item format, Spec status `DRAFT` / `PROPOSED` / `APPROVED` / `STALE` / `SUPERSEDED`, gates G0-G5 per Stage, Change Impact, reading by ID).
- Owner tasks: `state/owner-tasks.md` (skeleton `templates/owner-tasks.md`), `OWN-###`, one action per task, journal of the human's answers. The human's word does not block the work, except the blocking list (keys and accounts, production deploy, server change, money beyond budget, new external access or personal data, irreversible action, feature outside the MVP). Protocol: new section "Owner tasks"; States rows "Spec status" and "Owner task".
- Task File: `Spec: <IDs> | none - <reason> | spike - <Q-ID>`; `Read first` entries `<file> - <IDs>` (the worker reads only those sections); criteria cite their `AC-###`.
- `tools/gate.py spec`: duplicate IDs, invalid statuses, Must FR without AC, AC without FR, status counts; an FR / NFR priority other than `Must | Should | Could | Won't | Later` is an error (a mistyped `Must` is no longer read as "not Must"); `APPROVED` names the owner task that approved it, `APPROVED (OWN-###)`, and that task is `[x]` in `state/owner-tasks.md`; an implementable item while Vision or Brief is `DRAFT` / `STALE` is an error. Preflight with Product definition: a developer task needs `Spec:`; every item exists and is `PROPOSED` or `APPROVED`, never above the front matter status of Vision and Brief (weakest link); no `Allowed files` under `docs/product/`. Without `docs/product/` preflight is as in 2.3.0. Regression check: `python dev/test_gate_spec.py` (`dev/` is template-only).
- `gate.py verify` re-checks a developer task's `Spec:` items (a spec changed during the attempt fails acceptance); `gate.py stage` fails on a `STALE` item named by a Stage task. Preflight, verify, and stage need the main folder on `main` / `master`; "the main branch" is now that branch, not whatever is checked out (also for the merge checks of a live Tester and the Deployer).
- One risk scale: a developer task names `Risk: low | risky | critical` by what its failure costs (protocol, Task lifecycle, Flow 1); it replaces the separate "risky change" lists of the protocol and Tool routing. `risky` and `critical` need `Independent check: tester`, and the Tester proves the tests fail without the change (`Tests without the change: fail | pass | n/a - <reason>`; `pass` there is never `Verdict: pass`, checked by verify). `critical` needs `Acceptance test: T-xxx`: a done developer task on another tool or model wrote the test, and its files are in `Do not touch` (checked by preflight; verify already refuses changes outside `Allowed files`).
- Verify records `tasks/.runtime/T-NNN.verify.json` are committed with the ledger: an accepted task keeps its evidence after a clone; attempts and logs stay local. Owner journal: column `Канал` (`file`: the human wrote it; `chat`: moved by the Orchestrator, quoted verbatim).
- Deploy: the Deployer is an agent session of the platform project named in Project rules `## Deploy`; the Orchestrator requests the deploy; staging without the human when no server changes; production keeps the human's yes in that session.
- Roles: Results get `Proposed spec changes:` and `Needs owner:`; the Orchestrator runs the gates, opens owner tasks instead of waiting, records answers in the journal. `AGENTS.md`: a worker reads only the sections "Starting a role session" names. GUIDE: product before development, tasks for the human, deploy.

Migration from 2.3.x: in `.gitignore` replace the line `tasks/.runtime/` with `tasks/.runtime/*` and `!tasks/.runtime/*.verify.json` (a folder rule cannot be re-included), then commit the existing verify records; add the column `Канал` to the owner journal; replace `AGENTS.md` above `## Project rules`, `docs/ai-handoff-protocol.md`, `roles/`, `tasks/_template.md`, `tools/`, `GUIDE.md`; copy `templates/owner-tasks.md` to `state/owner-tasks.md` if absent (a project with its own owner queue keeps it and adopts the format). Add `## Deploy` to Project rules if the project is deployed. Product definition: copy `templates/product/` to `docs/product/` only when the human wants it; a project that already keeps such documents elsewhere moves them to `docs/product/`, renames Architecture sections `T01`-`T10` to `AR01`-`AR10`, adds `- **Статус:**` lines to FR, NFR, ADR and `- **Приоритет:**` to FR, NFR, writes `APPROVED (OWN-###)` with the owner task that holds the human's answer, and sets the Vision / Brief front matter `status` (items under a `DRAFT` Brief are not implementable). Open developer Task Files get a `Risk:` line before their next launch (preflight refuses one without it); new developer tasks in a project with `docs/product/` need `Spec:`. Dashboard unchanged.

## 2.3.0 - 2026-10-06

- Task File fields `Model: default | small | standard | strong | <id>` and `Effort: default | low | medium | high | xhigh | max`. New `tools/models.json` maps tiers to each tool's model and lists the accepted ids and efforts (`verifiedAt`); per-machine override `AGENTFLOW_MODEL_<TOOL>_<TIER>`. No model id in the scripts.
- Launcher passes the tool's own flags (claude `--model` / `--effort`, codex `-m` / `-c model_reasoning_effort=...` replacing the same keys in `AGENTFLOW_CODEX_ARGS`, agy `--model` / `--effort`); absent or `default` = no flag, the command line as in 2.2.0. The resolved model and effort are recorded per attempt and shown in the launch line and `-Status`.
- Preflight refuses an unknown tier, an id the table does not list for the launch tool, an unknown effort, or an effort on a model without one (Haiku 4.5), with the valid values.
- `run-task.ps1 -Limits`: the last usage-limit hit per tool with its log line (`limitText`, usually the reset time).
- Tool routing: section "Choosing the model" (tier table, task kinds, rules, sources). Protocol: Launching workers rule 6 (the model is part of the launch). Orchestrator fills `Model:` and `Effort:`. GUIDE: how tiers and overrides work.

Migration from 2.2.x: copy `tools/` (with `models.json`), `roles/`, `tasks/_template.md`, `docs/ai-handoff-protocol.md`, `GUIDE.md`. Existing Task Files need no change (no `Model:` line = as before).

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
