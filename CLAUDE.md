# Claude Project Instructions

@AGENTS.md

## Slash commands

- `/start-role <role> [task file]` -> protocol section "Starting a role session"
- `/start-session` -> protocol section "Starting a new AI session"
- `/update-memory` -> protocol section "Updating memory" (Orchestrator or Single Mode only)
- `/handoff-cmd` -> protocol section "Handoff (short transfer note)" (Orchestrator or Single Mode only)
- `/update-runbook` -> protocol section "Updating the runbook" (Orchestrator or Single Mode only)

These are also plain Markdown files under `.claude/commands/`, readable as `@.claude/commands/<name>.md` from Codex or any tool that supports file references.
