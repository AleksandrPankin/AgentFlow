# AgentFlow

Project memory and four agent roles for running one software project with several AI coding sessions (Claude Code, Codex CLI, Antigravity) without losing state or overwriting each other's work.

- **Orchestrator**: one session that splits the goal into tasks, launches workers, accepts results on evidence, and is the only writer of project memory.
- **Developer, Tester, Deployer**: fresh sessions, one task each, started through `tools/run-task.ps1`.
- **Product definition** (optional): Vision, Brief, PRD, Architecture in `docs/product/`; tasks reference requirement IDs, and the launcher refuses a task whose requirements are unchecked.
- **The human** gives the final word through a task queue (`state/owner-tasks.md`) that the work does not wait for, except keys, production approval, server changes, money, and irreversible steps.

All rules live in one file, [docs/ai-handoff-protocol.md](docs/ai-handoff-protocol.md). Everything else points there.

## Contents

| Path | What |
|---|---|
| `docs/ai-handoff-protocol.md` | the protocol: terms, states, rules, session steps |
| `roles/` | one instruction file per role; `tool-routing.md`: which tool takes which task |
| `tasks/_template.md` | Task File template |
| `templates/` | copied into a project once: `product/` (Vision, Brief, PRD, Architecture, readiness review, explanations for the human; Russian) and `owner-tasks.md` (the human's task queue) |
| `tools/` | `run-task.ps1` launcher, `gate.py` preflight / verify / Stage check, `ledger.py` Task Ledger |
| `dashboard/` | read-only view for the human: task table, filters, Gantt, timeline (`python dashboard/build.py`); see `dashboard/README.md` |
| `AGENTS.md`, `CLAUDE.md`, `.claude/commands/` | entry points for the tools |
| `GUIDE.md` | step-by-step guide (Russian): install, update, daily use |
| `CHANGELOG.md` | what changed in each version |

Requirements: git, Python 3, PowerShell 7 on Windows, and the CLIs of the tools you use.

## Start

Install and daily use: [GUIDE.md](GUIDE.md). In Claude Code the Orchestrator starts with `/start-role orchestrator` and your goal; a session without a role uses `/start-session`.

License: MIT.
