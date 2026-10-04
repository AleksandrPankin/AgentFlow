# Dashboard

A read-only view of the project for the human (Russian interface): task table and filters (`out/index.html`), Gantt, timeline and links (`out/graph.html`). It never changes the project; it reads `state/tasks.md` (Task Ledger), `tasks/T-*.md` (Task Files) and git history. Template-owned: see `docs/ai-handoff-protocol.md`, section "Dashboard".

## Use

```
python dashboard/build.py                          # build out/index.html and out/graph.html, open either in a browser
python dashboard/serve.py [port]                   # local server http://127.0.0.1:8765 with the Refresh button
python dashboard/snapshot.py save "what changed"   # keep the current dashboard sources as version vN
python dashboard/snapshot.py list
python dashboard/snapshot.py restore vN            # roll the sources back (the current state is saved first)
```

Needs Python 3 and git. `out/` and `versions/` are local and git-ignored; everything else here is part of the template.

## Freshness

The dashboard is rebuilt on demand only, so without a request it can lag behind the ledger: by a whole Stage if nobody rebuilds it. This is deliberate. A page weighs about 2 MB (full task texts are embedded), and rewriting it after every ledger change is wasted work, more so in a cloud-synced folder.

- Button: with `serve.py` running, the refresh icon in the page header rebuilds both pages in full and reloads the current one. Opened as a plain file (double click) the page works but the button is disabled, because a static page cannot start Python.
- Command: `python dashboard/build.py`.
- Orchestrator: rebuilds when the human asks or a Stage closes (`roles/orchestrator.md`).
- Periodic (optional, not installed by default): a daily Windows Task Scheduler job running `python <project>\dashboard\build.py`.
- History: the timeline and Gantt come from git history of `state/tasks.md`; until the Orchestrator commits the ledger, the current status is shown but the history lags.

`serve.py` listens on 127.0.0.1 only; its single action besides serving `out/` is `POST /rebuild`, which runs `build.py` with no parameters from the request; foreign Host/Origin is refused.

## Files

| File | Role |
|---|---|
| `build.py` | reads ledger, Task Files, git; writes `out/*.html`; owns the data contract below |
| `serve.py` | local server for `out/` with the page's Refresh button |
| `template.html`, `graph_template.html` | the two pages; `__DATA__` and `__PROJECT__` are replaced by `build.py` |
| `common.css`, `common.js` | header, task card, shared helpers (inlined into both pages) |
| `filterbar.css`, `filterbar.js` | the filter panel (inlined into both pages) |
| `snapshot.py` | local versions of the dashboard sources, rollback |
| `UI-RULES.md` | interface rules this dashboard follows (Russian); read before changing it |

## Data contract (`build.py` -> pages)

The pages compare against these exact strings; change both sides together. The source of every value is the protocol's state vocabulary.

| Field | Source | Values shown |
|---|---|---|
| `status` | ledger `Status` | `ready` В очереди, `in progress` В работе, `review` На приёмке, `done` Принята, `rejected` Отклонена, `blocked` Заблокирована, `cancelled` Отменена (1.x words are mapped) |
| `role` | ledger `Role` | Разработчик, Тестер, Деплоер |
| `tool` | ledger `Tool` | agent that did the work: Claude Code, Codex, Antigravity, or the raw value / «Не указан» |
| `result` | Result `Outcome` (1.x: `Status`) | Завершено исполнителем, Частично завершено, Исполнитель заблокирован, Провал исполнителя, Откат выкладки, «Нет отчёта». This is the worker's report, not acceptance |
| `check` | `Independent check` and tester `Verdict` | Тестер: pass / частично / fail, Тестер назначен, Нужен тестер, нет отчёта, Без независимой проверки, Не задано (старая задача), `—` for non-developer tasks |
| `origin` | estimated from text | Владелец, Оркестратор, Тестер, Деплоер (labeled as an estimate) |
| `sizeCls` | commits `[T-NNN] ...` | док., S, M, L, XL, `—` |

Three different questions, three different fields: ledger `status` (is it accepted), `result` (what the worker reported), `check` (what the independent review found). «Завершено исполнителем» is not «Принята».

The page header shows the project name: the name of the folder that contains `dashboard/`.
