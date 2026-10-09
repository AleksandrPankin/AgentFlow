# AI Project Memory Protocol

Purpose: keep project context across long AI-assisted work, tools, and sessions: one session, or a team of role sessions.

This file is the single source of truth. Entry points (`AGENTS.md`, `CLAUDE.md`, `.claude/commands/`), role files, README, and the guide point here by section name instead of repeating rules. Scripts in `tools/` enforce it; a script that disagrees with it is a defect in the script. Change a rule here, once.

## Terms

- Canonical Memory - the official project state: `state/`, `docs/project-plan.md`, `runbook/`. One writer: [Roles and memory ownership](#section-roles-and-memory-ownership). Files: [What goes where](#what-goes-where).
- Single Mode - a session without a role; it works and writes Canonical Memory itself. Team Mode - sessions started with a role ([Starting a role session](#section-starting-a-role-session)).
- Role file - instructions for one role in `roles/`: [orchestrator](../roles/orchestrator.md) (splits goals into tasks, decides on Results, the only writer of Canonical Memory in Team Mode) and the workers [developer](../roles/developer.md) (changes code for one task), [tester](../roles/tester.md) (checks one task), [deployer](../roles/deployer.md) (deploys one accepted commit).
- Task File - one unit of work for one worker, `tasks/T-NNN-slug.md`, written by the Orchestrator from [tasks/_template.md](../tasks/_template.md). Its `## Checks` are the exact commands that prove its `Acceptance criteria`; the worker and acceptance run them verbatim.
- Result - the `## Result` section of a Task File, written by its worker: `Outcome` plus the role result ([Task lifecycle](#section-task-lifecycle)); format in the role file.
- Attempt - one launch of a worker for a task, recorded by the launcher ([Runtime state](#runtime-state)).
- Task Ledger - [state/tasks.md](../state/tasks.md), one row per task. Stage - one roadmap step in `docs/project-plan.md`; each task belongs to one.
- Tool Routing - [roles/tool-routing.md](../roles/tool-routing.md): which tool takes which task; read by the Orchestrator only.
- Project rules - the project's own rules: `docs/engineering-rules.md` or `AGENTS.md` under `## Project rules`; never overwritten by a template update. They name the `<worktrees>` folder and may hold `## Preflight`, `## Tool routing`, and `## Deploy`.
- Owner task - `OWN-###` in `state/owner-tasks.md`: an action or decision only the human can give; the work goes on around it except for the blocking list ([Owner tasks](#section-owner-tasks)).
- Product definition - the product's own documents in `docs/product/` (Vision, Brief, PRD, Architecture, ADRs, readiness review); active when `docs/product/00_INDEX.md` exists ([Product definition](#section-product-definition)). Spec item - one ID block in it (`FR-012`, `AC-012`, `ADR-006`); a Task File names its items in `Spec:`. Product gate - G0-G5, a readiness check of one slice (a Stage) run by agents, with the human's word coming later through an owner task; not a `gate.py` check.
- Review isolation - a Tester cannot change the Developer artifact it checks: it works in a disposable checkout of the `Verifies` commit, and after the attempt the launcher checks that the checked branch, worktree, and Task File did not change. Codex enforces it with a sandbox; for Claude only that end check guards it.

## What goes where

- `state/handoff.md` - short transfer note for the next session.
- `state/current-step.md` - only the next practical action.
- `state/session-log.md` - chronological work history.
- `state/known-issues.md` - failed attempts, dead ends, false hypotheses, constraints; dated, with when to look again.
- `state/decisions.md` - important decisions: why, and what was rejected.
- `state/tasks.md` - Task Ledger, edited only with `python tools/ledger.py`.
- `state/owner-tasks.md` - owner tasks and the journal of the human's answers (human-facing).
- `docs/project-plan.md` - roadmap: stages with Exit criteria and state.
- `docs/product/` - Product definition (human-facing); `decisions/ADR-###.md` in it hold technical decisions of the product, `state/decisions.md` decisions about process and plan; neither copies the other.
- `runbook/` - verified steps only ([Updating the runbook](#section-updating-the-runbook)); `screenshots/` - images linked from it.
- `roles/`, `tasks/_template.md`, `tools/` (launcher `run-task.ps1`, gates `gate.py`, ledger `ledger.py`), `dashboard/` (the human's read-only view), `templates/` (skeletons copied into a project once) - template-owned ([Installing or updating AgentFlow](#section-installing-or-updating-agentflow)); change them only to fix the template itself.
- `tasks/T-NNN-slug.md` - Task Files.

### Planning levels

| File | Level | Horizon | Answers |
|---|---|---|---|
| `docs/project-plan.md` | Stage | weeks | where we are going, what closes the stage |
| `state/tasks.md` | Task | hours | who does which piece, in which state |
| `state/current-step.md` | Next action | now | what exactly to do next ("when T-104 is done, give T-105 to the tester") |
| `state/handoff.md` | Snapshot | one session | where the last session stopped, what to read first |

Each level links to the others and never copies them: the plan lists no tasks (tasks name their Stage), current-step refers to task IDs, handoff links to the other three. Single Mode: the ledger is optional.

## Standing rules

Apply to every session and role (after the Karpathy guidelines: think first, simplicity, surgical changes, goal-driven work).

Rule order: this file > Project rules (including nested `AGENTS.md`) > role file > Task File. Lower levels add specifics and cannot cancel or weaken higher ones. Imperatives are mandatory; "prefer" is a default you may leave with a stated reason. An explicit instruction from the human overrides a rule for the current session only, noted by the Orchestrator in the ledger `Notes` or `state/decisions.md`; it never covers secrets, review isolation, or production approval.

- Inspect relevant project files before assuming or asking.
- Unclear request or several readings: state your assumptions or ask; do not pick silently.
- Prefer the smallest change that does the job: no speculative features, abstractions, or settings.
- Change only the files and lines the task needs; keep existing style and unrelated work. Clean up only what your own change made unused.
- Before work, define how success will be checked (test, command, screenshot).
- Never write passwords, tokens, keys, recovery codes, cookies, or other secrets to Markdown.
- Do not invent screenshots or files; link a screenshot only if it exists in `screenshots/`.
- Do not repeat failed attempts listed in `state/known-issues.md`.
- Talk to the human in Russian unless Project rules name another language: an optional `Status: <LABEL>` line, then a short explanation that adds information; do not repeat the status in words or quote this file unless asked. Machine-facing files (rules, roles, Task Files, memory) stay in English; human-facing files (`docs/product/`, `state/owner-tasks.md`, `GUIDE.md`, the dashboard) are Russian, with IDs, statuses, and field names in Latin. A human explanation is written from the rules when needed, never stored as a second copy; the one exception is `docs/product/05`-`08`, which explain [Product definition](#section-product-definition) and change in the same commit as it.

## Section: Roles and memory ownership

Single Mode: you follow every section yourself, including writing Canonical Memory. Team Mode:

| | Orchestrator | Developer | Tester | Deployer |
|---|---|---|---|---|
| Write Canonical Memory and Task Files | only writer | own `## Result` | own `## Result` | own `## Result` |
| Write `docs/product/`, owner tasks | only writer (the human ticks owner tasks) | no | no | no |
| Change product code | no | within `Allowed files` | no | no |
| Commit | memory and `tasks/` | one per task | no | no |
| Merge | after acceptance | no | no | no |
| Deploy, server, production | no | no | checks without changes | yes; production after the human's yes in the Deployer session |

1. Workers never run Updating memory, Handoff, or Updating the runbook; they propose in `Proposed memory updates` (and `Proposed spec changes`), and the Orchestrator decides. A worker that needs the human writes `Needs owner: <action>` in a `blocked` Result.
2. One task = one fresh session.
3. Parallel tasks share no file in `Allowed files`; each developer task has its own worktree.
4. A worker that cannot continue writes `Outcome: blocked` with the question and stops: no guessing, no widening the task.
5. Workers start no sub-agents or parallel agents; only the Orchestrator decides what runs in parallel, as separate sessions.
6. Results are short and in the role file format; no reports on internal tools or token usage.

## Section: Git rules

Developer: branches and commits. Orchestrator: merges and cleanup. Tester and Deployer change no git state.

1. One task = one branch `t-NNN-slug` + one worktree `<worktrees>\<repo>-t-NNN-slug`, both in the Task File. `<worktrees>` is one folder outside the repository and outside cloud sync (for example `D:\tmp`), named in Project rules; not named: ask the human before the first developer task. Several repositories: the same branch name in each.
2. The main folder stays on the main branch (`main` or `master`) and belongs to the Orchestrator: memory, `tasks/`, merges. Developers change nothing there except their own `## Result`.
3. The launcher creates the worktree, also for `-Manual`. Check that the current folder is `Worktree` and the branch is `Branch`; anything else: `blocked`.
4. No mixing tasks in one branch; no carrying changes through stash or a shared branch.
5. One commit per task, `[T-NNN] <type>: <what>`; before finishing, the branch holds only this task and the worktree nothing uncommitted.
6. After acceptance the Orchestrator merges, then removes the worktree (`git worktree remove`) and the branch (`git branch -d`), unless the human forbids the merge; rejected or abandoned tasks are cleaned up the same way once the human agrees. If `git worktree remove` fails with `Permission denied` under OneDrive, delete the folder (`Remove-Item -Recurse -Force`), then run `git worktree prune`. Then `tools/run-task.ps1 T-NNN -Cleanup` drops the folder trust entries the launcher added for the task.
7. Nobody deletes other tasks' worktrees or branches without the Orchestrator or the human.

## Section: Starting a new AI session

For Single Mode and the Orchestrator.

1. Read this file, then `state/handoff.md`, `docs/project-plan.md`, `state/current-step.md`, `state/tasks.md` if it has open tasks, the open tasks of `state/owner-tasks.md` (not its journal), and `docs/product/00_INDEX.md` if it exists.
2. Inspect the referenced files you need before asking.
3. Summarize: goal, state, open tasks, next step, blockers, files likely to change.
4. Do not repeat failed attempts from `state/known-issues.md`; do not invent missing context; ask only what the files cannot answer.

## Section: Starting a role session

Input: a role and, for a worker, a Task File path (`/start-role developer tasks/T-101-api.md`).

Orchestrator: read `roles/orchestrator.md`, then run Starting a new AI session.

Worker:

1. Read `roles/<role>.md` and these sections: Terms, Standing rules, Roles and memory ownership (Developer: also Git rules).
2. Read the Task File completely, the files in its `Read first`, and related entries in `state/known-issues.md`. An entry `<file> - <IDs>` means only those sections of the file, plus the constraints the entry names; the whole file only when a named section cannot be understood without it. Not handoff, plan, or current-step unless the Task File lists them.
3. State task, plan, and assumptions in 3-5 lines, then work to the end without asking for confirmation, except for your role's stop conditions.
4. Finish by filling `## Result`.

## Section: Owner tasks

The human is the final word, not a dispatcher or a bottleneck. What only the human can do or decide goes into `state/owner-tasks.md` (skeleton `templates/owner-tasks.md`), and the work goes on around it.

1. Writer: the Orchestrator or Single Mode. The human ticks tasks and answers in the file or in chat; the Orchestrator moves chat answers into the file. For a worker's `Needs owner:` the Orchestrator opens the task and sets the ledger `blocked` with `Notes: OWN-###`.
2. One task = one action (one secret = one task), `OWN-###`, never reused: what to do (exact steps) -> what to return (form) -> what it unblocks (`ничего - финальное слово` allowed) -> when. Marks: `[ ]` open, `[~]` in progress, `[x]` done with date and short result, `[-]` withdrawn with reason. Secret values never go into the file, chat, or Markdown.
3. **Blocking list.** Agents wait for the human only here, and only the affected work: an action only the human can do (key, token, account, login, payment); a production deploy ([Launching workers](#section-launching-workers), rule 3); a server change (new service, port, proxy or firewall rule, DB role or grant, secret, volume, domain); money beyond the project budget; new external access or personal data; an irreversible action without rollback; a feature outside the agreed MVP (it waits and is not built meanwhile). Anything else: go on with the recommended option, mark it as proposed, and ask in an owner task. Silence is not consent: an unanswered recommendation stays proposed.
4. Journal at the end of the file: date, question or task, answer, where it landed. It is the only record of the human's answers on the product; an answer that changes how the project works also gets a `state/decisions.md` entry citing the journal date. Search the journal before asking the human anything.

## Section: Product definition

Active when `docs/product/00_INDEX.md` exists; otherwise skip this section. The same rules for the human, in Russian: `docs/product/05`-`08`; agents read those only when asked.

1. Files (from `templates/product/`): `00_INDEX` navigation and the only gate register; `01_VISION` why; `02_BRIEF` for whom, MVP, limits, MVP metrics; `03_PRD` behaviour (`FR`), quality (`NFR`), acceptance (`AC`); `04_ARCHITECTURE` how, with decisions in `decisions/ADR-###.md`; `09_REVIEW` the Orchestrator's readiness report for the human, rewritten each round. One fact, one place: a lower document cites the upper ID and never restates it; a disagreement becomes a question `Q-*`, not a silent edit.
2. Writer: the Orchestrator or Single Mode, from the human's words and research. Workers never edit `docs/product/`; they write `Proposed spec changes:` in the Result.
3. Items: a heading `### <ID> — <title>`, then `- **Статус:** <status>` (FR, NFR, ADR) or `- **Source:** FR-###` (AC: the worst status of its FR / NFR sources); FR and NFR also `- **Приоритет:** Must | Should | Could | Won't | Later`. Vision and Brief carry one `status` in front matter, a ceiling for every item: an item is implementable only while both are. IDs are never reused.
4. Spec status: `DRAFT`; `PROPOSED` once the agent check passed and an owner task asks for the human's word - implementable; `APPROVED (OWN-###)` only from the human's answer in the owner journal, naming that owner task, done - implementable; `STALE` when an upstream item changed - not implementable until re-checked (`PROPOSED`) or kept by the human (`APPROVED`); `SUPERSEDED` when replaced.
5. Gates. Slice = one Stage of `docs/project-plan.md`. G0-G3: the Orchestrator checks the readiness lists of `01`-`04` for the slice, runs `python tools/gate.py spec` (no errors), writes `09_REVIEW.md`, sets the slice's items `PROPOSED`, opens one owner task "review the slice" and goes on. G4: `gate.py verify` per task and `gate.py stage N`. G5: an owner task to check the slice in live use against `B07` and `V03`. The human's word never holds a Stage open; a "not OK" becomes changed items and new tasks. Each gate goes into the register in `00_INDEX.md`, and only there.
6. Tasks come only from implementable items. A developer task names them: `Spec: FR-012, AC-012, ADR-006`, or `Spec: none - <reason>` (chore, tooling), or `Spec: spike - <Q-ID>` (research before G3: the result goes to an ADR, the spike code is not merged). `Read first` lists `docs/product/<file> - <IDs>`. Task `Acceptance criteria` cite the AC they refine (`AC-012: ...`) and add no new obligation. Preflight checks this ([Launching workers](#section-launching-workers), rule 9).
7. Change Impact, when an implementable item changes: write what and why, bump `version`; find dependents with `git grep -n "<ID>" docs/product tasks state`; mark dependent items `STALE`; set open tasks that name them `blocked` with `Notes: spec changed <ID>`; leave `done` tasks, a needed rework is a new task; a change of meaning, scope, or anything on the blocking list is an owner task.
8. Reading: the Orchestrator reads `00_INDEX.md` and the sections it needs by ID, never all documents by default; workers read only their `Read first` sections; `05`-`09` are for the human.

## Section: Task lifecycle

### States

Each family has one owner, and a label means one thing only.

| Family | Where; who writes | Values |
|---|---|---|
| Task state | ledger `Status`; Orchestrator via `tools/ledger.py` | `ready`; `in progress` (issued, not decided); `review`; `done` (accepted); `rejected` (successor in `Notes`); `blocked` (waits for a human or another task); `cancelled` (reason in `Notes`) |
| Process state | `tasks/.runtime/T-NNN.json`; launcher | per attempt `running`, `exited` (exit 0, or a manual attempt marked finished), `error`; `-Status` derives `dead` (running, process gone) |
| Outcome | `## Result`, `Outcome:`; worker | `completed`; `blocked` (question in the Result); `failed` (why in the Result) |
| Role result | `## Result`; worker | Developer `Change: <SHA>`; Tester `Verdict:` `pass`, `partial`, `unverified`, `fail` = the worst criterion; Deployer `Deployment:` `deployed`, `rolled-back`, `not-started` |
| Stage state | `docs/project-plan.md`; Orchestrator | `planned`, `current`, `closed` |
| Spec status | `docs/product/` item `Статус:` (Vision, Brief: front matter); Orchestrator | `DRAFT`, `PROPOSED`, `APPROVED` (only from the owner journal), `STALE`, `SUPERSEDED` ([Product definition](#section-product-definition)) |
| Owner task | `state/owner-tasks.md`; Orchestrator, the human ticks | `[ ]` open, `[~]` in progress, `[x]` done, `[-]` withdrawn |

`tools/ledger.py` enforces the transitions: `ready` -> `in progress` / `blocked` / `cancelled`; `in progress` -> `review` / `blocked` / `rejected` / `cancelled`; `review` -> `done` / `rejected` / `in progress` / `blocked`; `blocked` -> `ready` / `in progress` / `review` / `cancelled`. `done`, `rejected`, `cancelled` are final. Task IDs are never reused.

### Flow

1. The Orchestrator writes the Task File (with Product definition: `Spec:`) and adds the ledger row (`ready`). `Independent check:` is `tester` for a user-visible or risky change (data, auth, deploy scripts, shared config), otherwise `none - <reason>`; the human sees it in the plan.
2. Launch ([Launching workers](#section-launching-workers)); ledger `in progress`.
3. The worker fills `## Result`.
4. The Orchestrator sets `review` and decides:

| Result | Decision | Task state |
|---|---|---|
| `completed`, `python tools/gate.py verify T-NNN` passes | accept: `ledger.py set T-NNN --status done --commit <SHA>`, then merge | `done` |
| `completed`, verify fails | reject; a new Task File with the findings links to the old one | `rejected`, `Notes: -> T-xxx: <why>` |
| `blocked` | answer, asking the human if needed | `blocked`, then `in progress` |
| `failed`, `incomplete`, empty Result, attempt `error` or `dead` | [Recovery](#recovery-stale-task) | `in progress` (new attempt) or `rejected` |
| Tester `Verdict` not `pass` | reject the checked task; the Tester task is `done` when its verify passes | checked task `rejected` |
| Deployer `rolled-back` | reject the Deployer task; accepted code stays `done` (accepted is not deployed); the fix is a new developer task | Deployer task `rejected` |

5. A Stage closes when its tasks are `done` (rejected or cancelled ones replaced by `done` successors) and `python tools/gate.py stage <N>` passes on the main branch; then update the plan.

### Acceptance

Acceptance is the event `review` -> `done`; `tools/ledger.py` allows it only after `gate.py verify` passed on that SHA. The verify record (`tasks/.runtime/T-NNN.verify.json`: attempt, SHA, target, check exit codes, log) is the evidence. Verify requires:

- the last attempt `exited`, the Task File above `## Result` unchanged, `Outcome: completed`;
- Developer: branch, clean worktree, and `Change` at one SHA; `git diff <main>...<SHA>` inside `Allowed files`; every `## Checks` command passing there with `AGENTFLOW_TARGET=local`; with `Independent check: tester`, a `done` Tester task with `Verdict: pass` for this SHA;
- Tester: `Verdict` equal to its worst criterion;
- Deployer: `Deployment: deployed`, `Smoke` pass, and for production `Approval: source=human target=prod sha=<SHA> at=<time>`.

Beyond verify the Orchestrator does not investigate: a new measurement is a Tester task. When verify notes that the Checks use files the task changed, read that diff first. A stage rule from the plan ("prototype first") is checked here too.

### Runtime state

An `exited` attempt says nothing about the task: only the Result and the ledger do.

1. `tasks/.runtime/T-NNN.json` is written only by `tools/run-task.ps1`: one entry per attempt (tool and arguments, times, exit code, `limitHit`, target, folder, baseline), appended, never overwritten; log `T-NNN.<n>.log`. Not committed.
2. At the end of every attempt the launcher runs `gate.py endcheck`: the Task File above `## Result` unchanged and, for a Tester, review isolation held. A violation makes the attempt `error`.
3. The human is not a dispatcher. After each launch the Orchestrator starts `tools/run-task.ps1 -Wait` (no ids: every running task) in the host tool's background mode, which wakes the session when the command exits (Claude Code: `run_in_background`); without one, in the foreground with the tool's longest command timeout; with neither, it polls `-Status` every few minutes. `-Wait` uses no model and no network and works only while the Orchestrator session is open. It returns at the first finished task with one line: `T-NNN finished: attempt=<process state> result=<class> [Change|Verdict|Deployment=<value>] [problem=...] [limit] [note=...]`; exit 0 finished, 3 timeout (`-TimeoutMin`), 4 nothing to wait for. On waking: read the `## Result`, run verify, decide, refill, start `-Wait` again.
   - Finished: the process ended (`exited`, `error`, `dead`); or, for an interactive tool (it keeps its window after the work) and a `-Manual` attempt, the Result holds a valid `Outcome:` unchanged for `-GraceSec` (default 20 s). Non-interactive tools are awaited until they exit.
   - Result class, read by keyword from the last `## Result` heading at line start (`gate.py result`): `completed` (Outcome and the role field: Developer `Change: <SHA>`, Tester `Verdict`, Deployer `Deployment`), `incomplete` (completed without a valid role field), `blocked`, `failed`, `none` (no valid Outcome; a pasted format line like `completed | blocked` is not one). `format=loose`: verify reads only strict `Field: value` lines and will fail on it.
   - Closing: an interactive window with a finished Result is closed by `-Wait` as `exited` after the end check, so verify can pass without the human; a Developer only when its worktree is clean at `Change`, otherwise the line says the window was left open. `-Stop` closes the same way when a valid Outcome exists and records `error` when none does (hung worker).
4. One task = one live worker. A `running` attempt is the task's lock; `tasks/.runtime/launch.lock` serializes launches from preflight until the attempt is recorded. Re-issue, Resume, and fallback happen only after the lock is released (the process ended, or `-Stop` on a hung worker). A worker is never declared dead by guess.

### Release order

Parts that depend on each other (a library, then the studio that embeds it, then the site) are listed in the Deployer's Task File in dependency order and deployed in that order. Before the first deploy of the train the Deployer runs the smoke check against the current production, to prove the check is not stale. Each Task File names what is rebuilt with it (`Rebuild together`).

### Recovery: stale task

A worker may vanish (limit, closed session, hang, broken context).

1. The Task File stays the assignment; uncommitted changes in the worktree are an unverified draft, not a Result.
2. The Orchestrator checks the branch and worktree: commits, uncommitted changes, any partial Result.
3. A useful commit exists: a new attempt continues from it on the same branch and worktree (`Resume: <commit>`). None: discard the draft in that worktree only, write `Resume: start fresh`, start a new attempt on the same Task File.
4. The Task ID stays while the scope is unchanged; a changed scope is a new task.
5. A usage limit (`limitHit` in the attempt, or "usage limit", "rate limit", "quota" at the end of the log) is not a task failure. After the lock is released the Orchestrator moves the same Task File to the fallback tool from Tool Routing without asking, notes it in the ledger `Notes`, and follows steps 2-3. The ledger `Tool` column always shows the tool that holds the task.

## Section: Launching workers

Who: the Orchestrator (or the human). Per tool: Tool Routing.

1. Every attempt starts through `tools/run-task.ps1` and passes the same gate. `T-NNN <tool>` prepares the worktree or checkout and the environment and opens a visible window with a log. `T-NNN -Manual` runs the same gate and preparation for a session a human starts (Antigravity IDE, the Deployer, a live Tester on production), prints folder, environment, and prompt, and is closed with `-MarkFinished`. No hand-written launch scripts.
2. Visible windows only, unless the human allows otherwise for this session: the window is how the human can stop a worker.
3. The Deployer is an agent session of the platform project named in Project rules `## Deploy` (its folder, the contract, the request file, the deploy script); without one, the session the human designates. The Orchestrator starts no deployer itself and gives no tool full access to production: it prepares the attempt with `-Manual`, adds the request to the request file, and messages that session where the host allows (Claude Code `SendMessage`); `-Wait` wakes it when the Result appears. The platform session writes only the deploy Task File's `## Result` and the request's status line. Staging: deployed on that request, through the contract script, with no server change. Production approval comes from the human in that session, never through the Orchestrator; the Orchestrator opens an owner task for it and other work goes on. A live Tester on production runs only in the session the human designated (`-Manual`).
4. Permissions come from the launcher's tool flags, not from prompts; a tool that asks to trust each new folder gets the worker folder pre-approved by the launcher (Antigravity CLI), and the entry is removed on cleanup. Full access: only a Developer in its own worktree. A Tester gets review isolation; prefer Codex for Tester tasks.
5. The launcher prepares what the task needs before the start (`## Setup`: links, copies, env); a task `blocked` on a missing environment is an Orchestrator error. Parallel tasks get different `PORT`s (`## Port`); tests read it from the environment.
6. The model is part of the launch: the Task File's `Model:` (tier or listed id) and `Effort:` are resolved by `tools/models.json` (per-machine override `AGENTFLOW_MODEL_<TOOL>_<TIER>`), passed as the tool's own flags, and recorded per attempt; absent or `default` = the tool's setting, no flag. Preflight refuses a value the table does not list for the launch tool. Choice: Tool Routing, Choosing the model.
7. The human states the remaining limit per tool at session start (`tools/run-task.ps1 -Limits` shows the last limit hit per tool with its log line); the Orchestrator keeps it in the conversation, not in files, and picks fallbacks from it.
8. **Maximize safe parallelism.** A task is ready when it is `ready` and every `Depends on` task is `done`. Launch every ready task that shares no `Allowed files`, `Port`, or `Rebuild together` with an open one: parallelism = min(ready tasks, free tool capacity, environment capacity). No fixed number of agents; refill a free slot at once.
9. **Preflight** (`gate.py preflight`) refuses a launch with the full list of problems, before anything is created:
   - a `Depends on` task not `done`;
   - Tester: pre-merge, the checked task lacks `Outcome: completed` with `Change` = the `Verifies` SHA, or its branch moved; live, the SHA is not merged. Deployer: the SHA is not merged;
   - a Deployer or a live Tester on production without `-Manual`;
   - with Product definition: a developer task without `Spec:`; a `Spec:` item that does not exist or is not `PROPOSED` / `APPROVED`; any `Allowed files` under `docs/product/`;
   - overlap with an open task (`in progress`, `review`, or a running attempt) in `Allowed files` or `Rebuild together`, or a `Port` of a running attempt; an open task whose Task File cannot be read;
   - the task itself: `Allowed files` inside `Do not touch`; empty or template `Acceptance criteria` or `## Checks`; a developer task without `Independent check` or with a `Branch` not starting with `t-NNN-`; a missing `## Setup` source; `env: AGENTFLOW_*`;
   - project patterns from `## Preflight` in Project rules, applied to the `## Checks` commands and `## Setup` lines of local tasks: `- deny: <regex>` (no command may match: production hosts, destructive commands) and `- require: <regex> => <regex>` (for example `playwright test => --project=local`).

   A refused launch is fixed in the Task File, not worked around.
10. **Production is opt-in.** Every worker gets `AGENTFLOW_TARGET`: `local`, or the task's `Target` (`staging` / `prod`) for a live Tester or the Deployer; a Task File cannot override it. Project test and run configs default to local: unset or `local` never reaches staging or production. A config that can reach production by default is a defect: the Orchestrator issues a developer task to fix it before other work that runs those tests.

## Section: Updating memory

Who: Single Mode or the Orchestrator, after meaningful work or before ending a long session.

1. `state/handoff.md`: per Handoff below.
2. `state/current-step.md` if the next step changed; `state/tasks.md` through `ledger.py`.
3. `state/session-log.md`: what was done or changed.
4. `state/decisions.md`: a choice that changes future work, dated, with why and what was rejected.
5. `state/known-issues.md`: a dead end, error, false lead, or constraint.
6. `docs/project-plan.md` if the roadmap changed.
7. Accepted `Proposed memory updates` go into these files; a rejected one gets a line with the reason in the session log.
8. `state/owner-tasks.md`: new owner tasks, closed ones, and a journal row for every answer the human gave in chat.

## Section: Handoff (short transfer note)

Who: Single Mode or the Orchestrator. Update only `state/handoff.md`:

- As of: date and `main@<SHA>`
- Goal
- Verified state (each fact with where it was checked)
- Files in flight; changed since the last handoff
- Failed attempts and false leads; assumptions; open problems
- Files to read first

Keep it, and `state/current-step.md`, within 1-2 screens (about 4 KB); move finished history to the session log in the same update. Open tasks live in the ledger and the next action in current-step, not here. Rules that must survive a new session or another tool belong in `state/decisions.md` or Project rules, never only in one tool's private memory.

## Section: Updating the runbook

Who: Single Mode or the Orchestrator, only after a step is confirmed to work; the Deployer proposes steps in its Result. Update the human-facing instruction in `runbook/` (a project-specific file, or `runbook/clean-instruction.md`; create it if missing) with only: the verified steps, exact commands or UI actions, the expected result of each step, links to existing screenshots, final verification. No failed attempts, diagnostics, hypotheses, or secrets. A missing screenshot: a TODO for the human, never an invented filename.

End of session (Single Mode or Orchestrator): Updating the runbook (if a verified step changed), Updating memory, Handoff. A worker session ends with its Result.

## Section: Dashboard

For the human, not for agents: a read-only view of the ledger, Task Files, and git history. `python dashboard/build.py` writes `dashboard/out/index.html` (task table, filters, task card) and `out/graph.html` (Gantt, timeline, links). Any session or the human may run it; it changes nothing outside `dashboard/out/`. Its interface is in Russian (human-facing).

1. It is rebuilt on demand only (the Refresh button of `python dashboard/serve.py`, `python dashboard/build.py`, or the human's request), never after every ledger change: it can lag, and that is accepted. It shows what the files say and invents nothing. Statuses, roles, and outcomes are this protocol's states under Russian labels; the ledger `Status`, the worker's `Outcome`, and the tester's `Verdict` stay three separate fields. A field it cannot read is empty or "Not set", never a guess; a value it estimates (who set the task) is labeled as an estimate.
2. `dashboard/` is template-owned: change it only to fix the template or on the human's request. Rules for changing it: `dashboard/UI-RULES.md`; before a noticeable change `python dashboard/snapshot.py save "<what>"`, roll back with `restore vN`. `dashboard/out/` and `dashboard/versions/` are local and git-ignored.
3. Changing a state or field name in this protocol means updating the data contract in `dashboard/README.md` and `dashboard/build.py` in the same commit.
4. The Orchestrator does not read the dashboard to decide: the ledger and `gate.py verify` are the evidence.

## Section: Installing or updating AgentFlow

Who: a Single Mode session, on the human's request. Version: `AgentFlow version:` in `AGENTS.md`.

- Template-owned, replaced on update: `AGENTS.md` above `## Project rules`, `CLAUDE.md`, `.claude/commands/`, this file, `roles/`, `tasks/_template.md`, `tools/`, `dashboard/`, and in a project with Product definition `docs/product/05_*`-`08_*`.
- Copied once, then project-owned: `templates/owner-tasks.md` -> `state/owner-tasks.md`; `templates/product/00_*`-`04_*`, `09_*` -> `docs/product/` (when the human wants a Product definition). The `templates/` folder itself is not copied.
- Project-owned, never overwritten: everything else (`state/`, `docs/project-plan.md`, `docs/product/` except `05`-`08`, `runbook/`, `screenshots/`, Task Files, Project rules).
- Template-only, never copied: `README.md`, `GUIDE.md`, `CHANGELOG.md`, `LICENSE`, `dev/` (regression checks of the template's tools), the template's own `state/` and `docs/project-plan.md`.
- A project rule never goes into a template-owned file, only into Project rules.

Install: the project needs git with a main branch and one commit. Copy the template-owned files and append the template's `.gitignore` lines; move rules from the project's earlier `CLAUDE.md` / `AGENTS.md` under `## Project rules`; create the memory from the real project state ([What goes where](#what-goes-where); `python tools/ledger.py show` creates the ledger) and `state/owner-tasks.md` from its skeleton; in Project rules name `<worktrees>`, add `## Preflight` (deny production hosts, require the local flags of test commands) and, if the project is deployed, `## Deploy` (platform project folder, contract, request file, deploy script). If the human wants a Product definition, copy `templates/product/` to `docs/product/` and fill the placeholders in `00_INDEX.md` only. A test config that reaches staging or production by default: tell the human, do not fix it here. No product code changes; one commit.

Update: compare `AgentFlow version` with the template's and read the template's `CHANGELOG.md` entries in between. Show the human the rules the project added inside template-owned files; after agreement move them to Project rules and replace the template-owned files. Apply the migration notes to open Task Files and the ledger; touch no other project-owned file; add a dated entry to `state/decisions.md`; one commit.
