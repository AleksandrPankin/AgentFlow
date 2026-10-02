# AI Project Memory Protocol

Purpose: preserve project context during long AI-assisted work, across any tool (Claude Code, Codex, ChatGPT, Cursor) and across sessions — for one session or a team of role sessions.

This file is the single source of truth. Tool-specific entry points (`.claude/commands/*.md`, Codex `@`-references, custom prompts) and role files (`roles/*.md`) point here by section name instead of repeating rules. If a rule needs to change, change it here once.

## Terms

Memory:

- AI Project Memory - project files that preserve state between AI sessions.
- Canonical Memory - the official project state: everything in `state/`, `docs/project-plan.md`, `runbook/`. Has one writer, see [Roles and memory ownership](#section-roles-and-memory-ownership).
- Session Handoff - short transfer note in `state/handoff.md`.
- Current Step - current practical next action in `state/current-step.md`.
- Decision Log - decisions and reasons in `state/decisions.md`.
- Known Issues - failures, dead ends, false leads, and constraints in `state/known-issues.md`.
- Session Log - chronological work log in `state/session-log.md`.
- Clean Runbook - verified repeatable instructions in `runbook/`.
- Screenshots - manually saved visual evidence and tutorial images in `screenshots/`.

Team:

- Single Mode - a session started without a role. Does the work and writes Canonical Memory itself.
- Team Mode - sessions started with a role via [Starting a role session](#section-starting-a-role-session).
- Role - how one kind of session works, in `roles/`:
  - Orchestrator - [roles/orchestrator.md](../roles/orchestrator.md). Splits goals into tasks, accepts results, the only writer of Canonical Memory in Team Mode.
  - Developer - [roles/developer.md](../roles/developer.md). Worker. Changes code for one task.
  - Tester - [roles/tester.md](../roles/tester.md). Worker. Verifies one task, read-only.
  - Deployer - [roles/deployer.md](../roles/deployer.md). Worker. Deploys one accepted commit.
- Worker - Developer, Tester, or Deployer.
- Task File - one unit of work for one worker: `tasks/T-NNN-slug.md`, created by the Orchestrator from [tasks/_template.md](../tasks/_template.md).
- Result - the `## Result` section at the end of a Task File. Written by the worker who did the task. Format is defined in that worker's role file.
- Task Ledger - [state/tasks.md](../state/tasks.md): one row per task with its status. Part of Canonical Memory.
- Stage - one roadmap step in `docs/project-plan.md`. Each task belongs to one Stage.
- Tool Routing - [roles/tool-routing.md](../roles/tool-routing.md): which tool (Claude Code, Codex CLI, Antigravity) gets which task. Read by the Orchestrator only.
- Project rules - the project's own code and run rules: `docs/engineering-rules.md`, or the part of `AGENTS.md` under the heading `## Project rules`. Either place is valid; a template update never overwrites them. They name the `<worktrees>` folder and may hold a `## Preflight` section ([Launching workers](#section-launching-workers), rule 9).
- Checks - the `## Checks` section of a Task File: the exact commands that prove the Acceptance criteria. Workers run them verbatim; acceptance runs the same commands.

## What goes where

- `state/handoff.md` - short context handoff for the next AI session.
- `state/current-step.md` - only the current practical step.
- `state/session-log.md` - chronological work history, including useful intermediate events.
- `state/known-issues.md` - mistakes, failed attempts, dead ends, false hypotheses, and constraints.
- `state/decisions.md` - important decisions and why they were made.
- `state/tasks.md` - Task Ledger: task IDs, roles, statuses, commits. Edit it with `python tools/ledger.py`, not with one-off scripts.
- `tools/` - launcher and ledger scripts. Same in every project.
- `docs/project-plan.md` - living roadmap: stages, status, what comes next.
- `runbook/clean-instruction.md` or a project-specific file in `runbook/` - only verified steps that led to the result.
- `screenshots/` - screenshots that can be linked from the runbook.
- `roles/` - role files and tool routing. Same in every project; change only to fix the role itself.
- `tasks/` - Task Files and `_template.md`.

### Planning levels

Four files describe "where we are" at different zoom levels. Each level links down, never copies:

| File | Level | Horizon | Answers | Example |
|---|---|---|---|---|
| `docs/project-plan.md` | Stage | weeks | Where are we going, what result closes the stage | "Stage 2: user login" |
| `state/tasks.md` | Task | hours | Who does which piece of the current stage, status | "T-104, developer, Stage 2, in progress" |
| `state/current-step.md` | Next action | now | What exactly to do next | "When T-104 is done, give T-105 to tester" |
| `state/handoff.md` | Snapshot | one session | Where the last session stopped, what to read first | links to the three above |

- The plan does not list tasks. Tasks point to their Stage (column `Stage`).
- current-step does not copy the ledger. It names the next action and refers to task IDs.
- handoff does not repeat plan, tasks, or current-step. It links to them.
- A Stage is done when all its tasks are `done` and the Stage result is checked. Then the plan is updated.
- Single Mode: the ledger is optional; current-step works as before.

## Standing rules

Apply to every session and every role. Based on the Karpathy guidelines: think before coding, simplicity first, surgical changes, goal-driven execution.

Rule hierarchy: Standing rules and Git rules in this file > role file > Task File. Lower levels add specifics; they cannot cancel or weaken higher ones. Exception: an explicit instruction from the human.

- Inspect relevant project files before making assumptions or asking questions.
- If a request is unclear or has several readings, state your assumptions or ask. Do not pick silently.
- Prefer the smallest change that satisfies the request. No speculative features, abstractions, or configurability.
- Change only files and lines required by the task. Preserve existing style and unrelated user work.
- Clean up only unused code introduced by your own change.
- Before work, define how success will be checked (test, command, screenshot). Work is done when the check passes.
- Never write passwords, tokens, private keys, recovery codes, cookies, or other secrets to Markdown.
- Do not invent screenshots or files. Link a screenshot only if it already exists in `screenshots/`.
- Do not repeat failed attempts listed in `state/known-issues.md`.

## Section: Roles and memory ownership

**Single Mode** (no role): you follow every section of this file yourself, including writing Canonical Memory.

**Team Mode**:

| | Orchestrator | Developer | Tester | Deployer |
|---|---|---|---|---|
| Read code and memory | yes | yes | yes | yes |
| Write Canonical Memory, `tasks/` | **only writer** | no | no | no |
| Write own Result | - | yes | yes | yes |
| Change product code | no | yes, within Allowed files | no | no |
| Commit | memory and `tasks/` only | 1 commit per task | no | no |
| Merge | yes, after acceptance | no | no | no |
| Deploy, server, production | no | no | read-only checks | yes, prod with human approval |

Rules:

1. Workers never run [Updating memory](#section-updating-memory), [Handoff](#section-handoff-short-transfer-note), or [Updating the runbook](#section-updating-the-runbook). They put suggestions in `Proposed memory updates` of their Result. The Orchestrator decides what goes into Canonical Memory.
2. One task = one fresh session. Do not reuse a chat for the next task.
3. Tasks that run in parallel must not share any file in Allowed files. Each developer task works in its own worktree (see [Git rules](#section-git-rules)), so parallel tasks in one repository are fine when their files do not overlap.
4. A worker that cannot continue sets Result status `blocked` with the question and stops. It does not guess and does not widen the task.
5. Workers do not launch sub-agents, sub-models, or parallel agents. Only the Orchestrator decides what runs in parallel, as separate sessions.
6. Results are short: status, branch, commit, checks, findings. No reports about internal tools or token usage.

## Section: Git rules

Who: Developer (branches, commits) and Orchestrator (merge, cleanup). Tester and Deployer do not change git state.

1. One task = one branch + one worktree, both named in the Task File: branch `t-NNN-slug`, folder `<worktrees>\<repo>-t-NNN-slug`. `<worktrees>` is one folder outside the repository and outside OneDrive or other cloud sync (for example `D:\tmp`), named once in the Project rules; not named = ask the human before the first developer task. If a task touches several repositories, use the same branch name in each.
2. The main folder of the repository stays on the main branch (`main` or `master`). Only the Orchestrator works there: memory, `tasks/`, merges. Developers never change files in the main folder, except their own Task File's `## Result`.
3. Developer start. Launched by `tools/run-task.ps1`: the worktree already exists and the session starts inside it; check that the current folder is the task's `Worktree` and `git branch --show-current` is the task's `Branch`, then work. Started by hand: create it yourself from the main folder, `git worktree add <folder> -b <branch> <main-branch>`, then `git status` inside it. In both cases: a folder or branch that exists but is not this task's = `blocked`.
4. Do not mix tasks in one branch. Do not carry changes between tasks through stash or a shared intermediate branch.
5. One commit per task: `[T-NNN] <type>: <what>`. Before finishing, check that the branch contains only this task's changes and the worktree has no uncommitted changes.
6. After acceptance the Orchestrator merges the task branch into the main branch, then removes the worktree (`git worktree remove <folder>`) and the branch (`git branch -d <branch>`). Finished worktrees and branches are not left hanging, unless the human forbids the merge. Rejected or abandoned tasks are cleaned up the same way once the human agrees. If the repository is in OneDrive and `git worktree remove` fails with `Permission denied` (OneDrive sets ReadOnly), delete the folder with PowerShell `Remove-Item -Recurse -Force <folder>`, then run `git worktree prune`.
7. Nobody deletes worktrees or branches of other tasks without the Orchestrator or an explicit human instruction.

## Section: Starting a new AI session

For Single Mode and the Orchestrator.

1. Read this file (`docs/ai-handoff-protocol.md`).
2. Read `state/handoff.md`.
3. Read `docs/project-plan.md`.
4. Read `state/current-step.md`.
5. Read `state/tasks.md` if it has open tasks.
6. If referenced files are needed to understand the task, inspect them before asking the user.
7. Summarize: current goal, current state, open tasks, next exact step, open blockers, files likely to be touched.
8. Do not repeat failed attempts listed in `state/known-issues.md`. Do not invent missing context. Ask only when the answer cannot be discovered from project files.

## Section: Starting a role session

Input: role name and, for workers, a Task File path. Example: `/start-role developer tasks/T-101-api.md`.

Orchestrator:

1. Read `roles/orchestrator.md`.
2. Run [Starting a new AI session](#section-starting-a-new-ai-session).

Worker (Developer, Tester, Deployer):

1. Read `roles/<role>.md`.
2. Read these sections of this file: Terms, Standing rules, Roles and memory ownership. Developer: also Git rules.
3. Read the Task File completely.
4. Read files listed in its `Read first`. Check `state/known-issues.md` for anything related.
5. Do not read handoff, project-plan, or current-step unless the Task File lists them. Workers need the task, not the whole project history.
6. State in 3-5 lines: task, plan, assumptions. Then work to the end without stopping for confirmation, except for the stop conditions in your role file.
7. Finish by filling `## Result` in the Task File.

## Section: Task lifecycle

Task Ledger statuses, set only by the Orchestrator in `state/tasks.md`:

```text
ready -> in progress -> review -> done
                          |
                          +-> rework (new task with the reviewer's findings)
blocked   - waiting for a human or another task
cancelled - no longer needed
```

1. Orchestrator writes `tasks/T-NNN-slug.md` from the template, adds a row `ready`.
2. Orchestrator hands the Task File to a fresh worker session, sets `in progress`.
3. Worker does the task and fills `## Result`.
4. Orchestrator reads the Result, sets `review`, checks it against Acceptance criteria and evidence.
5. Accepted: `done` (then merge per [Git rules](#section-git-rules), or hand to Deployer). Not accepted: `rework`, plus a new Task File that links to the old one.
6. All tasks of a Stage `done`: check the Stage result, update `docs/project-plan.md`.

Task IDs are never reused.

`in progress` means "issued and not yet accepted", not "a worker is alive". Whether a worker is alive is the process state below.

### Runtime state

Two different states, never mixed:

- **Process state** - `tasks/.runtime/T-NNN.json`, written only by `tools/run-task.ps1`: `running | completed | failed`, plus exit code, tool, pid, times, `limitHit`. `completed` means "the tool process exited with code 0", nothing more. `tools/run-task.ps1 -Status` lists all tasks and also shows `dead`: `running` in the file, but the process is gone (window closed).
- **Task state** - `## Result` (worker) and the ledger status (Orchestrator). Only these say `done`, `blocked`, `rework`.

Rules:

1. The human is not a dispatcher. The Orchestrator polls `-Status` slowly (for example every 2-3 minutes).
2. Process ended (`completed`, `failed`, `dead`) - read `## Result`. Filled: [Acceptance](#acceptance). Empty: [Recovery](#recovery-stale-task).
3. `## Result` filled while the process is still `running` (an interactive tool stays open) - read it. After acceptance stop the worker: `tools/run-task.ps1 T-NNN -Stop`.
4. **One task = one live worker.** A `running` state with a live process is the task's lock: `run-task.ps1` refuses a second launch of the same task; two launches at the same moment are serialized by a short startup mutex `tasks/.runtime/T-NNN.lock`. Re-issue, Resume, fallback to another tool happen only after the lock is released: the process ended, or the Orchestrator ran `-Stop` on a hung worker. A worker is never declared dead by guess.
5. Runtime files are not committed (`.gitignore`: `tasks/.runtime/`).

### Acceptance

The Orchestrator accepts on evidence, not on the worker's word:

1. `git diff --name-only <main>...<branch>` is inside `Allowed files`. Anything outside = `rework`, not a quiet merge.
2. Run the task's `## Checks` commands, exactly as written, on the branch before merge, not only after it. Nothing beyond them: a new experiment, measurement, or manual investigation is a Tester task, not acceptance.
3. A change visible to a user, or risky (data, auth, deploy scripts, shared config), needs an independent review before merge: a Tester task (UI: in a browser), or a read-only review by a cheap tool. The Orchestrator may skip it only by writing the reason in `state/decisions.md`.
4. A stage rule from the plan (for example "prototype first") is checked at acceptance too: no prototype, no `done`.

### Release order

When a product has parts that depend on each other (for example a library or viewer, then a studio that embeds it, then a site), the Task File of the Deployer lists them in dependency order, and a train is deployed in that order: dependency first, dependents after. Before the first deploy of the train, the Deployer runs the project's smoke check against the current production, to prove the check itself is not stale. Each Task File names what must be rebuilt together (section "Rebuild together").

### Recovery: stale task

A worker may vanish: tokens ran out, the session died or was closed, the tool hung, compaction broke the context. Then:

1. The Task File stays the source of the assignment.
2. Uncommitted changes in the worktree are not a Result. They are an unverified draft.
3. The Orchestrator checks the task's branch and worktree: commits, uncommitted changes, any partial `## Result`.
4. A useful commit exists: a new worker session continues from it on the same branch and worktree. The Orchestrator writes `Resume: <commit>` in the Task File.
5. No useful commit: the Orchestrator discards the draft in that worktree only, writes `Resume: start fresh`, and starts a new session on the same Task File.
6. The Task ID stays the same while the scope is unchanged. A changed scope means a new task.
7. Usage-limit failure (`limitHit: true` in the runtime state, or "usage limit", "rate limit", "quota" in the worker log): not a task failure. After the lock is released ([Runtime state](#runtime-state), rule 4) the Orchestrator moves the same Task File to the fallback tool from [roles/tool-routing.md](../roles/tool-routing.md) without asking the human, notes the tool change in the ledger `Notes`, and follows steps 3-5. A tool never changes silently: the ledger `Tool` column always shows the tool that holds the task.

## Section: Launching workers

Who: Orchestrator (or the human). Details per tool: [roles/tool-routing.md](../roles/tool-routing.md).

1. Launch through `tools/run-task.ps1 T-NNN <tool>` where it exists. It creates the worktree, prepares the environment, opens a visible window with a log, and keeps the [Runtime state](#runtime-state) with the one-worker lock. Do not hand-write launch scripts per task: escaping bugs (`$id`, `\t`, quotes) cost more than the script.
2. Workers run in visible windows, never hidden background processes, unless the human says otherwise for this session. A window the human can see is also the only way they can stop a worker.
3. The Deployer runs only in the session the human designated as the deployer (named in the Task File and in `state/decisions.md`). The Orchestrator does not start its own deployer on another tool, and gives no tool with full access to production.
4. Full-access modes (`danger-full-access`, `--dangerously-skip-permissions`) are for Developers in a throwaway worktree only. Tester and Deployer run with the tool's normal confirmations.
5. Prepare the environment before the worker starts, not inside its budget: dependencies and build artifacts a task needs (`node_modules`, `dist`, virtualenv) are copied or linked into the worktree by the launcher. A task that is `blocked` on a missing environment is an Orchestrator error.
6. Parallel tasks must not share a network port. Each task gets its own `PORT` in the Task File (section "Port"); tests read it from the environment.
7. At session start the human states the remaining limit per tool; the Orchestrator keeps it in the conversation, not in memory files, and picks fallbacks from it before launching.
8. **Maximize safe parallelism.** Launch every ready task that can safely run now; do not keep an independent ready task waiting while a suitable tool is free. A task is ready when its ledger status is `ready` and every `Depends on` task is `done`. Two ready tasks can run together when they share no file in `Allowed files`, no `Port`, and no `Rebuild together` target. Parallelism = min(independent ready tasks, free tool capacity by the stated limits, environment capacity: ports, machine). No fixed number of agents. When a task finishes, refill the free slot at once.
9. **Preflight.** `run-task.ps1` checks the Task File before it creates anything and refuses the launch with the full list of problems: a `Depends on` task not `done` in the ledger (a pre-merge Tester's checked task needs a filled Result instead); `Allowed files` or `Rebuild together` shared with a task that is `in progress` / `review` or has a worker process; `Port` shared with a running worker; `Allowed files` overlapping `Do not touch`; `Acceptance criteria` or `## Checks` empty or still the template text; a developer `Branch` not starting with `t-NNN-`; `env: AGENTFLOW_*` lines. Project patterns come from a `## Preflight` section in the Project rules and apply to `## Checks` commands and `## Environment setup` lines of local tasks:
   - `- deny: <regex>` - no command may match (production hosts, destructive commands);
   - `- require: <regex> => <regex>` - a command matching the first must also match the second (for example `playwright test => --project=local`).

   A refused launch is fixed in the Task File, not worked around.
10. **Production is opt-in.** Every worker gets `AGENTFLOW_TARGET`: `local` for Developers and pre-merge Testers, the task's `Environment` (`staging` / `prod`) for a live Tester. A Task File cannot override it. Project test and run configs must default to local: unset or `local` never reaches staging or production. A config that can reach production by default is a defect: the Orchestrator issues a developer task to fix it before other work that runs those tests.

## Section: Updating memory

Who: Single Mode session or Orchestrator. Workers do not run this section.

Run after meaningful work, or before ending a long session.

1. Update `state/handoff.md` - keep it short.
2. Update `state/current-step.md` if the next practical step changed.
3. Update `state/tasks.md` if task statuses changed.
4. Add a fact to `state/session-log.md` if work was done or project state changed.
5. Add a decision to `state/decisions.md` if an important choice changed future work - dated, with a reason.
6. Add an entry to `state/known-issues.md` if there was a dead end, error, false lead, or constraint.
7. Update `docs/project-plan.md` if the roadmap changed.
8. Move accepted `Proposed memory updates` from worker Results into the files above.
9. Follow Standing rules above (no secrets, etc).

## Section: Handoff (short transfer note)

Who: Single Mode session or Orchestrator.

Update `state/handoff.md` only, as a short transfer note for the next AI session. Include:

- Goal
- Current State
- Files in Flight
- Changed Since Last Handoff
- Failed Attempts / False Leads
- Assumptions
- Open Problems
- Next Exact Step
- Files To Read First

Keep it short: usually 1-2 screens (about 4 KB). `state/current-step.md` the same. History does not stay there: when a file passes the limit, move finished items to `state/session-log.md` in the same update. Rules that must survive a new session or another tool belong in project files (`state/decisions.md`, `roles/tool-routing.md`, Project rules), never only in one tool's private memory. Link to detailed files instead of duplicating long logs. Open tasks are listed in `state/tasks.md`, not here. Separate verified facts from assumptions.

## Section: Updating the runbook

Who: Single Mode session or Orchestrator. The Deployer proposes new verified steps in its Result.

Update the clean human-facing instruction in `runbook/` (project-specific file if one exists, otherwise `runbook/clean-instruction.md`; create it if missing). Use only after a step is confirmed to work.

Include only:

- verified steps that led to the result;
- exact commands or UI actions that should be repeated;
- expected result for each step;
- links to screenshots that already exist in `screenshots/`;
- final verification steps.

Exclude: failed attempts, temporary diagnostics, false hypotheses, duplicated trial-and-error, secrets.

If a screenshot would help but does not exist yet, add a TODO for the user to save it; do not invent a filename.

## Recommended end-of-session sequence

Who: Single Mode session or Orchestrator. A worker session ends when its Result is filled.

1. Updating the runbook (skip if no verified user-facing instruction changed)
2. Updating memory
3. Handoff
