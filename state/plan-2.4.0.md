# Implementation Plan: 2.4.0 Product definition layer

Status: implemented on `release/2.4.0` (2026-10-09), not merged; sandbox matrix for `gate.py` passes; end-to-end run with real tools and the live-project feedback pending. Template-owned working document (not copied into projects). When the release ships, this file is deleted and the result goes to `CHANGELOG.md` and `state/decisions.md`.

Inputs:
- product pack draft `D:\OneDrive\AI\01_Templates\000_AI-First\00_INDEX.md` ... `08_TRACEABILITY_EXAMPLE.md` (v0.1.0, Russian);
- the human's research: `ChatGPT-Product Vision Brief Overview-*`, `ChatGPT-Что такое PRD-*`, `ChatGPT-Что такое Technical Design-*` (same folder);
- integration review `ChatGPT-Пересборка структуры продукта-20261009-1533.md` (written against `main` 2.1.0, not 2.3.0);
- field evidence from a live project: `09_GAPS_REVIEW.md` and `state/owner-tasks.md` (owner task queue `OWN-###` with an answer journal; the owner started slice S1 before G0-G3 were approved);
- FPF (`FPF-Spec/`, local reference only): A.7 Strict Distinction, A.2.6 Scope, A.2.9 SpeechAct, A.6.B L/A/D/E, A.10 Evidence Graph, A.16 Language-State, B.3.4 Evidence Decay, C.16 MM-CHR, E.17 Multi-View Publication, F.17 UTS;
- the human's answers of 2026-10-09 (section 2).

## 1. Goals

1. Before agent work, a project can hold a short product definition (Vision, Brief, PRD, Architecture) that tasks reference by ID, so agents build the agreed product and not their own ideas.
2. One fact, one place: product docs, memory, ledger, and Task Files link to each other and never copy.
3. The human keeps the final word without being a bottleneck: agents draft, check, build, and verify; the human's verdict arrives asynchronously through a task queue.
4. Workers read only the spec sections their task names.
5. Rules are enforced by `gate.py` where cheap; prose only where code cannot check.

Non-goals: new worker roles, new task states, a traceability script, YAML in Task Files, RAG or a context agent, copies of process rules per project, reintegrating live projects (later, separate).

## 2. Decisions taken by the human (2026-10-09)

| # | Question | Answer |
|---|---|---|
| H1 | Language of product docs | Russian; IDs, statuses, front-matter keys, and Task File fields in Latin |
| H2 | Who approves | Agents run the checks and keep working; the human's final word is non-blocking and comes later, in live use, through tasks queued for the human. Rework after a "not OK" is accepted |
| H3 | Vision and Brief | Two files: G0 and G1 are separate |
| H4 | `gate.py` check | In 2.4.0 |
| H5 | Template folder | `templates/product/` |
| H6 | 05, 06, 07 | Keep them as short human explanations; agents do not read them unless asked |
| H7 | `09_GAPS_REVIEW.md` | Anonymize, turn into a template, integrate |
| H8 | Deploy | On the Orchestrator's request, performed by an agent session of the platform project (for the human's projects: `D:\OneDrive\AI\04_Infra_PVE`). Staging without the human; production keeps the human's yes in the platform session (the human considered a risk-policy deploy without a yes and kept the yes). Details 3.11 |
| H9 | Blocking list | Confirmed as in 3.3 |

## 3. Design

### 3.1 Layers and ownership

| Layer | Answers | Files | Writer |
|---|---|---|---|
| Memory | where we are, what next | `state/`, `docs/project-plan.md`, `runbook/` | Orchestrator / Single Mode |
| Roles and tasks | who does which piece | `roles/`, `tasks/`, `tools/` | Orchestrator; worker only its `## Result` |
| Product definition | why, what, how accepted, how built | `docs/product/00-04`, `09`, `decisions/ADR-###.md` | Orchestrator / Single Mode drafts; the human gives the final word |
| Owner queue | what only the human can do or decide | `state/owner-tasks.md` | Orchestrator; the human ticks and answers |

Links: slice = Stage of `docs/project-plan.md`; task -> spec IDs (`Spec:`); task acceptance (Orchestrator, `gate.py verify`) is not slice acceptance (human, OWN task).

### 3.2 Product layer is optional
Active when `docs/product/00_INDEX.md` exists. Without it AgentFlow behaves exactly as 2.3.0 (brownfield projects, small tools). A section that does not apply is filled `n/a - <reason>`, not deleted.

### 3.3 Human final word is non-blocking (H2)
- Agents run the gates (readiness checks), set `PROPOSED`, open an OWN review task, and continue.
- The human answers when free. "OK" -> `APPROVED`. "Not OK" -> findings -> changed items (Change Impact) -> new tasks.
- **Blocking list** (H9; agents stop the affected work only, the rest continues): an action only the human can do (key, token, account, login, payment); a production deploy (the human's yes in the platform session, 3.11); a server change (new service, port, proxy or firewall rule, DB role or grant, secret, volume, domain); money beyond the `B06` budget; new external access or processing of personal data; an irreversible action without rollback; a feature outside `B04` (it waits as an OWN decision, it is not built meanwhile).
- FPF: the blocking list is D (duties of roles), the gate checks are A (admissibility), the human's answer is a SpeechAct (A.2.9) whose carrier is the journal row.

### 3.4 Spec status family (A.16, A.2.6, B.3.4)
- `DRAFT` -> `PROPOSED`: the agent check passed (`gate.py spec` clean, Orchestrator checklist, `09` review written) and an OWN review task is open. Implementable.
- `PROPOSED` -> `APPROVED`: the human's answer is recorded in the journal of `state/owner-tasks.md` (source = human, date). AI never writes `APPROVED` without that row.
- `PROPOSED` / `APPROVED` -> `STALE`: an upstream item changed (Change Impact). Not implementable. Exit: re-check -> `PROPOSED` (refresh), human keeps it -> `APPROVED` (waive), replaced -> `SUPERSEDED` (deprecate).
- Any -> `SUPERSEDED`: replaced by a new item or version; kept for history.
- Scope of status: whole document for Vision and Brief (front matter); per item for PRD and Architecture (`FR`, `NFR`, `ADR` blocks carry `- **Статус:**`; an `AC` follows its FR through `- **Source:** FR-###`).
- Implementable = `PROPOSED` or `APPROVED`. `OPEN` belongs to questions and hypotheses only.
- New row in the protocol's States table: family "Spec status", owner Orchestrator / Single Mode, `APPROVED` only from a journal row.

### 3.5 Gates
| Gate | Agents check (blocking for task creation) | Human final word (non-blocking) |
|---|---|---|
| G0-G3 | readiness checklists of `01`-`04` for the Stage's slice, `gate.py spec`, `09` review | one OWN task per slice: "read `09`, then answer OK / changes" (field lesson: six gates in one review session) |
| G4 | `gate.py verify` per task, Tester where the lifecycle requires one, `gate.py stage N` | none: verification is the agents' job |
| G5 | release data per `B07` | OWN task "check slice in live use: OK / not OK + what": validation by `B07`, `V03` |

- A Stage closes on G4; G5 never holds a Stage open.
- One register: table in `docs/product/00_INDEX.md` (Gate, Stage, doc versions, agent check date, human word -> `OWN-###` and result). Removed from `05` and from front matter (`approved_by/at`).
- Spike before G3 allowed: `Spec: spike - Q-T-###`; result goes to an ADR; spike code is not merged into the product.

### 3.6 Owner tasks (core, not only with the product layer)
Format proven in the live project:
- `state/owner-tasks.md`, Russian, human-facing; `OWN-###`, never reused; one task = one action (one secret = one task).
- Each: what to do (exact steps) -> what to return (form) -> what it unblocks (`ничего - финальное слово` allowed) -> when.
- Status marks `[ ]` open, `[~]` in progress, `[x]` done + date + short result, `[-]` withdrawn + reason.
- Journal of answers at the bottom (date, question or OWN, answer, where it landed): the only carrier of the human's decisions on product questions. A decision that changes process also gets a `state/decisions.md` entry that cites the journal date.
- The human answers in the file or in chat; the Orchestrator transfers chat answers. Secret values never go into the file, chat, or Markdown.
- Orchestrator at session start reads the open OWN tasks (not the journal); before asking the human anything it searches the journal.
- A worker that needs the human writes `Outcome: blocked` with `Needs owner: <action>`; the Orchestrator opens the OWN task and sets the ledger `blocked` with `Notes: OWN-###`.
- Rejected: owner tasks as Task Files with `Role: human` in the ledger. Launch, preflight, verify, `-Wait`, and the Stage check are worker machinery; each would need a special case, and a human act is not Work of a worker (A.7). Separate namespace `OWN-###` instead.

### 3.7 Task <-> spec
- Task File header: `Spec: FR-012, AC-012, NFR-003, ADR-006` | `Spec: none - <reason>` | `Spec: spike - Q-T-###`. Required when the product layer is active.
- `## Read first`: `docs/product/03_PRD.md - FR-012, AC-012`; the worker reads only the named sections plus the cross-cutting constraints listed there.
- `## Acceptance criteria` cite the product AC they refine: `AC-012: <checkable statement for this task>` (refinement only, no new commitment: A.7 DS-1).
- Workers never edit `docs/product/`; they write `Proposed spec changes:` in the Result. Tester gives a verdict per criterion with its AC ID.
- Reverse lookup without a script: `git grep -n "FR-012" docs/product tasks state`.

### 3.8 Files and ownership
```text
templates/product/                 # template-owned (3.0.0: .agentflow/templates/product/)
  00_INDEX.md  01_VISION.md  02_BRIEF.md  03_PRD.md  04_ARCHITECTURE.md   # -> docs/product/, copied once, then project-owned
  05_GATES.md  06_AUTHORITY.md  07_DOCUMENT_RULES.md  08_TRACEABILITY_EXAMPLE.md  # -> docs/product/, template-owned, replaced on update
  09_REVIEW.md                                                            # -> docs/product/, copied once, project-owned
templates/owner-tasks.md           # -> state/owner-tasks.md, copied once, project-owned
```
- `05`-`08` are a human view of the protocol section (E.17: a view adds no semantics). Header in each: "Пояснение для человека. Норма - `docs/ai-handoff-protocol.md`, раздел Product definition; при расхождении прав протокол. Агенты читают только по прямому запросу." Changing that protocol section means updating `05`-`08` in the same commit (same rule as the dashboard data contract).
- ADR files: `docs/product/decisions/ADR-###.md`. `state/decisions.md` keeps process and planning decisions; neither copies the other.

### 3.9 `09_REVIEW.md` (from `09_GAPS_REVIEW.md`, H7)
The agent's gate-check report for the human (A.10: report links to sources, never restates them), rewritten each review round, version in front matter. Agents do not read it. Template sections, anonymized (no product names, services, hosts, people):
0. What changed since the last round (was -> now -> why, with the journal date).
1. Enough information: area -> where it landed (IDs).
2. Not enough: waits for the owner (-> `OWN-###`, what it blocks); waits for materials; not confirmed technically (-> `Q-*`, `HYP-*`).
3. Contradictions and ambiguities: what -> how resolved -> who confirms.
4. Over-complication cut (Simplicity First): proposed -> replaced by; items close to over-complication -> risk -> recommendation.
5. Karpathy summary: Think Before Coding, Simplicity First, Surgical Changes, Goal-Driven Execution -> how applied.
6. Open owner tasks: a link to `state/owner-tasks.md` (no copied checklist).

### 3.10 SSOT and vocabulary fixes in the pack (FPF findings)
| # | Defect | Fix |
|---|---|---|
| S1 | Approval stored in 4 places (00 register, 05 record, front matter, 06 `DEC`) | Register in `00`; human act in the journal; `05` record and `approved_by/at` removed |
| S2 | FR status in the FR block and in P09 | P09 removed (`git grep` gives traceability) |
| S3 | `04` T10 has a `T-NNN` column (copies the ledger) | T10 = slice content (FR/AC -> Stage), no task column |
| S4 | "История изменений" tables duplicate git | Removed; `version` in front matter |
| S5 | Questions in B08 and in "Открытые вопросы"; `DEC-###` and `Q-*` | B08 = risks and assumptions only; one namespace `Q-*` in the DEC format (options, recommendation, decision, who, when) |
| S6 | Architecture sections `T01..T10` collide with task IDs `T-NNN` | Renamed `AR01..AR10` |
| S7 | Product AC vs task "Acceptance criteria" | Task criteria cite `AC-###` (3.7) |
| S8 | "Gate" means G0-G5 and `gate.py` | Protocol Terms: "Product gate (G0-G5)" vs "`gate.py` check" |
| S9 | Slice has no ID or home | Slice = Stage N |
| S10 | `06` says the Orchestrator writes code and runs tests | "AI roles of AgentFlow within the roles table" |
| S11 | `06` lets agents edit tech docs (an approved baseline) | Workers propose spec changes in the Result (3.7) |
| S12 | Change Impact sets `STALE` on tasks and tests | Open tasks -> ledger `blocked`, `Notes: spec changed <ID>`; done tasks untouched, new task if rework |
| S13 | Diagram in `00` (PRD -> Architecture -> Tasks) contradicts `08` (two branches from FR) | FR -> AC -> checks; FR -> ADR -> tasks |
| S14 | ID table in `07` incomplete | Add `SCN`, `UC`, `UI`, `Q`, `HYP`, `R`, `AR`, `OWN`, `ADR`, `T-NNN`, `TEST` |
| S15 | `B07` metric lacks scale, polarity, who measures (C.16) | Columns "Ед./шкала (полярность)", "Кто меряет" |
| S16 | `HYP` has no exit states | `OPEN -> CONFIRMED / REFUTED` with evidence link |
| S17 | Leftovers: Miro, "пример про AgentFlow", "интеграция не выполнена" | Removed; `08` example neutral, uses `Spec:` and `OWN` |
| S18 | Path `docs/product/` in `07` vs a project folder `00_PRD/` (live project) | One path `docs/product/`; live projects move on reintegration |

### 3.11 Deploy through the platform project (H8)
Field practice (04 contracts for Calbot, NelliRadar, web-3d): the platform project owns servers and the deploy script; the product project owns code, Task File, and `docs/infra-requests.md`; the platform session writes only the request `**Статус:**` line and the deploy Task File `## Result`. Generalized:
- **Who:** the Deployer is an agent session of the platform project named in Project rules `## Deploy` (folder, contract file, request file, deploy script). It replaces "the session the human designated" per deploy. The Orchestrator never deploys and never launches the Deployer's tool: it writes the deploy Task File, records the attempt with `run-task.ps1 T-NNN -Manual`, adds the request entry, and messages the platform session where the host supports it (Claude Code `SendMessage`); `-Wait` wakes it when the Result appears.
- **Staging:** deployed on the request, no human, if it goes only through the contract script and changes no server (a server change is on the blocking list).
- **Production:** unchanged rule (decision 2026-10-03): the human's yes in the platform session, `Approval: source=human target=prod sha=<SHA> at=<time>`. The Orchestrator opens an OWN task `yes for prod <SHA>`; only that deploy waits, other work continues.
- Considered, not taken (2026-10-09): a production deploy without the human when a recomputed git-diff risk check is clean (`source=policy`). The human kept the yes.
- FPF: A.2.7 separation of duties (requester ⊥ deployer ⊥ approver).
- Follow-up outside this template: the platform project's protocol names which product projects it deploys for; it already reads their request files.

## 4. Changes per file

| File | Change | Size |
|---|---|---|
| `docs/ai-handoff-protocol.md` | Terms: Product definition, Product gate, Spec status, Owner task. States: Spec status row. New section "Product definition" (3.2-3.5, 3.7, Change Impact, reading rule incl. "agents do not read `05`-`09` unless asked"). New section or rule "Owner tasks" (3.6). Starting a new AI session: read `00_INDEX.md` if present and the open OWN tasks. Worker step 2: `Read first` by ID. What goes where, Installing / updating: `templates/`, `docs/product/`, `state/owner-tasks.md`, ownership per 3.8 | ~50 lines |
| `roles/orchestrator.md` | Do: gate check before splitting a Stage; tasks from implementable FR/AC; fill `Spec:` and `Read first` with IDs; open OWN tasks instead of waiting; Change Impact on spec change. Ask the human: point to the blocking list | ~6 lines |
| `roles/developer.md`, `tester.md`, `deployer.md` | Result: `Proposed spec changes:`, `Needs owner:`; Tester: verdict per AC ID | ~3 lines |
| `tasks/_template.md` | `Spec:` line; `Read first` format comment; Acceptance criteria comment "cite AC-###" | ~3 lines |
| Deploy (3.11) | Protocol: Launching workers rule 3 (Deployer = platform project session from Project rules `## Deploy`; staging on request; production with the human's yes as today), Install (name `## Deploy` in Project rules). `roles/deployer.md`: works from the platform project, writes only `## Result` and the request status. `roles/orchestrator.md`: request the deploy, open the OWN task for a production yes. No code change | ~15 lines docs |
| `tools/gate.py` | Spec item parser (`### <ID> — ` + `- **Статус:**`, AC `- **Source:**`). `spec` subcommand: duplicate IDs, invalid status, Must FR without AC, AC without FR, count `STALE`. Preflight when `docs/product/00_INDEX.md` exists: `Spec:` present; every ID exists once and is `PROPOSED` / `APPROVED`; no `Allowed files` under `docs/product/` | ~60-80 lines |
| `templates/product/*`, `templates/owner-tasks.md` | New: pack per 3.8-3.10 | 11 files |
| `AGENTS.md` | One line: a worker reads only the sections named in Starting a role session; version 2.4.0 | 2 lines |
| `GUIDE.md` | For the human: starting a product from G0, the owner queue, reading `09` | ~15 lines |
| `dashboard/` | Check `dashboard/README.md`: a `Spec` column only if the contract fits; owner tasks view: later | 0-10 lines |
| `CHANGELOG.md`, `state/decisions.md`, `docs/project-plan.md` | 2.4.0 entry and migration note; decisions H1-H7 and 3.3-3.6; new Stage | - |

## 5. Order

1. Stage "Product definition (2.4.0)" in `docs/project-plan.md`; decisions into `state/decisions.md`.
2. Branch `release/2.4.0` from `release/2.3.0` (additive: only `docs/product/` and the `Spec:` line change behaviour).
3. Templates (3.8-3.10), anonymized; Russian text, Latin IDs and statuses.
4. Protocol, roles, Task File template, `AGENTS.md`, `GUIDE.md`.
5. `gate.py` with its sandbox matrix (section 6).
6. End-to-end sandbox run.
7. Markdown link check, CHANGELOG, version line.

## 6. Verification

Sandbox matrix for `gate.py`:
| Case | Expected |
|---|---|
| no `docs/product/` | preflight as 2.3.0, `Spec:` ignored |
| product layer, no `Spec:` line | refused |
| `Spec: none - chore` / `Spec: spike - Q-T-001` | passes |
| ID missing / duplicated | refused / `spec` error |
| ID `DRAFT` or `STALE` or `SUPERSEDED` | refused |
| ID `PROPOSED` or `APPROVED`; AC whose FR is `PROPOSED` | passes |
| `Allowed files` under `docs/product/` | refused |
| Must FR without AC, AC without FR | `spec` error |

End to end: empty project -> install -> G0-G3 on a toy product (agent checks, `09` written, OWN review task opened, status `PROPOSED`) -> one developer task with `Spec:` -> verify -> Stage closes while the OWN task stays open -> the human's answer recorded -> `APPROVED`. A "not OK" answer: item changes, dependent open task goes `blocked`, a new task follows.

## 7. Risks

| Risk | Mitigation |
|---|---|
| Building on `PROPOSED` causes rework after a "not OK" | Accepted by the human (H2); the blocking list keeps the costly cases gated; slices stay small |
| AI writes `APPROVED` itself | Rule: only with a journal row; the journal is the human's channel; `gate.py spec` reports `APPROVED` counts per round for the `09` review |
| `05`-`08` drift from the protocol | Same-commit rule; header says the protocol wins |
| Owner queue grows unread | It never blocks except the blocking list; `09` and the session summary show open OWN counts |
| Item parser too strict for hand-edited docs | One fixed block format in the templates; `gate.py spec` names the line it cannot read |
| Production yes waits long in the owner queue | Only that deploy waits; staging keeps the slice testable; the OWN task says what is waiting |

## 8. Open

Nothing blocks the start. Decided: deploy (H8, 3.11), blocking list (H9).

1. Later, separate: reintegration of live projects (path `00_PRD/` -> `docs/product/`, `T01..` -> `AR01..`, `Spec:` lines, owner tasks already in place); dashboard view of owner tasks; optional independent spec review by a fresh session.
