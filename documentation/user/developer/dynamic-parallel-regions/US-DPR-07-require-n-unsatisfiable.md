# US-DPR-07 — `{:require_n, n}` is unsatisfiable when too many rows fail (insufficient_completions)

**User-type:** developer **Status:** spec

```gherkin
Given a parent with a has_many dynamic region of four rows and completion_strategy {:require_n, 3}
When two of the four related rows reach a failure terminal state
And check_completion/2 is invoked for the parent
Then it returns {:error, :insufficient_completions} because failed_count > total - count
```

## Acceptance criteria

- With `{:require_n, 3}` over four rows, two failures make `n` successes
  unreachable (`failed_count > total - count`) and `check_completion/2` returns
  `{:error, :insufficient_completions}` rather than staying pending.
- `total` is computed from the runtime row count.

## Notes

- **Reference / related code:** `AshStateMachine.ParallelCoordinator`
  `check_group_completion/3` (`{:require_n, count}` unreachability guard)
- **Size:** ≤ ~200 lines, 1 module — else split into subtasks.

## Tasks

- [Task 05 — Coordinator loads rows](../../../../../../docs/tasks/workflow-dag-engine/05-coordinator-load-rows.md) — the work that makes this story true.
- [Task 06 — Coordinator counts rows](../../../../../../docs/tasks/workflow-dag-engine/06-coordinator-count-rows.md) — the work that makes this story true.
- [Task 11 — require_n at runtime](../../../../../../docs/tasks/workflow-dag-engine/11-require-n-runtime.md) — the work that makes this story true.

## See also

- [US-DPR-06](US-DPR-06-require-n-runtime-count.md) — the success counterpart of
  the same `{:require_n, n}` strategy.
- [US-DPR-04](US-DPR-04-all-completion-fails-fast.md) — the analogous fail-fast
  path for the `:all` strategy.
