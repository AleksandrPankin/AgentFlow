# Agent Instructions

Read by Codex CLI, Antigravity, Antigravity CLI, and other AGENTS.md-aware tools. Claude Code reads it through `CLAUDE.md`.

This project uses AI Project Memory with team roles. Source of truth: `docs/ai-handoff-protocol.md`. Read it first, then follow it. It contains the mandatory Standing rules and Git rules; nested `AGENTS.md`, role files, and Task Files may add rules but cannot cancel or weaken them.

If you were given a role (`roles/<role>.md`, or `/start-role <role> ...`): run protocol section "Starting a role session" and follow your role file. Workers (developer, tester, deployer) do not update project memory.

Without a role (Single Mode): before substantial work run protocol section "Starting a new AI session"; before ending a long session run "Updating memory", and "Updating the runbook" if a verified human-facing step changed.

Project-specific code rules, if any, live in `docs/engineering-rules.md`.
