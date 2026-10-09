# Decision Log

Decisions about the AgentFlow template itself: why, and what was rejected. What changed per version: `CHANGELOG.md`. Add new decisions below; do not delete old ones without a reason.

## 2026-05-21

### AI Project Memory

Decision: baseline memory files: protocol, handoff, current-step, decisions, known-issues, session-log.

Why: long AI sessions lose context, repeat old errors, and forget why decisions were made. A short handoff is the entry point; details live in specialized files.

## 2026-10-01

### Team roles and single memory writer

Decision: four roles, Task Files in `tasks/`, Task Ledger `state/tasks.md`. In Team Mode only the Orchestrator writes Canonical Memory; workers write only their Result.

Why: several sessions updating handoff and current-step in parallel create conflicting versions of project state. Workers need their role and task, not the whole history.

### One task = one branch + one worktree, mandatory cleanup

Decision: each developer task gets branch `t-NNN-slug` and a worktree outside the repository and cloud sync; the main folder stays on the main branch and belongs to the Orchestrator; after merge the Orchestrator removes the worktree and the branch.

Why: on an earlier project 36 of 37 task branches with worktrees merged; the real problem was 33 merged worktrees left behind. Rejected: a no-worktree rule (loses parallel work).

### Tool routing by fit and budget

Decision: the Orchestrator picks the tool per task from `roles/tool-routing.md` and the limits the human reports; the choice is written in the Task File and ledger.

Why: tools differ in strengths and token cost; spending the most capable tool on mechanical work wastes limits.

## 2026-10-03

Context: an audit against the First Principles Framework (FPF) found rules that the scripts did not enforce, overloaded status words, evidence that was overwritten, and template history mixed into project memory. FPF was used as a reference, not as a target: a principle was applied only where it fixed a concrete defect.

### Enforcement before prose

Decision: prefer code enforcement, then structured fields, then one canonical rule; no rule repeated across files.

Why: every audit defect of the form "the text says X, the tool does Y" came from a rule that existed only as prose. Rejected: more prompt instructions (more tokens, same gap).

### Review isolation instead of "read-only Tester"

Decision: the Tester works in a disposable checkout of the checked commit; the launcher compares the checked branch, worktree, and Task File before and after the attempt. Codex (sandboxed) is the first choice; Claude is a fallback guarded only by the end check.

Why: the Tester needs write access for test runs and its Result, so "read-only" could not be true; what matters is that it cannot change the artifact that is then accepted. Rejected: Tester only on Codex (no fallback when its limit ends).

### Production approval stays in the Deployer session

Decision: the Deployer asks the human in its own designated session and records `source=human target sha at`; the Orchestrator is not in the chain.

Why: an approval relayed by the Orchestrator was a record it could write itself. Rejected: an `approve.ps1` record file (an agent with a shell can write the file as well).

### Acceptance as an event, separate state families

Decision: one owner and one vocabulary per family (Task state, Process state, Outcome, role result, Stage state); acceptance is the ledger transition `review -> done`, allowed by `ledger.py` only after a passing `gate.py verify`. No separate "Decision" status.

Why: `done`, `failed`, `blocked` meant different things in five places. Rejected: a common `Claim` result for all roles (Developer, Tester, and Deployer produce different results).

### Pure logic in Python, side effects in PowerShell

Decision: `tools/gate.py` parses Task Files and runs preflight, end check, verify, and the Stage check; `tools/run-task.ps1` creates worktrees and checkouts and runs processes.

Why: with verify and attempt history the launcher would have become parser, verifier, state machine, and evidence store at once; Python logic is easier to test and is shared with `ledger.py`.

### Template-owned vs project-owned files

Decision: ownership list and install / update procedure in the protocol; `AgentFlow version` in `AGENTS.md`; the template's own `state/` and `docs/project-plan.md` are never copied; project tool notes live in Project rules.

Why: projects inherited template history as their own decisions, and updating `roles/` overwrote project edits in `tool-routing.md`.

### Language

Decision: machine-facing files in English; communication with the human in Russian, generated from the canonical rule, never stored as a second copy.

Why: Russian text costs about twice the tokens of English, and two copies of a rule drift apart.

## 2026-10-04

### Dashboard is template-owned, in `dashboard/` beside `tools/`

Decision: the human's read-only view (built from the ledger, Task Files, git) ships with the template as `dashboard/`, Russian interface (it is for the human; machine-facing files stay English), statuses mapped from the protocol's ledger words. Only sources are committed; `out/` and `versions/` are git-ignored. Local versioning (`snapshot.py`) stays so the dashboard can be changed and rolled back.

Why: it was crystallized on one real project and the entities and flow are the same in every AgentFlow project. `tools/` is for agents; this is for the human, so a separate folder. Rejected: shipping built pages (they are project data, not template).

## 2026-10-06

### Wake the Orchestrator with a blocking command, not a model loop

Decision: `run-task.ps1 -Wait` blocks in the shell and exits at the first finished task with one line; the Orchestrator runs it in the host's background mode (Claude Code `run_in_background`). Finished = process ended, or for interactive tools and manual attempts a valid `Outcome:` stable for a grace period. The launcher closes a finished interactive window as `exited`; a Developer only with a clean worktree at `Change`.

Why: an idle chat session never reacted to finished workers, and the human became the dispatcher (Calbot T-001). Rejected: self-paced polling (a full model turn per tick), worker-to-Orchestrator messages (Claude-only), waiting for the human to type `/exit`.

### Result read by keyword for waking, strictly for acceptance

Decision: `gate.py result` reads `Outcome` and the role field tolerantly from the last `## Result` heading; `gate.py verify` stays strict. The difference is reported (`format=loose`).

Why: workers decorate fields (`**Outcome:** Completed.`) and quote the heading; a strict reader never woke (Calbot), a tolerant verify would weaken the evidence.

### The launcher owns Antigravity folder trust

Decision: add the worker folder to `trustedWorkspaces` before an `agy` launch, remove it with `-Cleanup` (testers: automatically), edit the JSON node-wise and atomically.

Why: the trust prompt for every new worktree blocked unattended runs, and the list grew forever. Rejected: trusting the parent `<worktrees>` folder (Antigravity matches exact paths only).

### Model per task as a tier, resolved by one table

Decision: Task Files name `Model: small | standard | strong` (or a listed id) and `Effort:`; `tools/models.json` maps them per tool, an env variable overrides per machine, preflight refuses what the table does not list, the attempt records what ran. No `Model:` line = no flag.

Why: workers ran on whatever the user-level settings said, unrecorded, and the Orchestrator had no cost lever (Calbot). A tier survives model releases; one table changes, not every Task File. Rejected: model ids in Task Files by default (stale on every release), ids in the script.

## 2026-10-07

### No classifier model in the template core

Decision: Result detection, preflight, and tier choice stay deterministic, free, and offline. A fast classifier with confidence scores (TypeSafe "Jeff", OpenRouter `typesafe/jev-router`, OpenAI Decisions API, from a video the human shared; claims not verified) is not taken. Possible later: an optional stall detector for `-Wait` on a silent worker's log tail, or an advisory guard on `## Checks` commands, never instead of the deny rules.

Why: the workers are CLI subscriptions, not OpenRouter; the router picks the cheapest adequate model, which conflicts with "strong" for risky code. Better fit: classification inside a product (for example message routing), decided in that project.

## 2026-10-09

Context: the human added a product definition layer (Vision, Brief, PRD, Architecture, gates, authority, document rules) drafted outside the template, plus field evidence from a live project (an owner task queue with an answer journal; the owner started a slice before its gates were approved). Checked against FPF (A.7, A.2.6, A.2.9, A.6.B, A.10, A.16, B.3.4, C.16, E.17, F.17) before integration; plan and findings: `state/plan-2.4.0.md` in git at `5f74ce3` (removed afterwards; open items in `state/plan-3.0.0.md`).

### Product definition is optional and lives in `docs/product/`

Decision: active only when `docs/product/00_INDEX.md` exists; skeletons in `templates/product/`, copied once, then project-owned. Process rules are stated once in the protocol; `05`-`08` are Russian explanations for the human, template-owned, updated in the same commit as the protocol section; agents read them only when asked.

Why: projects without product docs (brownfield, small tools) must keep working as before; per-project copies of process rules drift from the protocol. Rejected: copying `05`-`07` as project rules (two sources of one rule); merging Vision and Brief into one file (G0 and G1 are separate decisions).

### The human's word is final but non-blocking

Decision: agents run the gates, set items `PROPOSED` (implementable), and open an owner task; `APPROVED` only from the human's answer in the owner journal. The work waits for the human only on the blocking list.

Why: the human did not want to be the bottleneck; a late "not OK" costs rework, which the human accepted. Rejected: G0-G3 approval before any task (the live project skipped it in practice); owner tasks as Task Files with `Role: human` (launch, verify, `-Wait`, and the Stage check are worker machinery; a human act is not a worker's Work).

### One place per fact in the product layer

Decision: the gate register only in `00_INDEX.md`; the human's answers only in the owner journal; FR priority only in the FR block; AC points to its FR, not the reverse; no change-history tables (git); Architecture sections `AR01`-`AR10` (no clash with `T-NNN`); slice = Stage; a task links items through `Spec:`, never copies them.

Why: the draft stored approval in four places and status in two, which FPF A.10 / SSOT reading flagged as drift risk.

### Spec items are checked by code

Decision: `gate.py spec` lints items; preflight refuses a developer task without `Spec:` or with an item that is missing or not `PROPOSED` / `APPROVED`, and any `Allowed files` under `docs/product/`.

Why: enforcement before prose (2026-10-03). Rejected: deferring the check until after a pilot.

### Deploy through the platform project

Decision: the Deployer is an agent session of the platform project named in Project rules `## Deploy`; the Orchestrator requests; staging without the human when no server changes; production keeps the human's yes in that session (supersedes only the "session the human designated" part of the 2026-10-03 decision).

Why: the human's projects already deploy through one platform project with contract scripts. Considered and rejected by the human: production without a yes when a recomputed git-diff risk check is clean.

### Regression checks of the template's tools are committed in `dev/`

Decision: a sandbox matrix written for a release is kept as a script in `dev/` (template-only, never copied into projects), runnable without arguments; first one `dev/test_gate_spec.py`. If a `tests/` folder comes in with 3.0.0, the scripts move there.

Why: the 2.2.0 and 2.3.0 matrices lived only in a session's scratch folder and were lost; a later change to `gate.py` (the 3.0.0 path split) would have nothing to re-run. Rejected: waiting for the `tests/` decision (the script would be gone by then).

### Template working plans are deleted when their release is committed

Decision: one open plan file at a time (`state/plan-3.0.0.md`); a finished release's plan is removed after its commit, its result already in `CHANGELOG.md` and this file; the old plan stays in git history.

Why: two plans with finished sections next to open ones made it unclear what was still to do.
