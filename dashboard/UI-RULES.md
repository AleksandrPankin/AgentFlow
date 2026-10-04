# Rules for building human-facing interfaces over AgentFlow data

Scope: any dashboard or viewer that shows AgentFlow data (ledger, Task Files, git history) to a human. The reference implementation is the template's `dashboard/` (sources: `build.py`, `template.html`, `graph_template.html`, `common.js/css`, `filterbar.js/css`, `snapshot.py`; output `dashboard/out/`, versions `dashboard/versions/`). Section A: process and methods the human asked for. Section B: practices that proved themselves. Section C: how to apply this to a new interface.

---

## A. Requirements and methods

### A1. Process
1. **Discuss and assess feasibility first, do nothing yet.** For big ideas (graph, Gantt, timelines) first answer "can it be done", then build.
2. **Clickable mock-up before the real port.** Show layout options as a clickable mock-up, let the human choose, then implement.
3. **Version before changing.** Before every notable edit take a snapshot (`snapshot.py save`); roll back with one command (`restore vN`).
4. **Collect feedback as a list and assess it before editing.** When the human gives many remarks, consolidate them, assess, reply, then act.
5. **Do not break the process or the data.** The dashboard only reads the ledger, Task Files and git. Statuses, acceptance rules and templates are not changed for looks.
6. **Dashboard sources are template-owned and committed.** Only `out/` and `versions/` are git-ignored.
7. **Decide within your authority.** If the human said "do it your way, I will look", do not ask. Ask only when the decision is the human's.
8. **Interface language follows the project memory's language** (English by default for AgentFlow). The vocabulary of statuses, roles and outcomes comes from `docs/ai-handoff-protocol.md`, never invented.

### A2. Data and honesty
9. **Never invent a value.** No data means empty or "not set", not a guess. Mark estimated fields with the word "estimate" ("Set by: ... (estimate)").
10. **Do not mix different things under one word.** Ledger status, worker outcome (the worker's report) and the independent check verdict are three different lines with three different names. "Completed by worker" is not "done".
11. **Show the source.** Next to a normalized value show the raw report line; for commits, a caption saying where it came from and what it does not mean.
12. **Full text as is, no paraphrase.** No auto-summary, no LLM compression, no bold highlighting. Short form is a heading, full form is an expandable block with the original text.
13. **Do not show empty blocks** (no text, no block). Exception: "Status history" is always expanded.
14. **Do not guess ambiguous values.** A worker's commit is taken only from an explicit `Commit:` / `Change:` line and only if there is exactly one hash; otherwise empty.

### A3. Layout and screen
15. **Use the whole screen.** Side blocks do not scroll, they fit; only one central block scrolls (table, Gantt).
16. **Same column widths on all pages**, the same grid: header / filters / chosen / three columns.
17. **No horizontal scroll**, including 4K and narrow screens (extra columns are hidden by width).
18. **Page scale does not jump.** Moving between pages does not change element sizes or the header position at 100%.
19. **No extra scrollbars.** Long fields are expandable, with a bounded height inside.
20. **Identical headers:** `Tasks · <project>`, an "Overview / Gantt and timeline" switch, "Built ..." at top right, theme as an icon (sun / moon), not a word.
21. **Remove what is rarely needed** (for example the legend on the timeline tab) unless it is required for understanding.

### A4. Filters
22. **One set of filters on all pages, all of them working.** Remove a filter only if choosing it does nothing on that page.
23. **Maximum slice.** Filters on every axis: status, who set the task, stage, role, agent, outcome, independent check, size, links, creation and closing dates.
24. **Reset per filter and "Reset all".** The chosen values show as chips on a separate row; the "Showing N of M" counter comes first.
25. **A count next to every value** (how many tasks the choice gives). Zero values are dimmed but selectable.
26. **Search by number, title and notes, plus an option "in task text"**; matches inside the text are shown as a fragment in the card.
27. **Filters do not twitch.** The appearance and disappearance of ": N" does not move neighbours (space is reserved up front).
28. **Same height and look** of the filter panel on all pages.

### A5. Task card
29. **One card for all pages** (a shared component), one data source.
30. **Links between tasks are clickable** and work on all pages (jump, highlight).
31. **Long fields are expandable** (Goal, Result, Notes); everything else is shown in full.
32. **Separate agent and role** (the same session may act as deployer while Codex or Claude did the work).

### A6. Time, graph, links
33. **Real physical time.** Offer an option "without pauses between agent sessions" (a threshold activity model over git traces).
34. **Timeline units** (hours / days / weeks / months), as in MS Project, separate from zoom. Show how development sped up.
35. **Gantt order is by completeness:** cancelled on the left ... done on the right; grouping by stage by default, switchable.
36. **Links of different kinds** (depends, replacement-successor, check) use different styles, and **one legend serves the Gantt and the board** (one style table).
37. **Do not dim links without a reason**; background links are enabled by a separate setting and highlight on hover / click. Link settings are shared by the Gantt and the board; grouping and zoom are Gantt only.
38. **Layers:** background lines go under cards and do not cover them; highlighted ones go on top.
39. **Show "how large the change is"** per task (change size from git) and "depends on a rejected / cancelled task" (a toggle).
40. **A sticky right panel next to the Gantt:** the selected task's description stays visible without leaving the chart.

---

## B. Best practices

### B1. Architecture
1. **One data source shared by the pages.** One JSON payload is embedded in all pages; the pages differ only in presentation.
2. **A shared layer in separate files:** `common.css` (tokens, grid, header, card), `common.js` (namespace `C`: constants, `prep`, `makeDims`, `matchDims`, `taskCard`, `initHeader`), `filterbar.js/css`. A page template only includes them and draws its own part. Duplicated logic between pages is a bug.
3. **Build into one self-contained HTML** with no server: `build.py` substitutes markers (`__DATA__`, `/*COMMON_JS*/`, etc.). Python stdlib only.
4. **One style/vocabulary table for everything:** `EDGE_STYLE`, `ST`, the result-label map; swatches in the legend, on the Gantt and on the board are taken from it.
5. **Filter dimensions are described once** (`makeDims`); every screen builds filters and matches from them. Check: the numbers for each filter match on all pages.

### B2. Data
6. **The source of truth is project files and git**, not manual edits. Statuses over time come from replaying history (`git log --reverse`, `git show hash:file`).
7. **Normalization plus the original.** A map "raw -> label" plus the raw string kept alongside. Compare on raw values (lowercase ledger words), capitalise only for display.
8. **Strip service text:** HTML comments from templates are removed before display.
9. **Extraction rules are strict and explainable:** anchor on a label (`Commit:`), a single value, a regex check. "Undetermined" cases are listed and shown honestly.
10. **Test on real edge-case tasks**, not only typical ones: empty report, rejected, several hashes, replacement, a rework chain.

### B3. Layout and UX
11. **Colour tokens on `:root`, dark and light themes** (`prefers-color-scheme` plus an explicit `data-theme`); the toggle is saved in `localStorage`.
12. **A fixed `.app` grid per screen** (`100vh`, rows `auto auto 26px 1fr`), exactly one container scrolls; a narrow screen falls back to normal flow.
13. **Reserve space for what appears.** Dynamic counters, badges and "Chosen" rows have a reserved size; mark the selected item with colour and a border, not bold (bold changes width).
14. **Align the heights of related blocks** on all pages (search field, filter panel); verify with a screenshot.
15. **Dropdowns:** close on outside click via `composedPath().includes(bar)`; a re-render must not detach the target element.
16. **Do not overwrite classes** with `className=`; use `classList.add`.
17. **SVG layers:** background under cards; highlights are cloned into the top layers (`hlclone`), not recoloured in place.
18. **Compact left panel:** shrink plus a thin scrollbar instead of overflow; narrow screens hide columns instead of collapsing everything.
19. **Labels use the project's domain language** ("Outcome", "Independent check"), not implementation terms, and match the protocol vocabulary.

### B4. Verification and change safety
20. **Snapshot before and after** (`snapshot.py save|list|restore`), including sources and built pages.
21. **Check in a real browser** (playwright on a temporary `http.server`; `file://` is blocked): filters, page transitions, expanding blocks, links, a clean console, no horizontal scroll at 1920x1080 and other sizes.
22. **Regression by counters:** every filter gives the same numbers on all pages.
23. **Remove screenshots and the test server** after checking.
24. **Complex edits as a patch script** (`rep(old, new)` with `assert`), not long shell heredocs: it fails loudly if the anchor is gone.
25. **Hidden characters:** after escaping a regex in a patch, check the file for control characters (a \x08 once appeared instead of `\b`).
26. **Final reply to the human is short:** what changed, where each disputed field comes from, which cases are intentionally empty, how to roll back.

---

## C. Checklist for a new interface (before starting and before handing over)

Before starting
- [ ] One data source? One description of dimensions and vocabularies? Shared layer extracted?
- [ ] Layout options shown to the human, if the layout is new?
- [ ] Version saved before changes?
- [ ] Which entities are easy to confuse? Each gets its own line and its own name.
- [ ] Interface language matches the project memory; status, role and outcome words come from `docs/ai-handoff-protocol.md`.

Before handing over
- [ ] No invented values; estimates marked; source visible.
- [ ] Empty not shown, ambiguous not guessed.
- [ ] One filter set, all working, reset per filter and global, counts present.
- [ ] No jumps on state change (counters, chips, page transitions).
- [ ] No horizontal scroll at 4K, 1920 and a narrow screen; no extra scrollbars.
- [ ] Same header, grid, theme and "Built" stamp on all pages.
- [ ] Checked in a browser, console clean, numbers match across pages.
- [ ] Snapshot taken after; temporary files removed; short report to the human.
