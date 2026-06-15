# US-TSI-02 — Info.state_machine_terminal_states/1 returns all terminal states

**User-type:** developer **Status:** spec

```gherkin
Given a resource that uses the AshStateMachine extension with a set of transitions
When I call AshStateMachine.Info.state_machine_terminal_states/1 with that resource
Then I get every terminal state — states that never appear as a transition target — regardless of success or failure
```

## Acceptance criteria

- `AshStateMachine.Info.state_machine_terminal_states/1` returns every state
  that never appears as a transition `to` target, ignoring the `:*` wildcard.
- `ParallelCoordinator` delegates to the public function instead of its private
  `get_all_terminal_states/1` copy.

## Notes

- **Reference / related code:**
  `packages/ash_state_machine/lib/parallel_coordinator.ex`
  (`get_all_terminal_states/1`), `packages/ash_state_machine/lib/info.ex`
- **Size:** ≤ ~200 lines, 1 module — else split into subtasks.

## Tasks

- [Task 08 — Terminal-state Info API](../../../../../../docs/tasks/workflow-dag-engine/08-terminal-state-info-api.md) — the work that makes this story true.

## See also

- [US-TSI-01](US-TSI-01-success-terminal-states.md) — companion introspection
  that returns only the success terminal states (terminal minus failure).
