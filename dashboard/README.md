# Dashboard

A read-only view of the project for the human: task table and filters (`out/index.html`), Gantt, timeline and links (`out/graph.html`). It never changes the project; it reads `state/tasks.md` (Task Ledger), `tasks/T-*.md` (Task Files) and git history. Template-owned: see `docs/ai-handoff-protocol.md`, section "Dashboard".

## Use

```
python dashboard/build.py              # build out/index.html and out/graph.html, open either in a browser
python dashboard/snapshot.py save "what changed"   # keep the current dashboard sources as version vN
python dashboard/snapshot.py list
python dashboard/snapshot.py restore vN            # roll the sources back (the current state is saved first)
```

Needs Python 3 and git. Run it after the Orchestrator updates the ledger, or whenever you want a fresh view. `out/` and `versions/` are local and git-ignored; everything else here is part of the template.

## Files

| File | Role |
|---|---|
| `build.py` | reads ledger, Task Files, git; writes `out/*.html`; owns the data contract below |
| `template.html`, `graph_template.html` | the two pages; `__DATA__` and `__PROJECT__` are replaced by `build.py` |
| `common.css`, `common.js` | header, task card, shared helpers (inlined into both pages) |
| `filterbar.css`, `filterbar.js` | the filter panel (inlined into both pages) |
| `snapshot.py` | local versions of the dashboard sources, rollback |
| `UI-RULES.md` | interface rules this dashboard follows; read before changing it |

## Data contract (`build.py` -> pages)

Vocabulary comes from the protocol, never invented here.

| Field | Values |
|---|---|
| `status` | ledger `Status`: `ready`, `in progress`, `review`, `done`, `rejected`, `blocked`, `cancelled` (1.x words are mapped) |
| `role` | `developer`, `tester`, `deployer` |
| `tool` | agent that did the work: `Claude Code`, `Codex`, `Antigravity`, or the raw ledger value / `Not set` |
| `result` | worker report `Outcome`, as a label: `Completed by worker`, `Partially completed`, `Worker blocked`, `Worker failed`, `Deployment rolled back`, `No report`. Not acceptance |
| `check` | independent check: `Tester: pass` / `partial` / `fail`, `Tester assigned`, `Tester needed, no report`, `No independent check`, `Not set (older task)`, `—` for non-developer tasks |
| `origin` | who set the task (an estimate from text): `human`, `orchestrator`, `tester`, `deployer` |
| `sizeCls` | change size of the worker commit(s): `docs`, `S`, `M`, `L`, `XL`, `—` |

Three different questions, three different fields: ledger `status` (is it accepted), `result` (what the worker reported), `check` (what the independent review found). "Completed by worker" is not "done".

The page header shows the project name: the name of the folder that contains `dashboard/`.
