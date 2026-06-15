# US-DPR-04 — `:all` completion fails fast when any related row fails

**User-type:** developer **Status:** spec

```gherkin
Given a parent with a has_many dynamic region of four rows and completion_strategy :all
When one related row reaches a failure terminal state while others are still pending
And check_completion/2 is invoked for the parent
Then it returns {:error, :partial_failure} without waiting for the remaining rows
```

## Acceptance criteria

- With `:all` strategy, a single loaded row at `:failed` short-circuits
  `check_completion/2` to `{:error, :partial_failure}` even while siblings are
  still pending.
- The failure check is evaluated before the full-success check.

## Notes

- **Reference / related code:** `AshStateMachine.ParallelCoordinator`
  `check_group_completion/3` (`:all` strategy), `region_status/1`
- **Size:** ≤ ~200 lines, 1 module — else split into subtasks.

## Tasks

- [Task 05 — Coordinator loads rows](../../../../../../docs/tasks/workflow-dag-engine/05-coordinator-load-rows.md) — the work that makes this story true.
- [Task 06 — Coordinator counts rows](../../../../../../docs/tasks/workflow-dag-engine/06-coordinator-count-rows.md) — the work that makes this story true.

## See also

- [US-DPR-03](US-DPR-03-all-completion-succeeds.md) — the success path of the
  same `:all` strategy.
- [US-DPR-07](US-DPR-07-require-n-unsatisfiable.md) — the analogous
  unsatisfiable-failure path for `{:require_n, n}`.
