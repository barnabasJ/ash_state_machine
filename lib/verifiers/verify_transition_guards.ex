# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshStateMachine.Verifiers.VerifyTransitionGuards do
  @moduledoc """
  Verifies that transition guards are properly configured.

  Validates:
  1. At most one transition without a guard per action/from-state combination
  2. Multiple unguarded transitions for same action/from-state = compile error

  Skips validation for actions that have manual transition logic defined,
  as the user has explicitly opted into handling ambiguity themselves.
  """
  use Spark.Dsl.Verifier

  def verify(dsl_state) do
    module = Spark.Dsl.Verifier.get_persisted(dsl_state, :module)
    transitions = AshStateMachine.Info.state_machine_transitions(dsl_state)

    # Get actions that have manual transition logic (user-defined)
    manual_transition_actions = get_manual_transition_actions(dsl_state)

    # Group transitions by {action, from_state}, excluding wildcards and manual actions
    transitions
    |> Enum.reject(&(&1.action == :*))
    |> Enum.reject(&(&1.action in manual_transition_actions))
    |> group_by_action_and_from()
    |> Enum.each(fn {{action, from_state}, group_transitions} ->
      validate_guard_group(module, action, from_state, group_transitions)
    end)

    :ok
  end

  defp get_manual_transition_actions(dsl_state) do
    dsl_state
    |> Ash.Resource.Info.actions()
    |> Enum.filter(&(&1.type in [:create, :update]))
    |> Enum.filter(&has_manual_transition?/1)
    |> Enum.map(& &1.name)
  end

  defp has_manual_transition?(action) do
    Enum.any?(action.changes || [], fn change ->
      change_module = extract_change_module(change)

      change_module in [
        AshStateMachine.BuiltinChanges.TransitionState,
        AshStateMachine.BuiltinChanges.NextState,
        AshStateMachine.BuiltinChanges.GuardedTransition
      ]
    end)
  end

  defp extract_change_module(%{change: {module, _opts}}), do: module
  defp extract_change_module(%{change: module}) when is_atom(module), do: module
  defp extract_change_module(_), do: nil

  defp group_by_action_and_from(transitions) do
    transitions
    |> Enum.flat_map(fn transition ->
      transition.from
      |> List.wrap()
      |> Enum.reject(&(&1 == :*))
      |> Enum.map(fn from -> {{transition.action, from}, transition} end)
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  defp validate_guard_group(module, action, from_state, transitions) do
    # Count transitions without guards
    no_guard_count = Enum.count(transitions, &Enum.empty?(&1.guard))

    cond do
      # Single transition - no guard needed
      length(transitions) == 1 ->
        :ok

      # Multiple transitions without guards - ambiguous
      no_guard_count > 1 ->
        raise Spark.Error.DslError,
          module: module,
          path: [:state_machine, :transitions],
          message: """
          Ambiguous transitions for action :#{action} from state :#{from_state}.

          Found #{no_guard_count} transitions without guards. When multiple transitions
          share the same action and from-state, at most one can omit the guard
          (as the default fallback).

          Add guards to disambiguate:

              transition :#{action}, from: :#{from_state}, to: :some_state,
                         guard: compare(:field, greater_than: value)
          """

      # All have guards or exactly one doesn't - OK
      true ->
        :ok
    end
  end
end
