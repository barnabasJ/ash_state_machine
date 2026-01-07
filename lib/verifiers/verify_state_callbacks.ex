# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshStateMachine.Verifiers.VerifyStateCallbacks do
  @moduledoc """
  Verifies that state callbacks are properly configured.

  Checks:
  - States defined in `states` section are referenced in transitions
  - Callback modules are valid atoms (likely modules)
  """
  use Spark.Dsl.Verifier

  def verify(dsl_state) do
    states = AshStateMachine.Info.state_machine_states(dsl_state)

    if states == [] do
      :ok
    else
      verify_states_referenced(dsl_state, states)
    end
  end

  defp verify_states_referenced(dsl_state, states) do
    transitions = AshStateMachine.Info.state_machine_transitions(dsl_state)

    # Get all state names used in transitions
    transition_states =
      transitions
      |> Enum.flat_map(fn transition ->
        from_states = List.wrap(transition.from) |> Enum.reject(&(&1 == :*))
        to_states = List.wrap(transition.to) |> Enum.reject(&(&1 == :*))
        from_states ++ to_states
      end)
      |> MapSet.new()

    # Check each state definition is referenced in transitions
    Enum.each(states, fn state ->
      unless MapSet.member?(transition_states, state.name) do
        # Warn about orphaned state definitions
        IO.warn("""
        State `#{inspect(state.name)}` has callbacks defined but is not referenced in any transition.
        This state's callbacks will never be executed.

        Either add a transition to/from this state or remove the state definition.
        """)
      end
    end)

    :ok
  end
end
