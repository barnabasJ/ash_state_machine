# US-TSI-03 — The API powers an external readiness filter without re-deriving states

**User-type:** developer **Status:** spec

```gherkin
Given a downstream library (ash_jobs) that needs to know when a state-machine resource is ready
When it calls AshStateMachine.Info.state_machine_terminal_states/1 (or the success variant) to build a needs-readiness `where` filter
Then it can construct the filter against the canonical terminal states without re-deriving them from raw transitions
```

## Acceptance criteria

- `AshJobs.Transformers.IntegrateOban` builds its readiness `where` clause from
  the public `AshStateMachine.Info` API.
- No `from`/`to` terminal-state derivation is reimplemented in `ash_jobs`.

## Notes

- **Reference / related code:**
  `packages/ash_jobs/lib/ash_jobs/transformers/integrate_oban.ex`,
  `packages/ash_state_machine/lib/info.ex`
- **Size:** ≤ ~200 lines, 1 module — else split into subtasks.

## Tasks

- [Task 08 — Terminal-state Info API](../../../../../../docs/tasks/workflow-dag-engine/08-terminal-state-info-api.md) — the work that makes this story true.

## See also

- [US-TSI-01](US-TSI-01-success-terminal-states.md) — provides the success
  terminal states this readiness filter consumes.
