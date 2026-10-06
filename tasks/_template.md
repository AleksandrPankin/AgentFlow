# T-NNN: <short title>

<!-- Task File template. Only the Orchestrator copies and fills it: tasks/T-NNN-slug.md.
     Fields, states, gates: ../docs/ai-handoff-protocol.md. Task state lives in ../state/tasks.md. -->

Role: developer | tester | deployer
Tool: claude | codex | agy | antigravity      <!-- ../roles/tool-routing.md -->
Model: default                                <!-- small | standard | strong | <id from ../tools/models.json>; ../roles/tool-routing.md, Choosing the model -->
Effort: default                               <!-- low | medium | high | xhigh | max (per tool in ../tools/models.json) -->
Stage: <Stage number from docs/project-plan.md>
Depends on: T-xxx | none
Branch: t-NNN-slug                            <!-- developer -->
Worktree: <worktrees>\<repo>-t-NNN-slug       <!-- developer; <worktrees> from Project rules -->
Independent check: tester | none - <reason>   <!-- developer -->
Resume: none                                  <!-- after a failed attempt: <commit SHA> | start fresh -->
Verifies: T-xxx @ <SHA>                       <!-- tester: checked task and commit -->
Deploys: <SHA>                                <!-- deployer -->
Target: staging | prod                        <!-- deployer; tester after a deploy. Pre-merge tester: delete the line -->

## Goal

One or two sentences: what must be different.

## Read first

- files to read

## Allowed files

<!-- Tests that check the changed behaviour belong here too: an old test that contradicts the task, left in Do not touch, guarantees `blocked`. -->

- what may change (tester, deployer: nothing)

## Do not touch

- what must not change

## Setup

<!-- Prepared by the launcher before the start, not by the worker: `- link: node_modules`, `- copy: dist`, `- env: FOO=bar`. "nothing" is an answer too. -->

## Port

<!-- Developer or tester that starts a server or tests: PORT=<unique in this batch>. Tests read it from the environment. -->

## Rebuild together

<!-- Deployer, and developers of shared parts: what is rebuilt or deployed with this task, in dependency order. "nothing" is an answer too. -->

## Acceptance criteria

- [ ] checkable criterion 1
- [ ] checkable criterion 2

## Checks

<!-- Exact commands that prove the criteria; the worker and acceptance run them verbatim (PowerShell on Windows, sh elsewhere).
     Narrow: one spec file or filter; local only (AGENTFLOW_TARGET=local).
     A check without a command (screenshot, manual step): its own line without backticks, and give the task a Tester. -->

- `<command>` - which criterion it proves

## Result

<!-- Filled by the worker. Format: its role file. -->
