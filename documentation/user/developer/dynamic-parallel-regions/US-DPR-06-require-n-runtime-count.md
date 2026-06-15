# US-DPR-06 — `{:require_n, n}` is evaluated against the runtime row count

**User-type:** developer **Status:** spec

```gherkin
Given a parent with a has_many dynamic region of five rows and completion_strategy {:require_n, 2}
When two related rows reach a success terminal state while the rest are pending
And check_completion/2 is invoked for the parent
Then it returns {:ok, :complete, context} because succeeded_count >= 2
```

## Acceptance criteria

- With `{:require_n, 2}`, `check_completion/2` returns
  `{:ok, :complete, context}` once the `:succeeded` count across loaded rows
  reaches 2.
- The total reasoned over (`length(statuses)`) is the runtime `has_many` row
  count, not a fixed singleton list.

## Notes

- **Reference / related code:** `AshStateMachine.ParallelCoordinator`
  `check_group_completion/3` (`{:require_n, count}` strategy)
- **Size:** ≤ ~200 lines, 1 module — else split into subtasks.

## Tasks

- [Task 05 — Coordinator loads rows](../../../../../../docs/tasks/workflow-dag-engine/05-coordinator-load-rows.md) — the work that makes this story true.
- [Task 06 — Coordinator counts rows](../../../../../../docs/tasks/workflow-dag-engine/06-coordinator-count-rows.md) — the work that makes this story true.

## See also

- [US-DPR-07](US-DPR-07-require-n-unsatisfiable.md) — the unsatisfiable
  counterpart of the same `{:require_n, n}` strategy.
- [US-DPR-03](US-DPR-03-all-completion-succeeds.md) — the `:all` completion
  strategy alternative.
- [US-DPR-05](US-DPR-05-any-completion-first-success.md) — the `:any` completion
  strategy alternative.
