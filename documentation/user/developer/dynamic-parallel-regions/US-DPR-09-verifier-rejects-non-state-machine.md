# US-DPR-09 — The verifier rejects a relationship whose destination isn't an AshStateMachine

**User-type:** developer **Status:** spec

```gherkin
Given a region sourced from a has_many :line_items whose destination resource does not use AshStateMachine
When the parent resource is compiled
Then VerifyParallelRegions raises a Spark.Error.DslError
And the message names the offending region and instructs adding the AshStateMachine extension
```

## Acceptance criteria

- A dynamic `has_many` region pointing at a non-state-machine destination raises
  `Spark.Error.DslError` at compile time.
- The error message names the offending region and instructs adding the
  AshStateMachine extension.

## Notes

- **Reference / related code:**
  `AshStateMachine.Verifiers.VerifyParallelRegions.verify_region/3`
  (`uses_ash_state_machine?/1`)
- **Size:** ≤ ~200 lines, 1 module — else split into subtasks.

## Tasks

- [Task 07 — Verify dynamic region](../../../../../../docs/tasks/workflow-dag-engine/07-verify-dynamic-region.md) — the work that makes this story true.

## See also

- [US-DPR-01](US-DPR-01-declare-has-many-region.md) — the `has_many` region
  declaration this verifier validates the destination of.
