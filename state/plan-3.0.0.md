# Implementation Plan: 3.0.0 and open items

Status: 3.0.0 open. Template-owned working document (not copied into projects); deleted when 3.0.0 ships, the result goes to `CHANGELOG.md` and `state/decisions.md`. Earlier plans are in git: `state/plan-2.2-3.0.md` (2.2.0, 2.3.0, 3.0.0 draft) and `state/plan-2.4.0.md` (2.4.0, FPF findings S1-S18, `gate.py` matrix of 28 cases), both as of commit `5f74ce3`.

## 1. Release 3.0.0: template in `.agentflow/`

Breaking: migration required. Start only after 2.2.0-2.4.0 run in a pilot project.

### 1.1 Decisions
1. Decided by the human 2026-10-06: everything that belongs to AgentFlow lives in `.agentflow/`, project memory included: template code (`docs/ai-handoff-protocol.md`, `roles/`, `tools/`, `dashboard/`, `templates/`, `commands/`, `GUIDE.md`, `CHANGELOG.md`) and AgentFlow data (`state/`, `tasks/`, `docs/project-plan.md`, `runbook/`, `screenshots/`). Only the entry points stay in the root: `AGENTS.md`, `CLAUDE.md`, `.claude/` (tools look for them there), plus the project's own files. "Update" replaces the template-owned parts of `.agentflow/` and spares the data folders; the ownership list in the protocol names both sets, and the update copies an allow-list, never the whole folder.
2. Template repository layout: the root mirrors a project root (`.agentflow/`, `AGENTS.md`, `CLAUDE.md`, `.claude/`), so "install" is a copy of those entries.

### 1.2 Work
1. Two roots in the scripts: `$agentflowRoot` (template code) and `$projectRoot` (data). `gate.py`: `ROOT` split the same way; `TASKS`, `RUNTIME`, `PRODUCT`, the ledger path (`tools/ledger.py`) resolve to the data root. `python dev/test_gate_spec.py` passes after the split (adapt its copy paths to the new layout).
2. Every path in the protocol, roles, `AGENTS.md`, `CLAUDE.md`, `.claude/commands/*.md`, `GUIDE.md`, the Task File template, `templates/`, `dashboard/build.py`, `dashboard/serve.py`, `dashboard/snapshot.py` and its README: prefixed with `.agentflow/` where they point at template code. Link check over all Markdown after the move.
3. "Installing or updating AgentFlow": update = replace the template-owned parts of `.agentflow/` and the two root entry files' template part; project data untouched. `.gitignore` entries move with the paths.
4. Migration note for 2.x projects (move files, fix `.gitignore`, rebuild the dashboard) and a check script that lists leftovers at the old paths.
5. Sandbox: a fresh project installed from the new layout runs a full task cycle; a 2.4.0 project migrated by the note runs one.

### 1.3 Exit criteria
Install and update work by copying one folder plus the entry files; no template file outside `.agentflow/` except the entry points; all links and commands resolve; CHANGELOG 3.0.0 with the migration.

## 2. Open questions

1. REMINDER for the human: ask the colleague where his `launch.ps1` and `tests/` come from and whether `tests/` belongs in the template. Blocks 3.0.0 only. If `tests/` comes in, `dev/test_gate_spec.py` (2.4.0, 28 cases) moves there; the 2.2.0 and 2.3.0 matrices were never committed (cases in `plan-2.2-3.0.md`, D3, at `5f74ce3`).
2. Does `docs/engineering-rules.md` (Project rules) move into `.agentflow/`?
3. Does `docs/product/` move into `.agentflow/`? It is the product's own documents, human-facing, not AgentFlow data: proposal - it stays in the project.
4. Should `-Cleanup` also remove the worktree and branch (today the Orchestrator does it by Git rule 6)?
5. Optional stall detector for `-Wait` (a fast classifier on a silent worker's log tail): decide after the pilot; needs from the human how often workers hung on a question, and whether project logs may go to an external service (decisions, 2026-10-07).

## 3. Later (from 2.4.0)

- Reintegrate live projects into 2.4.0: path `00_PRD/` -> `docs/product/`, `T01..` -> `AR01..`, `Spec:` lines, `- **Статус:**` lines; owner tasks already in place. The human does it by hand first and brings feedback (Stage 5).
- The platform project (04) names the deploy session per product project in its own contracts; it already reads the product projects' request files.
- Dashboard: owner tasks view; a `Spec` column if the data contract fits.
- Optional independent spec review by a fresh session before G2 / G3.
