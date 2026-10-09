# AgentFlow

Project memory and four agent roles for running one software project with several AI coding sessions (Claude Code, Codex CLI, Antigravity) without losing state or overwriting each other's work.

- **Orchestrator**: one session that splits the goal into tasks, launches workers, accepts results on evidence, and is the only writer of project memory.
- **Developer, Tester, Deployer**: fresh sessions, one task each, started through `.agentflow/tools/run-task.ps1`.
- **Product definition** (optional): Vision, Brief, PRD, Architecture in `docs/product/`; tasks reference requirement IDs, and the launcher refuses a task whose requirements are unchecked.
- **The human** gives the final word through a task queue (`docs/state/owner-tasks.md`) that the work does not wait for, except keys, production approval, server changes, money, and irreversible steps.

All rules live in one file, [.agentflow/protocol.md](.agentflow/protocol.md). Everything else points there.

## Layout of a project

| Path | Owner | What |
|---|---|---|
| `.agentflow/` | template | the AgentFlow machine, the same in every project; an update replaces it as a whole |
| `AGENTS.md`, `CLAUDE.md`, `.gitignore` | project | AgentFlow owns only its block between `agentflow:start` and `agentflow:end` |
| `.claude/commands/` | template | the five AgentFlow slash commands |
| `docs/` | project | the project's knowledge in one flow: `product/` -> `plan.md` -> `tasks/` -> `state/` -> `runbook/`; an update never touches it |

Inside `.agentflow/`:

| Path | What |
|---|---|
| `protocol.md` | the protocol: terms, states, rules, session steps |
| `install.md` | install, update, migrate from 2.x: the procedure an LLM session follows |
| `roles/` | one instruction file per role; `tool-routing.md`: which tool takes which task |
| `tools/` | `run-task.ps1` launcher, `gate.py` preflight / verify / Stage check, `ledger.py` Task Ledger |
| `templates/` | skeletons copied into `docs/` once: Task File, product documents, owner tasks |
| `guide/` | for the human (Russian): `GUIDE.md` (install, daily use) and the product explanations |
| `dashboard/` | read-only view for the human: task table, filters, Gantt, timeline (`python .agentflow/dashboard/build.py`) |
| `CHANGELOG.md` | what changed in each version, with migration notes |

This repository mirrors a project: its own `docs/` is the template's memory, and `dev/` holds regression checks of the tools (`python dev/test_gate_spec.py`); neither is copied into projects.

Requirements: git, Python 3, PowerShell 7 on Windows, and the CLIs of the tools you use.

## Start

Install into a project: in Claude Code say "внедри AgentFlow" (skill `integrate-agentflow`); in another tool: "follow `<AgentFlow>/.agentflow/install.md` for this project". Daily use: [.agentflow/guide/GUIDE.md](.agentflow/guide/GUIDE.md). The Orchestrator starts with `/start-role orchestrator` and your goal; a session without a role uses `/start-session`.

License: MIT.
