# Claude Project Instructions

<!-- agentflow:start -->
## AgentFlow

@AGENTS.md

Slash commands, each runs one section of `.agentflow/protocol.md`:

- `/start-role <role> [task file]` -> "Starting a role session"
- `/start-session` -> "Starting a new AI session"
- `/update-memory` -> "Updating memory" (Orchestrator or Single Mode only)
- `/handoff-cmd` -> "Handoff (short transfer note)" (Orchestrator or Single Mode only)
- `/update-runbook` -> "Updating the runbook" (Orchestrator or Single Mode only)

These are also plain Markdown files under `.claude/commands/`, readable as `@.claude/commands/<name>.md` from Codex or any tool that supports file references.
<!-- agentflow:end -->
