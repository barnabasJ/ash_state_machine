# US-GTA-02 — Region wrapper actions expose empty input metadata

**User-type:** developer **Status:** spec

```gherkin
Given a static parallel region delegates to child region update actions
When AshStateMachine generates wrapper actions such as `:payment_process`
Then each wrapper action has `accept: []` input metadata
And the wrapper action still delegates to the region through `DelegateToRegion`
```

## Acceptance criteria

- Generated region wrapper actions compile under Ash's action-input cache.
- Each generated wrapper update action exposes `accept == []`, not `nil`.
- Each wrapper action keeps its `DelegateToRegion` change with the correct region
  and child action.

## Notes

- **Reference / related code:**
  `lib/transformers/generate_region_actions.ex`,
  `test/region_wrapper_actions_test.exs`
- **Size:** <= ~200 lines, 1 module — else split into subtasks.

## Tasks

- [Task 01 — Green the ash_jobs test suite](../../../../../../docs/tasks/workflow-dag-engine/01-ash-jobs-test-cleanup.md) — fixes generated no-input wrapper action metadata exposed by ash_jobs static parallel-step compilation.

## See also

- [US-DPR-08](../dynamic-parallel-regions/US-DPR-08-static-region-backcompat.md)
  — static region behavior that generated wrapper actions support.
