# US-DPR-01 — Declare a region sourced from a `has_many` relationship

**User-type:** developer **Status:** spec

```gherkin
Given a parent resource using AshStateMachine with a has_many :line_items relationship to a child AshStateMachine resource
When I declare region :line_items inside a parallel_region :processing, :completed referencing that has_many
Then the region entity records :line_items as a relationship-sourced region
And no compile error is raised for the absence of a singleton resource module
```

## Acceptance criteria

- A `region :line_items` referencing a `has_many` relationship compiles without
  a singleton `resource` module and is recorded as a relationship-sourced
  (dynamic) region.
- The `AshStateMachine.Region` entity carries the named `has_many` relationship
  so downstream activation/coordination fan out over rows.

## Notes

- **Reference / related code:** `lib/ash_state_machine.ex` (`@region` Spark
  entity), `lib/region.ex` (`AshStateMachine.Region`)
- **Size:** ≤ ~200 lines, 1 module — else split into subtasks.

## Tasks

- [Task 02 — Region :relationship field](../../../../../../docs/tasks/workflow-dag-engine/02-region-relationship-field.md) — the work that makes this story true.
- [Task 03 — has_many region relationship](../../../../../../docs/tasks/workflow-dag-engine/03-has-many-region-relationship.md) — the work that makes this story true.

## See also

- [US-DPR-02](US-DPR-02-runtime-cardinality.md) — the runtime fan-out over the
  rows of this declared relationship-sourced region.
- [US-DPR-08](US-DPR-08-static-region-backcompat.md) — the static
  `region :name, Resource` counterpart this dynamic form is additive to.
- [US-DPR-09](US-DPR-09-verifier-rejects-non-state-machine.md) — the verifier
  that guards the relationship destination of this declaration.
