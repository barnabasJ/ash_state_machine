# US-DPR-11 — Completion is recomputed each time a child reaches a terminal state

**User-type:** qa-engineer **Status:** spec

```gherkin
Given a parent with a has_many dynamic region of three rows and completion_strategy :all
When the first child reaches a success state and check_completion/2 returns {:ok, :pending}
And later the remaining two children each reach a success state
Then a fresh check_completion/2 reloads the rows and returns {:ok, :complete, context}
```

## Acceptance criteria

- An early `check_completion/2` (only some children terminal) returns
  `{:ok, :pending}`.
- A later `check_completion/2` reloads the rows and returns
  `{:ok, :complete, context}` — each call recomputes statuses from current data
  rather than caching an earlier pass.

## Notes

- **Reference / related code:**
  `AshStateMachine.ParallelCoordinator.check_completion/2` (`load_region/3`,
  `region_status/1`), `AshStateMachine.BuiltinChanges.CheckParallelCompletion`
- **Size:** ≤ ~200 lines, 1 module — else split into subtasks.

## Tasks

- [Task 05 — Coordinator loads rows](../../../../../../docs/tasks/workflow-dag-engine/05-coordinator-load-rows.md) — the work that makes this story true.

## See also

- [US-DPR-03](../../developer/dynamic-parallel-regions/US-DPR-03-all-completion-succeeds.md)
  — the `:all` success determination this recompute eventually reaches.
- [US-DPR-04](../../developer/dynamic-parallel-regions/US-DPR-04-all-completion-fails-fast.md)
  — the `:all` fail-fast path a later recompute can surface.
