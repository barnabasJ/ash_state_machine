# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshStateMachine.Transformers.GenerateRegionActions do
  @moduledoc """
  Generates wrapper actions on the parent resource for each region's update actions.

  For each parallel region, for each region within it, and for each update action
  on that region's resource, this transformer generates a wrapper action on the parent.

  ## Generated Actions

  For a parent with:
  ```elixir
  parallel_region :processing, :completed do
    region :payment, PaymentMachine
    region :inventory, InventoryMachine
  end
  ```

  Where PaymentMachine has actions `:process`, `:complete`, `:fail`, this generates:
  - `:payment_process`
  - `:payment_complete`
  - `:payment_fail`

  Each generated action uses `delegate_to_region/2` to:
  1. Load and call the region's action
  2. Check completion criteria
  3. Invoke on_complete callback if criteria met

  ## Opt-out

  If a parent already defines an action with the generated name, that action is not overwritten.
  """

  use Spark.Dsl.Transformer

  # Run after parallel regions are configured and relationships added
  def after?(AshStateMachine.Transformers.AddParallelRegionRelationships), do: true
  def after?(AshStateMachine.Transformers.InjectStateTransitions), do: true
  def after?(_), do: false

  def transform(dsl_state) do
    parallel_regions = AshStateMachine.Info.state_machine_parallel_regions(dsl_state)

    if Enum.empty?(parallel_regions) do
      {:ok, dsl_state}
    else
      generate_all_region_actions(dsl_state, parallel_regions)
    end
  end

  defp generate_all_region_actions(dsl_state, parallel_regions) do
    Enum.reduce_while(parallel_regions, {:ok, dsl_state}, fn parallel_region, {:ok, acc} ->
      case generate_actions_for_parallel_region(acc, parallel_region) do
        {:ok, new_state} -> {:cont, {:ok, new_state}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp generate_actions_for_parallel_region(dsl_state, parallel_region) do
    Enum.reduce_while(parallel_region.regions || [], {:ok, dsl_state}, fn region, {:ok, acc} ->
      case generate_actions_for_region(acc, region) do
        {:ok, new_state} -> {:cont, {:ok, new_state}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp generate_actions_for_region(dsl_state, region) do
    if AshStateMachine.Region.dynamic?(region) do
      {:ok, dsl_state}
    else
      region_name = region.name
      region_resource = region.resource

      # Get update actions from the region resource
      region_actions = get_region_update_actions(region_resource)

      Enum.reduce_while(region_actions, {:ok, dsl_state}, fn action, {:ok, acc} ->
        wrapper_action_name = :"#{region_name}_#{action.name}"

        # Skip if parent already has this action defined
        if Ash.Resource.Info.action(acc, wrapper_action_name) do
          {:cont, {:ok, acc}}
        else
          case generate_wrapper_action(acc, region_name, action.name, wrapper_action_name) do
            {:ok, new_state} -> {:cont, {:ok, new_state}}
            {:error, error} -> {:halt, {:error, error}}
          end
        end
      end)
    end
  end

  defp get_region_update_actions(region_resource) do
    region_resource
    |> Ash.Resource.Info.actions()
    |> Enum.filter(&(&1.type == :update))
  end

  defp generate_wrapper_action(dsl_state, region_name, region_action, wrapper_action_name) do
    # Build the delegate_to_region change
    change_ref =
      {AshStateMachine.BuiltinChanges.DelegateToRegion,
       region: region_name, action: region_action}

    change = Ash.Resource.Builder.build_action_change(change_ref)

    # Generate the wrapper action
    Ash.Resource.Builder.add_action(dsl_state, :update, wrapper_action_name,
      accept: [],
      changes: [change],
      require_atomic?: false
    )
  end
end
