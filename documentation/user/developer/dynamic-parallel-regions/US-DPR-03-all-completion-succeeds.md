# US-DPR-03 — `:all` completion succeeds when every related row reaches a success state

**User-type:** developer **Status:** spec

```gherkin
Given a parent with a has_many dynamic region of four rows and completion_strategy :all
When all four related rows reach a success terminal state
And check_completion/2 is invoked for the parent
Then it returns {:ok, :complete, context} with the configured exit_state
```

## Acceptance criteria

- With `:all` strategy and every loaded row at `:succeeded`,
  `check_completion/2` returns `{:ok, :complete, context}` carrying the
  configured `exit_state`.
- The success determination is made over the loaded row count, not a static
  region list.

## Notes

- **Reference / related code:**
  `AshStateMachine.ParallelCoordinator.check_completion/2` (`load_region/3`,
  `region_status/1`, `check_group_completion/3`)
- **Size:** ≤ ~200 lines, 1 module — else split into subtasks.

## Tasks

- [Task 05 — Coordinator loads rows](../../../../../../docs/tasks/workflow-dag-engine/05-coordinator-load-rows.md) — the work that makes this story true.
- [Task 06 — Coordinator counts rows](../../../../../../docs/tasks/workflow-dag-engine/06-coordinator-count-rows.md) — the work that makes this story true.

## See also

- [US-DPR-04](US-DPR-04-all-completion-fails-fast.md) — the failure path of the
  same `:all` strategy.
- [US-DPR-05](US-DPR-05-any-completion-first-success.md) — the `:any` completion
  strategy alternative.
- [US-DPR-06](US-DPR-06-require-n-runtime-count.md) — the `{:require_n, n}`
  completion strategy alternative.
