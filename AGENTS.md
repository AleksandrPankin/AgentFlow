# Agent Instructions

<!-- agentflow:start -->
## AgentFlow

AgentFlow version: 3.0.0

Read by Codex CLI, Antigravity, Antigravity CLI, and other AGENTS.md-aware tools. Claude Code reads it through `CLAUDE.md`. This block belongs to AgentFlow: an install or update replaces only the text between the markers.

This project uses AgentFlow: project memory and team roles. `.agentflow/` is the AgentFlow machine (same in every project); `docs/` is this project's knowledge: product, plan, tasks, state, runbook. Source of truth: `.agentflow/protocol.md`: a session without a role and the Orchestrator read it first; a worker reads only the sections "Starting a role session" names. Rule order (what may add to or override what): protocol, Standing rules.

If you were given a role (`.agentflow/roles/<role>.md`, or `/start-role <role> ...`): run protocol section "Starting a role session" and follow your role file. Workers (developer, tester, deployer) do not update project memory.

Without a role (Single Mode): before substantial work run protocol section "Starting a new AI session"; before ending a long session run "Updating memory", and "Updating the runbook" if a verified human-facing step changed.
<!-- agentflow:end -->

## Project rules

Project-specific rules go here, outside the AgentFlow block, or in `docs/engineering-rules.md` (protocol, Terms: Project rules): code and run rules, the `<worktrees>` folder, `## Preflight`, `## Tool routing` notes, and `## Deploy` (platform project folder, contract, request file, deploy script) for this project.
