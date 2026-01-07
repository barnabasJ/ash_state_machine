# SPDX-FileCopyrightText: 2023 ash_state_machine contributors <https://github.com/ash-project/ash_state_machine/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshStateMachine.BuiltinChanges do
  @moduledoc """
  Changes for working with AshStateMachine resources.
  """

  @doc """
  Changes the state to the target state, validating the transition
  """
  def transition_state(target) do
    {AshStateMachine.BuiltinChanges.TransitionState, target: target}
  end

  @doc """
  Try and transition to the next state. Must be only one possible next state.
  """
  def next_state, do: AshStateMachine.BuiltinChanges.NextState

  @doc """
  Activates parallel regions by creating region resources.

  This change should be used in actions that transition to the activation state.

  ## Example

      update :start_processing do
        change transition_state(:processing)
        change activate_parallel_regions()
      end
  """
  def activate_parallel_regions do
    AshStateMachine.BuiltinChanges.ActivateParallelRegions
  end

  @doc """
  Checks if the parent resource should transition after a parallel region completes.

  This change is intended for use on parallel region resources. After the region
  transitions to a terminal state, it checks if the parent's completion criteria
  are met and optionally triggers the parent's completion action.

  ## Options

  - `:parent_attribute` - The attribute on this resource that references the parent (required)
  - `:parent_resource` - The parent resource module (required)
  - `:on_complete` - Action to call on parent when completion criteria are met (optional)
  - `:on_failure` - Action to call on parent when completion fails with :require_all (optional)

  ## Example

      update :complete do
        change transition_state(:completed)
        change check_parallel_completion(
          parent_attribute: :order_id,
          parent_resource: Order,
          on_complete: :complete,
          on_failure: :fail
        )
      end
  """
  def check_parallel_completion(opts) do
    {AshStateMachine.BuiltinChanges.CheckParallelCompletion, opts}
  end

  @doc """
  Delegates an action to a parallel region's child resource.

  This change loads the region, calls the specified action on it,
  then checks if parallel completion criteria are met and invokes
  the on_complete callback if so.

  ## Example

      update :payment_complete do
        change delegate_to_region(:payment, :complete)
      end

  ## Options

  - `:region` - The region name (atom)
  - `:action` - The action to call on the region
  - `:domain` - The Ash domain (optional, defaults to resource's domain)
  """
  def delegate_to_region(region, action, opts \\ []) do
    {AshStateMachine.BuiltinChanges.DelegateToRegion,
     Keyword.merge(opts, region: region, action: action)}
  end
end
