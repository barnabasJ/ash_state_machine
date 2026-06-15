# US-DPR-08 — A static `region :name, Resource` keeps its has_one semantics (back-compat)

**User-type:** developer **Status:** spec

```gherkin
Given a parallel_region declaring region :payment, PaymentMachine and region :inventory, InventoryMachine
When the resource compiles and the parent enters the region's enter_state
Then AddParallelRegionRelationships adds a has_one :payment and has_one :inventory
And exactly one child of each is created, unchanged from the pre-dynamic behavior
```

## Acceptance criteria

- A static `region :name, Resource` still produces a `has_one` per region and
  creates exactly one child per region with `parent_id` set.
- The dynamic `has_many` dispatch is additive — existing static declarations
  behave exactly as before.

## Notes

- **Reference / related code:**
  `AshStateMachine.Transformers.AddParallelRegionRelationships`,
  `AshStateMachine.BuiltinChanges.ActivateParallelRegions`
- **Size:** ≤ ~200 lines, 1 module — else split into subtasks.

## Tasks

- [Task 02 — Region :relationship field](../../../../../../docs/tasks/workflow-dag-engine/02-region-relationship-field.md) — the work that makes this story true.
- [Task 03 — has_many region relationship](../../../../../../docs/tasks/workflow-dag-engine/03-has-many-region-relationship.md) — the work that makes this story true.

## See also

- [US-DPR-01](US-DPR-01-declare-has-many-region.md) — the dynamic `has_many`
  region declaration this static form coexists with.
