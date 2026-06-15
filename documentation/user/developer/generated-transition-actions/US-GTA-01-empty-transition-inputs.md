# US-GTA-01 — Transition-generated actions expose empty input metadata

**User-type:** developer **Status:** spec

```gherkin
Given a state-machine transition references an action the resource did not define explicitly
When AshStateMachine generates that update action from the transition
Then the generated action has `accept: []` input metadata
And the action compiles and runs as a normal no-input Ash update action
```

## Acceptance criteria

- Generated update actions from transitions compile under Ash's action-input
  cache.
- A generated action with no accepted attributes exposes `accept == []`, not
  `nil`.
- The generated action still performs the configured state transition.

## Notes

- **Reference / related code:**
  `lib/transformers/inject_state_transitions.ex`,
  `test/auto_transition_test.exs`
- **Size:** <= ~200 lines, 1 module — else split into subtasks.

## Tasks

- [Task 01 — Green the ash_jobs test suite](../../../../../../docs/tasks/workflow-dag-engine/01-ash-jobs-test-cleanup.md) — fixes generated no-input action metadata exposed by ash_jobs static parallel-step compilation.

## See also

- [US-GTA-02](US-GTA-02-empty-wrapper-inputs.md) — the parallel-region wrapper
  action form of the same no-input action contract.
