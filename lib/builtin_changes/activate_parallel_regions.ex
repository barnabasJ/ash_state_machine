# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshStateMachine.BuiltinChanges.ActivateParallelRegions do
  @moduledoc """
  A change that activates parallel regions when the parent enters a specific state.

  This change creates records for regions within the parallel_region group whose
  `enter_state` matches the target state of the transition.

  ## Usage

  This change is typically used in combination with `transition_state/1`:

      update :start_processing do
        change transition_state(:processing)
        change activate_parallel_regions()
      end

  Given a parallel_region configured as:

      parallel_region :processing, :completed do
        region :payment, PaymentMachine
        region :inventory, InventoryMachine
      end

  When transitioning to `:processing`, both `PaymentMachine` and `InventoryMachine`
  resources will be created with `parent_id` set to the parent's id.
  """
  use Ash.Resource.Change

  @doc false
  def change(changeset, _opts, context) do
    state_attribute = AshStateMachine.Info.state_machine_state_attribute!(changeset.resource)
    target_state = Ash.Changeset.get_attribute(changeset, state_attribute)

    regions =
      AshStateMachine.Info.state_machine_regions_for_state(
        changeset.resource,
        target_state
      )

    if Enum.empty?(regions) do
      changeset
    else
      Ash.Changeset.after_action(changeset, fn _changeset, result ->
        create_region_resources(result, regions, context)
      end)
    end
  end

  defp create_region_resources(parent, regions, context) do
    parent_id = parent.id

    results =
      Enum.map(regions, fn region ->
        activate_region(parent, region, parent_id, context)
      end)

    errors = Enum.filter(results, &match?({:error, _}, &1))

    case errors do
      [] ->
        {:ok, parent}

      [{:error, first_error} | _] ->
        {:error, first_error}
    end
  end

  defp activate_region(parent, region, parent_id, context) do
    if AshStateMachine.Region.dynamic?(region) do
      load_dynamic_region(parent, region, context)
    else
      create_region_resource(region, parent_id, context)
    end
  end

  defp load_dynamic_region(parent, region, context) do
    domain = Ash.Resource.Info.domain(parent.__struct__)
    relationship_name = AshStateMachine.Region.relationship_name(region)

    parent
    |> Ash.load!([relationship_name],
      domain: domain,
      lazy?: false,
      tenant: context.tenant,
      actor: context.actor
    )

    {:ok, parent}
  end

  defp create_region_resource(region, parent_id, context) do
    # Get the domain from resource's configured domain
    domain = Ash.Resource.Info.domain(region.resource)

    region.resource
    |> Ash.Changeset.for_create(:create, %{parent_id: parent_id},
      domain: domain,
      tenant: context.tenant,
      actor: context.actor
    )
    |> Ash.create()
  end
end
