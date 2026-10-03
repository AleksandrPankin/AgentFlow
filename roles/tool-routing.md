# Tool routing

Which tool takes which task. Read by the [Orchestrator](orchestrator.md) only. The choice goes to `Tool:` in the Task File and to the ledger `Tool` column.

This file is shared by all projects and replaced on template update: notes from one project go to its Project rules, `## Tool routing`. As of 2026-10; the strengths below are defaults, not measurements: confirm them on your own tasks.

## How to choose

1. Fit: the tables below.
2. Remaining limit: at session start the human says what is left per tool. Not said: ask in one line. Do not write limits to memory.
3. Expensive tools only where a mistake is expensive: mechanical edits, renames, simple tests go to the cheapest fitting tool or a smaller model.
4. Tester on a different tool than the Developer when possible: another model has other blind spots. Codex first: only there [review isolation](../docs/ai-handoff-protocol.md#terms) is a sandbox.

## Tools

| Tool | Strong | Weak |
|---|---|---|
| Claude Code | complex multi-file work and architecture; long action chains; project memory (`CLAUDE.md`, commands) | more tokens per task; limits per time window |
| Codex CLI | fewer tokens per task; sandbox modes; small models for simple tasks; reads `AGENTS.md` | large multi-file changes |
| Antigravity (IDE) | built-in browser agent: sites, screen widths, screenshots | not automatable: `-Manual` only |
| Antigravity CLI | context up to 1M tokens: large code, logs, dumps; fast models; free quota | young; slows down when the quota ends; soft confirmations: never production |

## Routing

| Task | First choice | Fallback |
|---|---|---|
| Orchestrator: plan, split, accept | Claude Code | Codex |
| Developer: complex, several files, architecture | Claude Code | Codex (larger model) |
| Developer: small, isolated, clear criteria | Codex (smaller model) | Antigravity CLI |
| Tester: code review, test runs | Codex | Claude Code |
| Tester: interface in a browser, widths, screenshots | Antigravity (IDE) | Claude Code + Playwright |
| Reading large code, logs, data | Antigravity CLI | Claude Code |
| Deployer | the tool where server access and the runbook are set up: Claude Code or Codex | never Antigravity CLI for production |

## Fallback by limit

Used when `-Status` shows `limitHit=True`, or the attempt is `dead` / `error` without a Result, after the lock is released ([Recovery](../docs/ai-handoff-protocol.md#recovery-stale-task), rule 7).

| Out of | Use instead |
|---|---|
| Claude Code | Codex (larger model) |
| Codex | Antigravity CLI (`-i`); for review: Claude Code |
| Antigravity CLI | Codex |

No tool left: the task is `blocked` and one line to the human. Orchestrator out of Claude limit: hand the role to Codex through `state/handoff.md`; Claude stays for splitting and disputed acceptance.

## Tool notes

- Launch: `tools/run-task.ps1 T-NNN <codex|claude|agy>`. Machine settings are environment variables, not script edits: `AGENTFLOW_CODEX` (codex path, `*` allowed, the newest match wins), `AGENTFLOW_CODEX_ARGS` (for example `-m <model>`).
- Antigravity CLI: interactive only (`-i`); `-p` prints nothing until the end, so work and a hang look the same.
- Antigravity: the worktree must be in its trusted folders before the first run; the first run passes the setup wizard by hand once. Error 500: retry, not a task failure.
- Antigravity (IDE): `tools/run-task.ps1 T-NNN -Manual`, the human starts the task, then `-MarkFinished`.
- Prompt for tools without slash commands (they read `AGENTS.md` themselves): `Your role: roles/<role>.md. Your task: tasks/T-NNN-slug.md. Follow docs/ai-handoff-protocol.md, section "Starting a role session".` Claude Code: `/start-role <role> tasks/T-NNN-slug.md`.
