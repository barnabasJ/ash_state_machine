# US-DPR-10 — A running parent shows exactly one active child per related row

**User-type:** operator **Status:** spec

```gherkin
Given a parent activated into a has_many dynamic region with three related rows
When I inspect the parent's region state while it is processing
Then get_region_states/2 reports one child record per related row
And there are no duplicate or orphan children for any row
```

## Acceptance criteria

- Inspecting a running parent reports exactly one child record per related row
  (three rows → three children).
- There are no duplicate or orphan children — a one-to-one mapping between
  related rows and active children.

## Notes

- **Reference / related code:**
  `AshStateMachine.ParallelCoordinator.get_region_states/2` (`load_region/3`),
  `AshStateMachine.BuiltinChanges.ActivateParallelRegions`
- **Size:** ≤ ~200 lines, 1 module — else split into subtasks.

## Tasks

- [Task 04 — Dynamic activation](../../../../../../docs/tasks/workflow-dag-engine/04-dynamic-activation.md) — the work that makes this story true.

## See also

- [US-DPR-02](../../developer/dynamic-parallel-regions/US-DPR-02-runtime-cardinality.md)
  — the runtime fan-out that produces the one-child-per-row mapping inspected
  here.
- [US-DPR-01](../../developer/dynamic-parallel-regions/US-DPR-01-declare-has-many-region.md)
  — the `has_many` declaration whose rows these children map to.
