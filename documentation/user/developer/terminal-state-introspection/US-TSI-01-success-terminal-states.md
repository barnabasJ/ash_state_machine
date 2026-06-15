# US-TSI-01 — Info.state_machine_success_terminal_states/1 returns the success terminal states

**User-type:** developer **Status:** spec

```gherkin
Given a resource that uses the AshStateMachine extension with terminal and failure states
When I call AshStateMachine.Info.state_machine_success_terminal_states/1 with that resource
Then I get the terminal states that are not failure states (terminal minus failure)
```

## Acceptance criteria

- `AshStateMachine.Info.state_machine_success_terminal_states/1` returns the
  terminal states minus the failure states.
- `ParallelCoordinator` delegates to the public function instead of its private
  `get_success_terminal_states/1` copy.

## Notes

- **Reference / related code:**
  `packages/ash_state_machine/lib/parallel_coordinator.ex`
  (`get_success_terminal_states/1`), `packages/ash_state_machine/lib/info.ex`
- **Size:** ≤ ~200 lines, 1 module — else split into subtasks.

## Tasks

- [Task 08 — Terminal-state Info API](../../../../../../docs/tasks/workflow-dag-engine/08-terminal-state-info-api.md) — the work that makes this story true.

## See also

- [US-TSI-02](US-TSI-02-all-terminal-states.md) — companion introspection that
  returns every terminal state, not just the success ones.
- [US-TSI-03](US-TSI-03-external-readiness-filter.md) — downstream consumer that
  builds an external readiness filter from the success terminal states.
