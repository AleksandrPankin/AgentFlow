# Tool routing

Which tool takes which task. Read by the [Orchestrator](orchestrator.md) only. The choice goes to `Tool:` in the Task File and to the ledger `Tool` column.

This file is shared by all projects and replaced on template update: notes from one project go to its Project rules, `## Tool routing`. As of 2026-10; the strengths below are defaults, not measurements: confirm them on your own tasks.

## How to choose

1. Fit: the tables below.
2. Remaining limit: at session start the human says what is left per tool. Not said: ask in one line. Do not write limits to memory.
3. Expensive tools only where a mistake is expensive: mechanical edits, renames, simple tests go to the cheapest fitting tool or a smaller model ([Choosing the model](#choosing-the-model)).
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

## Choosing the model

The Task File names a tier, not a model: `Model: small | standard | strong` (or an id listed in [tools/models.json](../tools/models.json)), and `Effort: low | medium | high | xhigh | max`. `default` or no line = the tool's own setting. The launcher maps the tier to the tool's model, records it per attempt, and preflight refuses a value the table does not list. Tiers as of 2026-10-06 (`models.json`, `verifiedAt`):

| Tier | Claude Code | Codex | Antigravity CLI |
|---|---|---|---|
| small | Haiku 4.5 (no effort setting) | GPT-6 Luna | Gemini 3.8 Flash low |
| standard | Sonnet 5.5 | GPT-6.1 Sol | Gemini 3.8 Flash medium |
| strong | Opus 5.5 | GPT-6 Astra | Gemini 3.8 Flash high |

Above `strong`, by explicit id only and with a reason in the ledger `Notes`: `claude-fable-5-1` (Anthropic's most capable model, about 2.5x Opus 5.5 per token, long turns), `gemini-3.1-pro-high`.

| Task kind | Model | Effort |
|---|---|---|
| mechanical: skeleton, config, renames, Task File or doc fixes, glue | small | default (Codex, agy: low) |
| ordinary feature with clear criteria and tests | standard | default |
| Tester of a risky or user-visible change; adversarial or mutation reading | strong | high |
| silent or costly failure: access control, writes to external systems, data loss, security, concurrency, probabilistic output (routing, extraction) | strong | high or xhigh |
| large read-only reading of code, logs, data | the tool with the longest context, tier by risk | low |
| Deployer | not set by the Orchestrator: the human's designated session | - |

Rules:

1. Start at the cheapest tier that fits the risk; judge cost per accepted task, not per attempt: a cheap attempt that is rejected and redone costs more.
2. Before a stronger model, try more effort on the same one; a newer model at lower effort often matches an older one at high effort.
3. A task that failed twice on `standard` is retried on `strong` before it is split or rejected again.
4. Short quota and a low-risk task: lower the tier; never for the Tester of a risky change.
5. A choice that differs from the table goes to the ledger `Notes` with the reason.

Sources (2026-10-06): installed CLI help (`claude --help` 2.1.291, `codex exec --help` 0.130.0, `agy --help` and `agy models` 1.3.0); Anthropic model guidance (Opus 5.5 default model, Sonnet 5.5 for everyday coding and agents, Haiku 4.5 for sub-agents and simple tasks; effort `low` for simple tasks and sub-agents, at least `high` for intelligence-sensitive work, `max` when correctness outweighs cost); OpenAI model descriptions in the Codex model catalog (Astra "frontier intelligence for the most demanding work", 6.1 Sol "workhorse for coding and everyday work", Luna "fast and affordable for easier tasks"). Gemini Flash over Pro for coding agents is public practice, not a vendor statement. Rules 1, 3-5: AgentFlow practice.

## Tool notes

- Launch: `tools/run-task.ps1 T-NNN <codex|claude|agy>`. Machine settings are environment variables, not script edits: `AGENTFLOW_CODEX` (codex path, `*` allowed, the newest match wins), `AGENTFLOW_CODEX_ARGS` (for example `-m <model>`).
- Antigravity CLI: interactive only (`-i`); `-p` prints nothing until the end, so work and a hang look the same.
- Antigravity CLI: the launcher adds the worker folder to its trusted folders (`trustedWorkspaces` in `%USERPROFILE%\.gemini\antigravity-cli\settings.json`, override `AGENTFLOW_AGY_SETTINGS`) and `-Cleanup` removes it; the first run on a machine passes the setup wizard by hand once. Its window stays open after the work: `-Wait` closes it once the Result is filled. Error 500: retry, not a task failure.
- Waiting for workers (`-Wait`, protocol Runtime state rule 3): Claude Code as Orchestrator runs it with `run_in_background` and is woken on exit; Codex runs it in the foreground with a timeout (`-TimeoutMin`); a host with neither polls `-Status`.
- Antigravity (IDE): `tools/run-task.ps1 T-NNN -Manual`, the human starts the task, then `-MarkFinished`.
- Prompt for tools without slash commands (they read `AGENTS.md` themselves): `Your role: roles/<role>.md. Your task: tasks/T-NNN-slug.md. Follow docs/ai-handoff-protocol.md, section "Starting a role session".` Claude Code: `/start-role <role> tasks/T-NNN-slug.md`.
