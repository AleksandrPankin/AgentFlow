# Agent Instructions

AgentFlow version: 2.0.0

Read by Codex CLI, Antigravity, Antigravity CLI, and other AGENTS.md-aware tools. Claude Code reads it through `CLAUDE.md`.

This project uses AI Project Memory with team roles. Source of truth: `docs/ai-handoff-protocol.md`. Read it first, then follow it. Rule order (what may add to or override what): protocol, Standing rules.

If you were given a role (`roles/<role>.md`, or `/start-role <role> ...`): run protocol section "Starting a role session" and follow your role file. Workers (developer, tester, deployer) do not update project memory.

Without a role (Single Mode): before substantial work run protocol section "Starting a new AI session"; before ending a long session run "Updating memory", and "Updating the runbook" if a verified human-facing step changed.

## Project rules

Project-specific rules go below this heading or in `docs/engineering-rules.md` (protocol, Terms: Project rules): code and run rules, the `<worktrees>` folder, `## Preflight`, and `## Tool routing` notes for this project. A template update replaces only the part of this file above this heading.
