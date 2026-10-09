# Project Plan

Project: AgentFlow template.

## Goal

A small, tool-agnostic template that lets one Orchestrator and fresh worker sessions run a software project without losing state, with rules enforced by the tools.

Tasks are not listed here: they live in `state/tasks.md` with a `Stage` column. See `docs/ai-handoff-protocol.md`, "Planning levels".

## Roadmap

### Stage 1. Team layer and launcher

Status: closed.

Exit criteria: roles, Task Files, ledger, launcher with preflight work on a live project (1.2.0).

### Stage 2. 2.0.0: enforcement, states, template vs project

Status: closed.

Exit criteria: P0-P4 of the FPF audit committed; sandbox checks pass; the branch is merged by the human. (Merged; 2.1.0 dashboard on top.)

### Stage 3. Wake-up and pilot (2.2.0)

Status: current.

Exit criteria: 2.2.0 shipped (`CHANGELOG.md`) with its sandbox matrix passing; one real project updated with the "Update" procedure and a full task cycle run with the real tools and `-Wait`; findings in `state/known-issues.md`.

### Stage 4. Model per task (2.3.0)

Status: planned.

Exit criteria: `Model: strong` launches claude and codex with the id from `tools/models.json` or the env override; the launch line, `T-NNN.json`, and `-Status` show the model; an unknown tier or id is refused with the valid list; no `Model:` line leaves the command line unchanged; the agy path is tested on a machine that has it; every statement in "Choosing the model" has a vendor source or is labelled practice.

### Stage 5. Product definition and owner tasks (2.4.0)

Status: current.

Exit criteria: 2.4.0 committed on `release/2.4.0` (`5f74ce3`); the `gate.py` sandbox matrix (28 cases) passes; the human copies the layer into one live project and its feedback is in `state/known-issues.md`.

### Stage 6. One template folder (3.0.0)

Status: planned.

Exit criteria: `state/plan-3.0.0.md`, section 1.3.
