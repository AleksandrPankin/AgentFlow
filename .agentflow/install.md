# Installing, updating, and migrating AgentFlow

For a session without a role that the human started in the target project ("внедри AgentFlow"; Claude Code: skill `integrate-agentflow`). The template is the AgentFlow folder the human named; read it, never edit it. Talk to the human in Russian.

Ground rules:

1. AgentFlow owns only `.agentflow/`, its block between `agentflow:start` and `agentflow:end` in `AGENTS.md`, `CLAUDE.md`, `.gitignore`, and its five commands in `.claude/commands/` ([protocol](protocol.md), section "Installing or updating AgentFlow"). Everything else is the project's: moved when needed, never rewritten.
2. Read before asking. Plan before changing. Change nothing before the human's "ok" on the plan; commit only after the human's "ok" on the diff.
3. No script copies or merges files: you read both sides and write.
4. No secrets in files; of `.env` read variable names only, never values.
5. Use the template from its main branch: `git -C <template> branch --show-current` is `main` or `master`; otherwise tell the human and stop.

## 1. Mode

Detect it before asking anything; tell the human in one line.

| Sign in the project | Mode |
|---|---|
| only `.git` and at most 3 own files | greenfield |
| a live project without AgentFlow | brownfield |
| AgentFlow 2.x or the older memory: `docs/ai-handoff-protocol.md`, `roles/orchestrator.md`, `tools/run-task.ps1`, `state/handoff.md`, `tasks/_template.md`, or `AgentFlow version: 2.` in `AGENTS.md` | migrate |
| `.agentflow/` with an older `AgentFlow version` than the template | update |
| the same version | repair: fill placeholders and missing files only; nothing wrong: say so and stop |

## 2. Reconnaissance

All modes except greenfield; about 15 tool calls; facts, not guesses.

1. The owner's rules: `AGENTS.md`, `CLAUDE.md`, `.cursorrules`, `.github/copilot-instructions.md`, `docs/engineering-rules.md`. They limit what you may do and are never rewritten.
2. `README.md` and manifests (`package.json`, `pyproject.toml`, `requirements.txt`, `*.csproj`, `Dockerfile`): name, stack, entry point, test commands.
3. Material the project already has: `docs/**`, `00_PRD/` or other folders and files named PRD, Vision, Brief, Architecture, ADR; an owner queue (`owner-tasks.md`); request files (`*-requests.md`). Headings and first paragraphs, not whole files.
4. Existing memory: `state/`, `tasks/`, `docs/project-plan.md`, `runbook/`; open tasks (ledger rows not `done`, `rejected`, `cancelled`).
5. `git log --oneline -40`, `git log -1 --format=%ad`, `git status --short`, `git worktree list`, branches `t-*`.
6. Test and run configs: can they reach staging or production by default (hosts, URLs, env defaults)?
7. `grep -rn "TODO\|FIXME" --include=*.md`.

Keep a project card in mind: name; what it is, in one line; stack; done; in progress; the owner's constraints; open questions; today's date; deploy (platform project, request file); a `<worktrees>` folder outside the repository and cloud sync.

## 3. Plan

Show the human the plan in Russian, short, and change nothing yet. Classify every path you will touch:

| Class | Paths | Action |
|---|---|---|
| CANON | `.agentflow/` as a whole, without local `dashboard/out/`, `dashboard/versions/`, `__pycache__/`; `.claude/commands/` `start-role.md`, `start-session.md`, `update-memory.md`, `handoff-cmd.md`, `update-runbook.md`; `.claude/settings.example.json` | copy from the template byte for byte; update: replace |
| BLOCK | `AGENTS.md`, `CLAUDE.md`, `.gitignore` | the template's block between the markers; the rest of the file stays |
| MOVE | what the project already has: product documents, an owner queue, 2.x memory | `git mv` into `docs/`, then only the format fixes the tools need |
| GENERATE | missing files in `docs/` | structure from `.agentflow/templates/`, text from the project card |
| KEEP | code, the owner's text, everything else | untouched |

Also list conflicts (a CANON file the project edited; owner text that contradicts AgentFlow) and your questions. Wait for "ok".

## 4. Apply

### 4.1 CANON

Copy `.agentflow/` and the five commands; other commands in `.claude/commands/` stay. Update and migrate: before replacing, compare the project's copy with the template at the project's version (`git -C <template> show v<version>:<path>` when that tag exists, otherwise the project's git history). Project additions found there are listed in the plan and go to Project rules after the human's "ok".

### 4.2 BLOCK

- File absent: take the template's file whole (`AGENTS.md` brings the `## Project rules` heading).
- File present without a block: insert the block after its first `# ` heading, or at the top; keep the rest.
- Block present: replace the text between the markers.
- 2.x `AGENTS.md`: the part above `## Project rules` was AgentFlow's and becomes the block; `## Project rules` and below stay.
- `CLAUDE.md` that already imports `@AGENTS.md` outside the block: leave it and tell the human.
- `.gitignore`: remove the 2.x lines `tasks/.runtime/`, `tasks/.runtime/*`, `!tasks/.runtime/*.verify.json`, `dashboard/out/`, `dashboard/versions/`; the block replaces them.

### 4.3 MOVE

Migrate needs no running attempt (`tools\run-task.ps1 -Status` lists none `running`) and no worktree with uncommitted work; otherwise stop and tell the human.

| Was | Becomes |
|---|---|
| `docs/ai-handoff-protocol.md`, `roles/`, `tools/run-task.ps1`, `tools/gate.py`, `tools/ledger.py`, `tools/models.json`, the AgentFlow files of `dashboard/`, `tasks/_template.md`, `templates/` | removed after 4.1 (`.agentflow/` replaces them) |
| `docs/product/05_*` - `08_*` | removed (now `.agentflow/guide/product-*.md`) |
| `docs/project-plan.md` | `docs/plan.md` |
| `state/tasks.md` | `docs/tasks/tasks.md` |
| `state/*.md` | `docs/state/` |
| `tasks/T-*.md` | `docs/tasks/` |
| `tasks/.runtime/` (local) | `docs/tasks/.runtime/`; then `git add` its `*.verify.json` |
| `runbook/`, `screenshots/` | `docs/runbook/`, `docs/runbook/screenshots/` |
| product documents elsewhere (`00_PRD/` ...) | `docs/product/` as `00_INDEX.md` ... `04_ARCHITECTURE.md`, `09_REVIEW.md` (`09_GAPS_REVIEW.md` too); their own `05`-`08` explanation files are removed |
| an owner queue elsewhere | `docs/state/owner-tasks.md` |

Format fixes the tools read, never a change of meaning: `- **Статус:**` on FR, NFR, ADR; `- **Приоритет:**` on FR, NFR; `- **Source:** FR-###` on AC; `APPROVED (OWN-###)`; Architecture sections `T01`... -> `AR01`...; `status` in the front matter of Vision and Brief. A status or priority the text does not tell: `DRAFT` and an owner task.

Then replace old paths in open Task Files and in Project rules; done Task Files stay (history). Apply the migration notes of `.agentflow/CHANGELOG.md` between the project's version and the template's (from 2.x: `Risk:` in open developer Task Files, and the rest listed there).

### 4.4 GENERATE

Missing files only; never overwrite one that exists.

| File | Source |
|---|---|
| `docs/state/handoff.md` | the protocol's Handoff sections, filled from the project card |
| `docs/state/current-step.md` | the real next action |
| `docs/state/session-log.md` | git history grouped by topic with real dates; today: AgentFlow installed (mode) |
| `docs/state/decisions.md` | decisions found in documents and commits, with their dates; today: AgentFlow installed, and why |
| `docs/state/known-issues.md` | the owner's prohibitions, known dead ends, TODOs that describe a problem |
| `docs/state/owner-tasks.md` | `.agentflow/templates/owner-tasks.md`, plus one task per open question |
| `docs/plan.md` | Stages with `Status` (`closed`, `current`, `planned`) and Exit criteria |
| `docs/tasks/tasks.md` | `python .agentflow/tools/ledger.py show` creates it |
| `docs/product/` | only when the human wants a Product definition and the project has none: `.agentflow/templates/product/` `00`-`04`, `09`; fill `00_INDEX.md`, the rest stays `DRAFT` for the gate work |
| `docs/runbook/clean-instruction.md` | verified steps only; none: a skeleton and one owner task |

Each field: a fact; or an inference, listed in the report to confirm; or unknown: `TODO(OWN-###)` in the file and the question as that owner task. Real dates only. Handoff and current-step within 1-2 screens.

### 4.5 Project rules

From the reconnaissance and the human's lines, in `AGENTS.md` outside the block or in `docs/engineering-rules.md`, wherever the project keeps its rules: the `<worktrees>` folder; `## Preflight` (deny production hosts, require the local flags of test commands); `## Deploy` when the project is deployed (platform project folder, contract, request file, deploy script). A test config that reaches staging or production by default: tell the human, do not fix it here.

## 5. Check

Read only.

1. Placeholders in what you wrote: `[вписать]`, `YYYY-MM-DD`, `T-NNN-slug`, `<...>` in `docs/state/`, `docs/plan.md`, filled product files. Each hit: a fact or an owner task.
2. No AgentFlow file left at a 2.x path (table in 4.3).
3. No old path in text the agents read: `grep -rn "docs/ai-handoff-protocol\|state/tasks.md\|tools/run-task\|python tools/" AGENTS.md CLAUDE.md docs/engineering-rules.md` and open Task Files.
4. Tools: `python .agentflow/tools/ledger.py show`; with a Product definition `python .agentflow/tools/gate.py spec`; `.agentflow\tools\run-task.ps1 -Status`.
5. `git status --short`, `git diff -M --stat` (moves show as renames), and the full diff of `AGENTS.md`, `CLAUDE.md`, `.gitignore`, and of every moved file that changed beyond the move. Every changed line outside AgentFlow's parts is a move or a listed format fix.

## 6. Report and commit

One message in Russian:

1. Mode and why.
2. Replaced or inserted (CANON, BLOCK).
3. Moved, from -> to, and the format fixes.
4. Created (GENERATE).
5. Not touched, and conflicts.
6. Inferences to confirm, 2-5.
7. Owner tasks opened.

Up to 4 questions that decide content: ask with the tool's question dialog and write the answers in at once. After the human's "ok": one commit `chore: AgentFlow <version> (<mode>)`; `docs/state/decisions.md` has the dated entry.

## Never

- Rewrite, shorten, or "improve" project text; delete project files other than the 2.x AgentFlow files in 4.3.
- Copy the template's own `docs/`, `README.md`, `dev/`, `LICENSE`.
- Edit the template.
- Invent screenshots, runbook steps, dates, or decisions.
- Commit without the human's "ok".
