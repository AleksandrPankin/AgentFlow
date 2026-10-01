# Decision Log

This file records decisions that affect future project work. If the approach changes later, add a new decision below instead of deleting old context without a reason.

## 2026-05-21

### AI Project Memory

Decision: add the baseline AI Project Memory structure: protocol, handoff, current-step, decisions, known-issues, and session-log.

Reason: long AI sessions lose context, repeat old errors, and forget why decisions were made. A short handoff should be the entry point, while details live in specialized files.

## 2026-10-01

### Team roles and single memory writer

Decision: add four roles (orchestrator, developer, tester, deployer), Task Files in `tasks/`, and the Task Ledger `state/tasks.md`. In Team Mode only the Orchestrator writes Canonical Memory; workers write only their task Result.

Reason: several sessions updating handoff/current-step in parallel create conflicting versions of project state. Workers need only their role and task, not the whole project history.

### Git rules: one task = one branch + one worktree, mandatory cleanup

Decision: each developer task gets its own branch `t-NNN-slug` and worktree `<worktrees>\<repo>-t-NNN-slug` (a folder outside the repository and cloud sync); the main folder stays on the main branch and belongs to the Orchestrator; workers do not launch sub-agents; after merge the Orchestrator removes the worktree and the branch.

Reason: a no-worktree rule (taken from a colleague's AGENTS.md) was considered, but real practice on an earlier project showed worktrees outside the repository working: 36 of 37 task branches merged into main. The actual problem was missing cleanup: 33 merged worktrees left hanging. Worktrees keep parallel work; the cleanup rule removes the mess.

### Tool routing by fit and budget

Decision: the Orchestrator picks the tool per task (Claude Code, Codex CLI, Antigravity, Antigravity CLI) using `roles/tool-routing.md` and the limits the human reports; the choice is written in the Task File and ledger.

Reason: tools differ in strengths and token cost; spending the most capable tool on mechanical work wastes limits.
