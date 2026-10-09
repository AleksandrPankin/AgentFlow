# Implementation Plan: 2.2.0, 2.3.0, 3.0.0

Status: 2.2.0 and 2.3.0 implemented on `release/2.3.0` (2026-10-06), not merged; 3.0.0 open. Template-owned working document (not copied into projects). Once a release ships, its section is deleted and the result goes to `CHANGELOG.md` and `state/decisions.md`.

Inputs: `requests/2026-10-06-orchestrator-wake-on-worker-finish.md` (with its addendum), `requests/2026-10-06-per-task-model-selection.md` (both from project Calbot), the human's messages of 2026-10-06, and the `.agentflow/` layout proposed by a colleague (screenshots in the chat, no file source).

## 1. Goals

1. The Orchestrator learns that a worker has finished without the human and without spending model tokens while it waits.
2. A finished interactive worker (Antigravity CLI `-i`) does not stay `running` forever and does not block `gate.py verify`.
3. A worker never stops at a trust or permission prompt for its own folder.
4. Every task runs on a model chosen by complexity and risk, from vendor guidance and recorded practice, to spend quota rationally.
5. The template lives in one folder of a project and does not spread files over the project root.

Non-goals: new roles, new states in the task lifecycle, a daemon or service, any network call in the launcher, automating the Antigravity IDE.

## 2. Proposals and where they land

| # | Proposal | Source | Release |
|---|---|---|---|
| P1 | Zero-token alarm `run-task.ps1 -Wait` | Calbot #1, human | 2.2.0 |
| P2 | Result detection by keyword at the `## Result` heading (last match), tolerant to formatting | Calbot #1, human | 2.2.0 |
| P3 | Completion classes for every role and every tool (completed, incomplete, blocked, failed, none; process exited, error, dead, limit hit) | human | 2.2.0 |
| P4 | Close an interactive attempt as `exited` when the Result holds an `Outcome:` | Calbot #1 item 2 | 2.2.0 |
| P5 | Pre-approve the worker's folder for Antigravity CLI, remove the entry on cleanup | Calbot addendum, human | 2.2.0 |
| P6 | `Model:` per task, tier table, env override, recorded per attempt, preflight check | Calbot #2, human | 2.3.0 |
| P7 | "Choosing the model": vendor-verified selection guidance and rules | Calbot #2, human | 2.3.0 |
| P8 | Quota awareness: `-Limits` | Calbot #2 item 5 | 2.3.0 |
| P9 | Template in one folder `.agentflow/` | colleague | 3.0.0 |
| P10 | `requests/` is a local inbox, ignored by git | human | done |
| P11 | Refresh stale memory (handoff, current-step, plan) | session start | now, before 2.2.0 |

Order: P11, then 2.2.0, 2.3.0, 3.0.0. Reason: Calbot is blocked on 2.2.0 today; 2.3.0 needs vendor research and a table that can lag; 3.0.0 breaks every path and is mechanical once the scripts resolve paths from one root, so it goes last and does not double the work of the first two.

## 3. Design decisions

Each goes to `state/decisions.md` when its release ships.

### D1. The alarm is a launcher mode, not a model loop
`-Wait` is a blocking shell command. The Orchestrator starts it in the host tool's background mode (Claude Code `run_in_background`, which re-invokes the session on exit). Cost: no model tokens while waiting, one Orchestrator turn when a task ends. Rejected: self-paced polling (`/loop`: a full turn per tick, mostly empty), worker-to-Orchestrator messages (Claude-only). Polling stays as the fallback for hosts with no background mode.

### D2. "Finished" has one definition
A task is finished when either:
- the last attempt is no longer `running` (`exited`, `error`, or `dead` = process gone without a final state); or
- the Result holds a valid `Outcome:` and the Result text has not changed for `-GraceSec` seconds (default 20). The grace covers a worker that writes `Outcome:` first and fills the rest after.

For a `-Manual` attempt only the second rule applies (there is no process to watch); `-MarkFinished` still ends it.

### D3. Completion classes (output of `gate.py result`)
Detection is by keyword and tolerant: `Outcome: completed`, `- **Outcome:** Completed.`, backticks and quote markers are accepted. A value followed by `|` is a copied format line, not an answer, and is ignored.

| Class | Condition | What the Orchestrator does |
|---|---|---|
| `completed` | `Outcome: completed` and the role field is valid: Developer `Change: <SHA>`, Tester `Verdict: pass|partial|unverified|fail`, Deployer `Deployment: deployed|rolled-back|not-started` | `gate.py verify`, then decide |
| `incomplete` | `Outcome: completed`, role field missing or invalid | read the Result; usually reject or re-issue |
| `blocked` | `Outcome: blocked` | answer the question in the Result; ask the human if needed |
| `failed` | `Outcome: failed` | Recovery or reject by the lifecycle table |
| `none` | no valid `Outcome:` | process ended: Recovery (stale task); still running: keep waiting |

`blocked` and `failed` without `Question or reason` are flagged `problem` in the line. Process facts are printed next to the class: `attempt=exited|error|dead|running`, `limit` when `limitHit`.

Matrix of endings the tests must cover (role x ending):

| Ending | Process | Result | Expected line |
|---|---|---|---|
| clean | exited 0 | completed + role field | `attempt=exited result=completed <field>=<value>` |
| clean, wrong format | exited 0 | `Outcome: completed`, no role field | `result=incomplete` |
| worker stuck on a question | exited 0 | blocked + reason | `result=blocked` |
| worker gave up | exited 0 | failed + reason | `result=failed` |
| tool crash | exited non-zero (`error`) | empty | `attempt=error result=none` |
| window closed / process killed | gone, no final state (`dead`) | empty | `attempt=dead result=none` |
| silent finish | exited 0 | empty | `attempt=exited result=none` |
| limit hit | error | empty or partial | `attempt=error result=none limit` |
| interactive, done, window open | running | completed + field, stable | `attempt=running result=completed`, then auto-close (D4) |
| interactive, still writing | running | Outcome present, changing | keeps waiting until stable |
| Result quotes the heading | any | quote in text, real Outcome below | the real Outcome wins |
| manual attempt | none | completed | `attempt=running(manual) result=completed` |

### D4. Closing an interactive worker
Applies to tools with `pipe = $false` (Antigravity CLI). When D2 fires on the Result rule and the attempt is still `running`:
- Developer: close only if its worktree has nothing uncommitted (`git status --porcelain` empty) and `Change` is a commit on the task's branch; otherwise print `result filled, worktree dirty` and keep waiting.
- Kill the process tree, run the end check (`Complete-Attempt`, review isolation unchanged), record `exited` with `note: closed after Result`. `gate.py verify` then passes without the human.
- `-Stop` does the same when a valid `Outcome:` exists, and records `error` otherwise (today's behaviour for a hung worker).

Rejected: waiting for the human to type `/exit`.

### D5. Folder trust is data the launcher owns
Before an `agy` launch the launcher adds the worker folder to `trustedWorkspaces` in `%USERPROFILE%\.gemini\antigravity-cli\settings.json` (exact-path list, a parent folder does not cover subfolders). Rules: keep unknown keys and other entries; create file or key when absent; UTF-8 without BOM; write through a temp file and move; compare paths case-insensitively; path override `AGENTFLOW_AGY_SETTINGS` (used by tests so the real file is never touched). Removal: `run-task.ps1 T-NNN -Cleanup` for developer worktrees (the Orchestrator runs it with the worktree removal), automatic for tester checkouts. Old stale entries already in the file are left alone. Codex and Claude Code need no equivalent: Codex is sandboxed by flags, Claude runs with `--dangerously-skip-permissions` (developer) or `--allowedTools` (tester).

### D6. Models: tiers in one table
Task File `Model: default | small | standard | strong | <explicit id>`. `default` or no line = today's behaviour, no new flag. Resolution order for a tier: env `AGENTFLOW_MODEL_<TOOL>_<TIER>`, then `tools/models.json`, else a launch error that lists the table. An explicit id must be listed for that tool in `models.json`, otherwise preflight refuses. No model id in the scripts. The resolved model is recorded per attempt and printed.

Draft table (ids to be verified against vendor documentation before writing; `verifiedAt` date stored in the file):

| Tier | Claude Code | Codex | Antigravity CLI |
|---|---|---|---|
| small | Haiku 4.5 (`claude-haiku-4-5-20251001`) | Luna | Flash |
| standard | Sonnet 5.5 (`claude-sonnet-5-5`) | Terra | Flash (High) |
| strong | Opus 5.5 (`claude-opus-5-5`) | Sol | Pro, if available |

Sources found so far are third-party (the OpenAI tiers Sol / Terra / Luna: flagship / balanced / cheap; GPT-5.6 generally available 2026-07-09; GPT-6 Sol and Luna reported 2026-09-22). The generation currently offered in Codex CLI and the exact ids are not confirmed.

### D7. Layout (3.0.0)
Template code lives in `.agentflow/`; the project's own data stays in the project root. Entry points stay at the root because tools look for them there. Detailed in section 6.

## 4. Release 2.2.0: alarm, closing, trust

Prerequisite: P11 (memory refresh) so the session log and handoff match `main`.

### 4.1 `tools/gate.py`: `result T-NNN` (started, untested, uncommitted)
- `last_result`, `loose_field`, `result_state` are written. Fix before use: a captured value followed by `|` on the same line must be ignored (a pasted `Outcome: completed | blocked | failed` or `Verdict: pass | partial ...` currently matches its first word).
- Output JSON: `taskId`, `role`, `outcome`, `roleField`, `roleValue`, `class`, `problem`, `hash` (of the Result body, for the stable-text rule).
- `verify` keeps its strict `field()` parsing: tolerant for waking, strict for acceptance. Report in `result` when the strict reading differs (`formatOk`) so the Orchestrator knows verify will fail before running it.
- Update the module docstring (new subcommand).

### 4.2 `tools/run-task.ps1`
1. `-Wait [T-NNN ...] [-PollSec 30] [-TimeoutMin N] [-GraceSec 20]`.
   - No ids: every task whose last attempt is `running` (including `dead`) or manual-running. Nothing to wait for: print `nothing to wait for`, exit 4.
   - Each poll: read the attempt state (`Test-Alive` for `dead`), call `gate.py result`, apply D2.
   - Return at the first finished task; print exactly one line: `T-001 finished: attempt=<state> result=<class> [<field>=<value>] [problem=...] [limit]`. No log content.
   - Exit codes: 0 finished, 3 timeout, 4 nothing to wait for; gate errors throw (exit 1).
   - Pure shell and Python, no model, no network.
2. `Stop-Attempt` function extracted from `-Stop`; implements D4 for both `-Stop` and `-Wait`. `Complete-Attempt` keeps running the end check.
3. `Set-AgyTrust` before the launch (replaces the "make sure the folder is trusted" message), `Remove-AgyTrust` in `-Cleanup T-NNN` and in `Remove-Checkout` for testers. Both read the path from `AGENTFLOW_AGY_SETTINGS` when set.
4. `-Cleanup T-NNN`: removes trust entries recorded for the task's attempts (`workdir`). It does not remove the worktree: Git rules keep that with the Orchestrator.
5. Help text and examples at the top of the script updated.

### 4.3 Documents (each rule once; the protocol is the source, others point to it)
- `docs/ai-handoff-protocol.md`:
  - Runtime state, rule 3: replace slow `-Status` polling with `-Wait` in the host's background mode (foreground with the tool's longest command timeout if it has none; polling fallback); state that the wake works only while the Orchestrator session is open; Result filled on an interactive tool: `-Wait` or `-Stop` closes it as `exited`.
  - New subsection or rule for the completion classes (D3) and the finished definition (D2).
  - Launching workers: the launcher pre-approves the worker's folder where the tool needs it (D5).
  - Git rules, rule 6: add `run-task.ps1 T-NNN -Cleanup` after removing the worktree.
  - Task lifecycle table: row `failed, empty Result, attempt error or dead` stays; add `incomplete` to the same row family.
- `roles/orchestrator.md`: the loop starts `-Wait` in the background after each launch and acts when it returns; Save-tokens list: read only the printed line, the `## Result`, and the verify output.
- `roles/tool-routing.md`, Tool notes: per tool how the Orchestrator waits; remove "the worktree must be in its trusted folders"; Antigravity CLI is closed by the launcher.
- Role files' Result formats are unchanged; `roles/*.md` get a one-line note where the worker writes `Outcome:` last, after the commit, so the grace rule and the clean-worktree check hold.
- `GUIDE.md`: one paragraph for the human: the Orchestrator wakes by itself; keep its session open while workers run; what happens when the session is closed.
- `dashboard/`: show the completion class next to the task state if `build.py` already reads the runtime state; check `dashboard/README.md` data contract first, change only if it fits (rules in `dashboard/UI-RULES.md`).
- `CHANGELOG.md` 2.2.0 and `AGENTS.md` version line; the migration note: copy `tools/`, `docs/ai-handoff-protocol.md`, `roles/`, `GUIDE.md`; no Task File or ledger changes.
- Fill `## Result` in the first request file (it stays local) and note what was shipped.

### 4.3.1 Sandbox verification (throwaway repository, as for 2.0.0)
No real CLI is needed for the alarm: the tests write Task Files and runtime JSON directly and use a placeholder process (`pwsh -Command Start-Sleep`) for `running` / `dead`.
1. `-Wait` returns within one poll interval after the attempt leaves `running`, and within poll + grace after a stable `Outcome:` appears while the process still runs.
2. Each row of the D3 matrix produces its line; output is one line per task, nothing from logs.
3. A Result quoting "`## Result`" and a pasted format line do not hide or fake the Outcome.
4. Timeout gives exit 3; nothing running gives exit 4; several tasks return at the first finished one.
5. Interactive attempt, Outcome filled, clean worktree: closed as `exited`, end check ran, `gate.py verify` passes. Dirty worktree: not closed, line says so. `-Stop` without Outcome: `error`.
6. Trust: entry added on a fresh launch (`AGENTFLOW_AGY_SETTINGS` pointed at a temp file), other entries and unknown keys unchanged, file absent is created, `-Cleanup` removes only this entry, tester checkout removes its entry automatically.
7. Then one real run per tool on a scratch task (Stage 3 evidence): at least agy for the close path and Claude for the background wake.

### 4.4 Exit criteria
All acceptance criteria of request 1 and its addendum met; the matrix passes; docs say the same flow once; CHANGELOG written; known issue "Antigravity IDE cannot be automated" unchanged, the new agy `exited` path noted.

## 5. Release 2.3.0: model per task

### 5.1 Research before code
Verify against current vendor documentation, and record the dates:
- Anthropic: model ids and the recommended use of Opus / Sonnet / Haiku; Claude Code `--model`; effort settings, if any.
- OpenAI: the current Codex CLI models (Sol / Terra / Luna generation), `-m`, reasoning effort settings, recommended use per tier, how the plan limits count per model.
- Google: Antigravity CLI model names and whether the model can be set per run (flag or settings only).
- Public practice on routing: cheap model for mechanical work, strong model for review and for silent-failure code, escalate after repeated failure.
Do not copy the request's starting table; keep what is confirmed, mark the rest as practice.

### 5.2 Changes
1. `tasks/_template.md`: optional `Model:` in the header; one-line comment with the allowed values.
2. `tools/models.json`: per tool, tiers -> id, the list of accepted ids, `verifiedAt`. Overridable by `AGENTFLOW_MODEL_<TOOL>_<TIER>`.
3. `tools/gate.py`: parse `Model`; preflight refuses an unknown tier or an id the table does not list for the tool, with the valid values (the `-Manual` Deployer: the field is informational); the resolved model is part of the task JSON.
4. `tools/run-task.ps1`:
   - claude: `--model <id>`; codex: `-m <id>` replacing any `-m` / `--model` in `AGENTFLOW_CODEX_ARGS` (the task wins); agy: its option if it has one, else set `model` in its settings for the run and restore it afterwards (same atomic-write helper as the trust entry; restore also in `-Stop` and `-Cleanup` paths), else a warning "model not selectable".
   - No `Model:` or `default`: no new arguments, byte-for-byte today's command line.
   - Record `model` per attempt in `T-NNN.json`; print it in the launch line and in `-Status`.
5. `-Limits` (or part of `-Status`): last `limitHit` per tool with the matching log line and the reset time when the log gives one. Needs the worker end step to store the matching line (`limitText`, at most 200 characters) next to `limitHit`.
6. Selection guidance, `roles/tool-routing.md`, section "Choosing the model":

| Task kind | Tier |
|---|---|
| mechanical: skeleton, config, renames, Task File and doc fixes, glue | small |
| ordinary feature with clear criteria and tests | standard |
| Tester of a risky or user-visible change; mutation or adversarial reading | strong |
| silent or costly failure: access control, writes to external systems, data loss, security, concurrency, probabilistic output | strong |
| large read-only reading of code or logs | the tool with the longest context; tier by risk |
| Deployer | not chosen by the Orchestrator: the model of the human's designated session |

   Rules: (a) a task that failed twice on `standard` is retried on `strong` before it is split or rejected again; (b) the Orchestrator may lower the tier when the quota is short and the task is low risk, never for the Tester of a risky change; (c) a choice that differs from the table goes to the ledger `Notes` with the reason; (d) start at the cheapest tier that fits the risk.
7. Docs: protocol (Launching workers: the model is part of the launch and is recorded), `roles/orchestrator.md` (fill `Model:`, point to tool-routing), `GUIDE.md` (how to change the table and override per machine), CHANGELOG 2.3.0, AGENTS version line. Migration: add the `Model:` line optionally; copy `tools/models.json`.
8. `dashboard/`: add a Model column if the data contract allows it.
9. `Effort:` (decided 2026-10-06): optional Task File field `Effort: default | low | medium | high` mapped per tool in `models.json` to the tool's own reasoning-effort option, only for tools whose vendor documentation recommends and exposes it (to verify in 5.1); absent or `default` = no flag. Recorded per attempt like the model; guidance rows in "Choosing the model" (for example mechanical work low, review and risky code high).

### 5.3 Verification
- `Model: strong` launches claude with `--model <id from the table>` and codex with `-m <id>`; the id comes from `models.json` or the env override.
- The launch line, `T-NNN.json`, and `-Status` show the model.
- Unknown tier or id: refused with the valid list; no `Model:` line: command line unchanged (compare against 2.2.0 output).
- Test the agy path on the machine that has it (flag or settings substitution plus restore).
- Every statement in "Choosing the model" has a vendor source or is labelled practice.

## 6. Release 3.0.0: `.agentflow/`

Breaking: migration required. Start only after 2.2.0 and 2.3.0 are in a pilot project.

### 6.1 Decisions
1. Decided by the human 2026-10-06: everything that belongs to AgentFlow lives in `.agentflow/`, project memory included: template code (`docs/ai-handoff-protocol.md`, `roles/`, `tools/`, `dashboard/`, `commands/`, `GUIDE.md`, `CHANGELOG.md`) and AgentFlow data (`state/`, `tasks/`, `docs/project-plan.md`, `runbook/`, `screenshots/`). Only the entry points stay in the root: `AGENTS.md`, `CLAUDE.md`, `.claude/` (tools look for them there), plus the project's own files. Consequence: "update" replaces the template-owned parts of `.agentflow/` and must spare the data folders; the ownership list in the protocol names both sets explicitly, and the update procedure copies an allow-list, never the whole folder. Open: whether `docs/engineering-rules.md` (Project rules) moves too.
2. Pending (the human asks the colleague): what his `launch.ps1` and `tests/` are, and whether they belong in the template.
3. Template repository layout: the repository root mirrors a project root (`.agentflow/`, `AGENTS.md`, `CLAUDE.md`, `.claude/`) so "install" is a copy of those entries.

### 6.2 Work
1. Two roots in the scripts: `$agentflowRoot` (template code) and `$projectRoot` (data). `gate.py`: `ROOT` is split the same way; `TASKS`, `RUNTIME`, the ledger path (`tools/ledger.py`) resolve to the project root.
2. Every path in the protocol, roles, `AGENTS.md`, `CLAUDE.md`, `.claude/commands/*.md`, `GUIDE.md`, the Task File template, `dashboard/build.py`, `dashboard/serve.py`, `dashboard/snapshot.py` and its README: prefixed with `.agentflow/` where they point at template code. Link check over all Markdown after the move.
3. The "Installing or updating AgentFlow" procedure: update = replace `.agentflow/` and the two root entry files' template part; project data untouched. `.gitignore` entries move with the paths (`.agentflow/dashboard/out/`, `.agentflow/dashboard/versions/`, `tasks/.runtime/` stays).
4. Migration note for 2.x projects (move files, fix `.gitignore`, re-run the dashboard build) and a check script that lists leftovers at the old paths.
5. Sandbox: a fresh project installed from the new layout runs a full task cycle; a 2.3.0 project migrated by the note runs one.

### 6.3 Exit criteria
Install and update work by copying one folder plus the entry files; no template file outside `.agentflow/` except the entry points; all links and commands resolve; CHANGELOG 3.0.0 with the migration.

## 7. Roadmap changes (apply with the memory refresh, P11)

Edit `docs/project-plan.md` through the human's approval:
- Stage 2 (2.0.0): `closed` (P0-P4 committed, merged into `main`, 2.1.0 on top).
- Stage 3: rename to "Pilot and wake-up (2.2.0)": 2.2.0 shipped and one real project run with real codex / claude / agy. Exit criteria: the matrix passes in the sandbox; one full cycle in Calbot with `-Wait`; findings in `state/known-issues.md`.
- Stage 4: "Model per task (2.3.0)". Stage 5: ".agentflow layout (3.0.0)" (Stage 6 since 2.4.0 took Stage 5, 2026-10-09).
- `state/handoff.md`, `state/current-step.md`, `state/session-log.md` (entry for 2.1.0 and this plan).

## 8. Risks

| Risk | Mitigation |
|---|---|
| Auto-close kills a worker that is still writing | stable Result text for the grace period; developer worktree must be clean and `Change` must be on the branch; the end check stays |
| A tolerant keyword reader wakes on a pasted format line | ignore values followed by `|`; `verify` stays strict; `formatOk` reported |
| Editing the agy settings file corrupts the user's configuration | atomic write, keep unknown keys, tests only against `AGENTFLOW_AGY_SETTINGS`, never the real file |
| The wake works only while the Orchestrator session is open | stated in the protocol and GUIDE; the polling fallback exists |
| Model ids go stale | one table, `verifiedAt`, env override, a launch error that lists valid values |
| Vendor claims in guidance are wrong or old | verify against vendor docs first; practice labelled as practice; dated "As of" line in tool-routing |
| 3.0.0 breaks installed projects | last, with a migration note and a leftover check; 2.x stays documented in CHANGELOG |

## 9. Questions

Answered by the human 2026-10-06:
1. Automatic close inside `-Wait`: yes, with the developer clean-worktree guard, and only if it behaves the same on every run (the sandbox matrix must show no flaky case; otherwise ship manual `-Stop` only).
2. Layout for 3.0.0: all AgentFlow files including `state/` and `tasks/` inside `.agentflow/` (section 6.1).
3. Reasoning effort: add `Effort:` to 2.3.0 where the vendor documentation recommends it (section 5).

Considered, not taken (2026-10-07): a fast classifier model with confidence scores (TypeSafe "Jeff", OpenRouter `typesafe/jev-router`, OpenAI Decisions API, per a video the human shared; claims not verified). Not for the template core: Result detection, preflight, and tier choice must stay deterministic, free, and offline, and the workers are CLI subscriptions, not OpenRouter. The router picks the cheapest adequate model, not the strongest, which conflicts with "strong" for risky code. Possible later as an optional advisory guard on `## Checks` commands, never instead of the deny rules. Better fit: project-level classification (for example Calbot message routing), decided in that project.

Open:
4. REMINDER for the human: ask the colleague where his `launch.ps1` and `tests/` come from and whether `tests/` belongs in the template. Blocks 3.0.0 only.
5. Whether `-Cleanup` should also remove the worktree and branch (today the Orchestrator does it by Git rule 6).
