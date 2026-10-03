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

Status: current.

Exit criteria: P0-P4 of the FPF audit committed; sandbox checks pass; the branch is merged by the human.

### Stage 3. Pilot 2.0.0

Status: planned.

Exit criteria: one real project updated with the "Update" procedure and a full task cycle run with the real tools; findings in `state/known-issues.md`.
