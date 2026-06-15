# US-DPR-05 — `:any` completion succeeds on the first related row that succeeds

**User-type:** developer **Status:** spec

```gherkin
Given a parent with a has_many dynamic region of three rows and completion_strategy :any
When one related row reaches a success terminal state while the other two are still pending
And check_completion/2 is invoked for the parent
Then it returns {:ok, :complete, context} with the configured exit_state
```

## Acceptance criteria

- With `:any` strategy, `check_completion/2` returns `{:ok, :complete, context}`
  as soon as one loaded row is `:succeeded`, without requiring the remaining
  rows to be terminal.
- The result carries the configured `exit_state`.

## Notes

- **Reference / related code:** `AshStateMachine.ParallelCoordinator`
  `check_group_completion/3` (`:any` strategy), `region_status/1`
- **Size:** ≤ ~200 lines, 1 module — else split into subtasks.

## Tasks

- [Task 05 — Coordinator loads rows](../../../../../../docs/tasks/workflow-dag-engine/05-coordinator-load-rows.md) — the work that makes this story true.
- [Task 06 — Coordinator counts rows](../../../../../../docs/tasks/workflow-dag-engine/06-coordinator-count-rows.md) — the work that makes this story true.

## See also

- [US-DPR-03](US-DPR-03-all-completion-succeeds.md) — the `:all` completion
  strategy alternative.
- [US-DPR-06](US-DPR-06-require-n-runtime-count.md) — the `{:require_n, n}`
  completion strategy alternative.
