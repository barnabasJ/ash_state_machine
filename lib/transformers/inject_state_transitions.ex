# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshStateMachine.Transformers.InjectStateTransitions do
  @moduledoc """
  Automatically injects transition_state changes into actions that match
  transition definitions, unless the user has manually configured transitions.

  Also generates missing actions from transition definitions.

  ## Behavior

  1. For each transition definition:
     - If no matching action exists, generate an update action with `transition_state`
     - If action exists but has no transition change, inject `transition_state`
     - If action exists with manual transition logic, skip (opt-out)

  2. Wildcards (`:*`) are skipped for action generation (too generic)

  3. Multiple `to` states use `next_state()` which errors at runtime if ambiguous
  """
  use Spark.Dsl.Transformer
  alias Spark.Dsl.Transformer

  # Run after wildcards are expanded
  def after?(AshStateMachine.Transformers.FillInTransitionDefaults), do: true
  def after?(_), do: false

  # Run before state attribute is added and verifiers run
  def before?(AshStateMachine.Transformers.AddState), do: true
  def before?(Ash.Resource.Transformers.DefaultAccept), do: true
  def before?(_), do: false

  def transform(dsl_state) do
    transitions = AshStateMachine.Info.state_machine_transitions(dsl_state)

    # Group transitions by action name (excluding wildcards)
    transitions_by_action =
      transitions
      |> Enum.reject(fn t -> t.action == :* end)
      |> Enum.group_by(& &1.action)

    # Process each action's transitions
    Enum.reduce_while(transitions_by_action, {:ok, dsl_state}, fn {action_name,
                                                                   action_transitions},
                                                                  {:ok, acc} ->
      case process_action(acc, action_name, action_transitions) do
        {:ok, new_state} -> {:cont, {:ok, new_state}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp process_action(dsl_state, action_name, transitions) do
    existing_action = Ash.Resource.Info.action(dsl_state, action_name)

    cond do
      # No action exists - generate one
      is_nil(existing_action) ->
        generate_action(dsl_state, action_name, transitions)

      # Action exists and is update/create - maybe inject transition
      existing_action.type in [:update, :create] ->
        maybe_inject_transition(dsl_state, existing_action, transitions)

      # Action exists but is wrong type (read/destroy) - skip
      true ->
        {:ok, dsl_state}
    end
  end

  defp generate_action(dsl_state, action_name, transitions) do
    target_state = determine_target_state(transitions)

    change_ref =
      if target_state do
        {AshStateMachine.BuiltinChanges.TransitionState, target: target_state}
      else
        # Multiple targets - use next_state which will error if ambiguous
        AshStateMachine.BuiltinChanges.NextState
      end

    # Build the change struct using the builder (returns {:ok, struct})
    # Pass as-is since handle_nested_builders unwraps {:ok, _} tuples
    change = Ash.Resource.Builder.build_action_change(change_ref)

    Ash.Resource.Builder.add_action(dsl_state, :update, action_name, changes: [change])
  end

  defp maybe_inject_transition(dsl_state, action, transitions) do
    if has_manual_transition?(action) do
      # User opted out by adding their own transition logic
      {:ok, dsl_state}
    else
      inject_transition(dsl_state, action, transitions)
    end
  end

  defp inject_transition(dsl_state, action, transitions) do
    target_state = determine_target_state(transitions)

    change =
      if target_state do
        {AshStateMachine.BuiltinChanges.TransitionState, target: target_state}
      else
        # Multiple targets - use next_state which will error if ambiguous
        AshStateMachine.BuiltinChanges.NextState
      end

    # Build a change struct
    {:ok, change_struct} = Ash.Resource.Builder.build_action_change(change)

    # Prepend the transition change to existing changes
    updated_action = %{action | changes: [change_struct | action.changes]}

    # Replace the action in dsl_state using replace_entity with a custom matcher
    {:ok,
     Transformer.replace_entity(
       dsl_state,
       [:actions],
       updated_action,
       fn a -> a.name == action.name and a.type == action.type end
     )}
  end

  defp has_manual_transition?(action) do
    Enum.any?(action.changes, fn change ->
      change_module = extract_change_module(change)

      change_module in [
        AshStateMachine.BuiltinChanges.TransitionState,
        AshStateMachine.BuiltinChanges.NextState
      ]
    end)
  end

  defp extract_change_module(%{change: {module, _opts}}), do: module
  defp extract_change_module(%{change: module}) when is_atom(module), do: module
  defp extract_change_module(_), do: nil

  defp determine_target_state(transitions) do
    # Get all unique target states across all transitions for this action
    targets =
      transitions
      |> Enum.flat_map(fn t -> List.wrap(t.to) end)
      |> Enum.uniq()

    case targets do
      [single] -> single
      # Multiple targets - return nil to signal next_state() should be used
      _ -> nil
    end
  end
end
