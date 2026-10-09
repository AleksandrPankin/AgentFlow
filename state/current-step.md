# Current Step

## Now

2.4.0 (product definition, owner tasks, `Spec:` checks, deploy through the platform project) is in the working tree of `release/2.4.0`, not committed.

## Next action

1. The human reviews the diff; on "ok", one commit on `release/2.4.0`.
2. The human copies the layer into a live project (CHANGELOG 2.4.0, migration note) and brings feedback; findings go to `state/known-issues.md`.
3. Merge order to decide with the human: `release/2.3.0`, then `release/2.4.0`, into `main`.
4. Release 3.0.0 (`.agentflow/`, Stage 6) after the colleague's answer about `launch.ps1` and `tests/`.
