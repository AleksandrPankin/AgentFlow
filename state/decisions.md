# Decision Log

Decisions about the AgentFlow template itself: why, and what was rejected. What changed per version: `CHANGELOG.md`. Add new decisions below; do not delete old ones without a reason.

## 2026-05-21

### AI Project Memory

Decision: baseline memory files: protocol, handoff, current-step, decisions, known-issues, session-log.

Why: long AI sessions lose context, repeat old errors, and forget why decisions were made. A short handoff is the entry point; details live in specialized files.

## 2026-10-04

### Dashboard is template-owned, in `dashboard/` beside `tools/`

Decision: the human's read-only view (built from the ledger, Task Files, git) ships with the template as `dashboard/`, Russian interface (it is for the human; machine-facing files stay English), statuses mapped from the protocol's ledger words. Only sources are committed; `out/` and `versions/` are git-ignored. Local versioning (`snapshot.py`) stays so the dashboard can be changed and rolled back.

Why: it was crystallized on one real project and the entities and flow are the same in every AgentFlow project. `tools/` is for agents; this is for the human, so a separate folder. Rejected: shipping built pages (they are project data, not template).

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

### Wake the Orchestrator with a blocking command, not a model loop (2026-10-06)

Decision: `run-task.ps1 -Wait` blocks in the shell and exits at the first finished task with one line; the Orchestrator runs it in the host's background mode (Claude Code `run_in_background`). Finished = process ended, or for interactive tools and manual attempts a valid `Outcome:` stable for a grace period. The launcher closes a finished interactive window as `exited`; a Developer only with a clean worktree at `Change`.

Why: an idle chat session never reacted to finished workers, and the human became the dispatcher (Calbot T-001). Rejected: self-paced polling (a full model turn per tick), worker-to-Orchestrator messages (Claude-only), waiting for the human to type `/exit`.

### Result read by keyword for waking, strictly for acceptance (2026-10-06)

Decision: `gate.py result` reads `Outcome` and the role field tolerantly from the last `## Result` heading; `gate.py verify` stays strict. The difference is reported (`format=loose`).

Why: workers decorate fields (`**Outcome:** Completed.`) and quote the heading; a strict reader never woke (Calbot), a tolerant verify would weaken the evidence.

### The launcher owns Antigravity folder trust (2026-10-06)

Decision: add the worker folder to `trustedWorkspaces` before an `agy` launch, remove it with `-Cleanup` (testers: automatically), edit the JSON node-wise and atomically.

Why: the trust prompt for every new worktree blocked unattended runs, and the list grew forever. Rejected: trusting the parent `<worktrees>` folder (Antigravity matches exact paths only).

### Model per task as a tier, resolved by one table (2026-10-06)

Decision: Task Files name `Model: small | standard | strong` (or a listed id) and `Effort:`; `tools/models.json` maps them per tool, an env variable overrides per machine, preflight refuses what the table does not list, the attempt records what ran. No `Model:` line = no flag.

Why: workers ran on whatever the user-level settings said, unrecorded, and the Orchestrator had no cost lever (Calbot). A tier survives model releases; one table changes, not every Task File. Rejected: model ids in Task Files by default (stale on every release), ids in the script.
