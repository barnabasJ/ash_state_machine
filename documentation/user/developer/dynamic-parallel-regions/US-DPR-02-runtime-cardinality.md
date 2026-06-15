# US-DPR-02 — Fan-out cardinality is determined at runtime by the number of related rows

**User-type:** developer **Status:** spec

```gherkin
Given a parent with a has_many :line_items dynamic region and three persisted line-item rows
When the parent transitions into the region's enter_state and activate_parallel_regions runs
Then exactly three child state machines are tracked for the region
And a parent with five rows tracks five children, with no DSL change between the two
```

## Acceptance criteria

- After activation, the number of tracked child state machines equals the loaded
  related-row count (three rows → three children, five rows → five children).
- The fan-out width is resolved at runtime from the relationship, with no DSL
  change between cardinalities.

## Notes

- **Reference / related code:**
  `AshStateMachine.BuiltinChanges.ActivateParallelRegions.change/3`
- **Size:** ≤ ~200 lines, 1 module — else split into subtasks.

## Tasks

- [Task 03 — has_many region relationship](../../../../../../docs/tasks/workflow-dag-engine/03-has-many-region-relationship.md) — the work that makes this story true.
- [Task 04 — Dynamic activation](../../../../../../docs/tasks/workflow-dag-engine/04-dynamic-activation.md) — the work that makes this story true.

## See also

- [US-DPR-01](US-DPR-01-declare-has-many-region.md) — the `has_many` declaration
  whose rows this fan-out counts at runtime.
- [US-DPR-10](../../operator/dynamic-parallel-regions/US-DPR-10-one-active-child-per-row.md)
  — the operator-facing one-child-per-row view of the same runtime fan-out.
