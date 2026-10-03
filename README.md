# AgentFlow

AI Project Memory — Team Edition.

Tool-agnostic project memory plus four agent roles, so several AI sessions (Claude Code, Codex, Antigravity, ...) can work on one project without losing state or overwriting each other.

Base version without roles: `ai-project-memory-pankin`. Use this one when a project is run by an orchestrator and worker sessions.

## Model

```text
Role    — how to work            roles/*.md        (same in every project)
Task    — what to do now         tasks/T-NNN-*.md  (written by the orchestrator)
Memory  — where the project is   state/, docs/     (written by the orchestrator only)
Session — who is doing it now    fresh chat, one task, then closed
```

| Role | File | In one line |
|---|---|---|
| Orchestrator | [roles/orchestrator.md](roles/orchestrator.md) | Splits goals into tasks, accepts results, merges, the only writer of memory |
| Developer | [roles/developer.md](roles/developer.md) | One task: code + own test + one commit |
| Tester | [roles/tester.md](roles/tester.md) | Independently verifies against criteria, fixes nothing |
| Deployer | [roles/deployer.md](roles/deployer.md) | Deploys an accepted commit, smoke-checks, rolls back on failure |

Which tool gets which task (Claude Code, Codex CLI, Antigravity, Antigravity CLI), with token budget in mind: [roles/tool-routing.md](roles/tool-routing.md). Read by the orchestrator only.

Full rules, terms, git rules, planning levels, and permissions table: [docs/ai-handoff-protocol.md](docs/ai-handoff-protocol.md) — single source of truth. Everything else (`AGENTS.md`, `CLAUDE.md`, `.claude/commands/*.md`, `roles/*.md`) points into its sections instead of repeating rules.

## Structure

```text
docs/ai-handoff-protocol.md   <- source of truth: terms, planning levels, standing rules, roles & memory ownership, git rules, session steps, task lifecycle
docs/project-plan.md          <- living roadmap: stages
roles/*.md                    <- orchestrator, developer, tester, deployer
roles/tool-routing.md         <- which tool for which task; orchestrator only
tasks/_template.md            <- Task File template; tasks/T-NNN-slug.md are created from it
tools/run-task.ps1            <- launcher: worktree + environment + visible window + log; process state + one-worker lock in tasks/.runtime/
tools/ledger.py               <- add/set/show rows of the Task Ledger (no one-off scripts)
state/tasks.md                <- Task Ledger: one row per task, status
state/handoff.md              <- short transfer note for the next AI session
state/current-step.md         <- current practical step only
state/decisions.md            <- decisions + reasons, dated
state/known-issues.md         <- failed attempts, dead ends, constraints
state/session-log.md          <- chronological work log
runbook/clean-instruction.md  <- in this template: how to install and use it (not copied into projects)
screenshots/                  <- visual evidence, linked from the runbook (create on first use)
AGENTS.md                     <- entry point for Codex, Antigravity, other AGENTS.md-aware tools; points to the protocol
CLAUDE.md                     <- Claude Code entry point: imports AGENTS.md + slash commands
.claude/commands/*.md         <- slash commands, also readable as @-references by Codex etc.
.claude/settings.example.json <- example permission deny-list for secrets
```

## Install and daily use

Step-by-step human guide (new project, existing project with memory, daily work with the orchestrator): [runbook/clean-instruction.md](runbook/clean-instruction.md).

Do not copy the whole folder with `-Force`: it would overwrite an existing project's `README.md`, `CLAUDE.md`, and memory. `README.md` and `runbook/` of this template stay here; a project creates its own `runbook/` on the first verified step. Do not edit `roles/` per project unless the role itself is wrong.

## Usage

### Team Mode

Orchestrator session:

```text
/start-role orchestrator
Goal: <what I want>.
```

Worker session (always a fresh chat, one task):

```text
/start-role developer tasks/T-101-api.md
```

Codex, Antigravity, or any tool without slash commands (they read `AGENTS.md` themselves):

```text
Your role: roles/developer.md. Your task: tasks/T-101-api.md.
Follow docs/ai-handoff-protocol.md, section "Starting a role session".
```

Cycle:

```text
Human: goal
 -> Orchestrator: tasks T-101, T-102 (scope, allowed files, criteria), ledger "ready"
 -> Developer A / B: fresh session per task, own worktree <worktrees>\<repo>-t-NNN-slug,
    branch t-NNN-slug, one commit [T-101], ## Result (parallel if files do not overlap)
    all safe-parallel ready tasks launched at once by tools/run-task.ps1
 -> Orchestrator: polls run-task.ps1 -Status (not the human), accepts on evidence, refills free slots
 -> Tester: verdicts with evidence (required for user-visible or risky changes)
 -> Orchestrator: gate.py verify, accept (done) or reject (rejected + successor task), merge, remove worktree + branch
 -> Deployer (the session the human designated): dependency first, smoke before and after, ## Result
 -> Orchestrator: /update-memory, /handoff-cmd
```

### Single Mode

No role — one session does everything, same as the base template.

**Claude Code:** `/start-session`, `/update-memory`, `/handoff-cmd`, `/update-runbook`.

**Other tools:** reference the same files, e.g. `@.claude/commands/start-session.md`, or point at `docs/ai-handoff-protocol.md` and name the section.

Starting a session:

```text
Read docs/ai-handoff-protocol.md, then read state/handoff.md and continue from exactly where we left off.
Do not repeat failed attempts listed in known-issues.
```

Ending a session:

```text
Update AI Project Memory according to docs/ai-handoff-protocol.md.
Keep handoff short, preserve failed attempts, update current-step, update the clean runbook with verified steps, and do not write secrets.
```

Recommended end-of-session order: update-runbook (only if a verified step changed) -> update-memory -> handoff-cmd.

Note: `/handoff-cmd` (not `/handoff`) — named to avoid clashing with `state/handoff.md` when referenced by filename.

## Safety

- Never write secrets to Markdown: passwords, tokens, private keys, recovery codes, cookies.
- Don't invent screenshots or files.
- Keep `runbook/` free of failed attempts and intermediate noise — that goes in `state/known-issues.md` or `state/session-log.md`.
- In Team Mode only the Orchestrator writes memory; a production deploy needs the human's approval inside the Deployer session.
