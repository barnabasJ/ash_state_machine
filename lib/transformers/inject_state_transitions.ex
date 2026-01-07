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
    # First, maybe generate a create action for the default initial state
    {:ok, dsl_state} = maybe_generate_create_action(dsl_state)

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

  defp maybe_generate_create_action(dsl_state) do
    existing_create = Ash.Resource.Info.action(dsl_state, :create)

    case AshStateMachine.Info.state_machine_default_initial_state(dsl_state) do
      # No default initial state configured
      {:ok, nil} ->
        {:ok, dsl_state}

      :error ->
        {:ok, dsl_state}

      # User already defined a create action
      {:ok, _} when not is_nil(existing_create) ->
        {:ok, dsl_state}

      # Generate create action
      {:ok, default_initial_state} ->
        generate_create_action(dsl_state, default_initial_state)
    end
  end

  defp generate_create_action(dsl_state, _initial_state) do
    # Create actions don't support require_atomic?, so we just generate a simple create action
    # The RunEntryExitChanges will handle entry callbacks automatically
    Ash.Resource.Builder.add_action(dsl_state, :create, :create, primary?: true)
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

    # Build the transition state change
    transition_change_ref =
      if target_state do
        {AshStateMachine.BuiltinChanges.TransitionState, target: target_state}
      else
        # Multiple targets - use next_state which will error if ambiguous
        AshStateMachine.BuiltinChanges.NextState
      end

    transition_change = Ash.Resource.Builder.build_action_change(transition_change_ref)

    # Merge configuration from all transitions for this action
    merged_config = merge_transition_configs(transitions)

    # Build transition-specific changes
    transition_changes =
      Enum.map(merged_config.changes, fn change_spec ->
        Ash.Resource.Builder.build_action_change(change_spec)
      end)

    # Auto-inject ActivateParallelRegions if target is an activation state
    parallel_region_changes = build_parallel_region_changes(dsl_state, target_state)

    # Combine all changes: transition_state + parallel regions + transition-specific changes
    # Note: Transition validations are handled separately (TODO: implement validation support)
    all_changes = [transition_change] ++ parallel_region_changes ++ transition_changes

    # Build action options
    action_opts =
      [changes: all_changes]
      |> maybe_add_accept(merged_config.accept)
      |> maybe_add_require_atomic(merged_config.require_atomic?)

    Ash.Resource.Builder.add_action(dsl_state, :update, action_name, action_opts)
  end

  defp build_parallel_region_changes(dsl_state, target_state) when is_atom(target_state) do
    activation_states = AshStateMachine.Info.state_machine_region_activation_states(dsl_state)

    if target_state in activation_states do
      [
        Ash.Resource.Builder.build_action_change(
          AshStateMachine.BuiltinChanges.ActivateParallelRegions
        )
      ]
    else
      []
    end
  end

  defp build_parallel_region_changes(_dsl_state, _target_state), do: []

  defp merge_transition_configs(transitions) do
    # Merge config from all transitions for this action
    # This handles cases where multiple transitions map to the same action
    Enum.reduce(transitions, %{accept: [], changes: [], validations: [], require_atomic?: nil}, fn
      transition, acc ->
        %{
          accept: Enum.uniq(acc.accept ++ (transition.accept || [])),
          changes: acc.changes ++ (transition.changes || []),
          validations: acc.validations ++ (transition.validations || []),
          # Use first non-nil value (false || nil returns nil, so we need explicit handling)
          require_atomic?: merge_require_atomic(acc.require_atomic?, transition.require_atomic?)
        }
    end)
  end

  # Merge require_atomic? values - first explicit value wins
  defp merge_require_atomic(nil, value), do: value
  defp merge_require_atomic(value, _), do: value

  defp maybe_add_accept(opts, []), do: opts
  defp maybe_add_accept(opts, accept), do: Keyword.put(opts, :accept, accept)

  defp maybe_add_require_atomic(opts, nil), do: opts
  defp maybe_add_require_atomic(opts, value), do: Keyword.put(opts, :require_atomic?, value)

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
