# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshStateMachine.BuiltinChanges.DelegateToRegion do
  @moduledoc """
  Delegates an action to a parallel region's child resource.

  This change:
  1. Loads the region record via the relationship
  2. Calls the specified action on the region resource
  3. Checks parallel completion after the region action
  4. Invokes the on_complete callback if completion criteria are met

  ## Options

  - `:region` - The region name (atom) - corresponds to the relationship name
  - `:action` - The action name to call on the region resource
  - `:domain` - The Ash domain to use for operations (optional, uses resource domain if not set)

  ## Example

      update :payment_complete do
        change delegate_to_region(:payment, :complete)
      end
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, opts, context) do
    region_name = Keyword.fetch!(opts, :region)
    action_name = Keyword.fetch!(opts, :action)

    changeset
    |> Ash.Changeset.after_action(fn _changeset, parent ->
      delegate_and_check_completion(parent, region_name, action_name, opts, context)
    end)
  end

  defp delegate_and_check_completion(parent, region_name, action_name, opts, context) do
    domain = opts[:domain] || Ash.Resource.Info.domain(parent.__struct__)

    # Load the region record
    parent_with_region = Ash.load!(parent, [region_name], domain: domain)
    region_record = Map.get(parent_with_region, region_name)

    if is_nil(region_record) do
      {:error,
       Ash.Error.Invalid.exception(
         errors: [
           Ash.Error.Invalid.NoSuchResource.exception(
             resource: region_name,
             message:
               "Region #{region_name} not found for parent. Was activate_parallel_regions() called?"
           )
         ]
       )}
    else
      region_resource = region_record.__struct__

      # Call the action on the region resource
      case call_region_action(region_record, region_resource, action_name, domain) do
        {:ok, _updated_region} ->
          # Check if parallel regions have completed
          check_and_invoke_completion(parent, domain, context)

        {:error, error} ->
          {:error, error}
      end
    end
  end

  defp call_region_action(region_record, _region_resource, action_name, domain) do
    region_record
    |> Ash.Changeset.for_update(action_name)
    |> Ash.update(domain: domain)
  end

  defp check_and_invoke_completion(parent, domain, _context) do
    case AshStateMachine.check_parallel_completion(parent, domain) do
      {:ok, :complete, completion_context} ->
        # Completion criteria met - invoke the on_complete callback
        invoke_on_complete(parent, completion_context, domain)

      {:ok, :pending} ->
        # Still waiting for other regions
        {:ok, parent}

      {:error, :partial_failure} ->
        # Some regions failed with :all strategy - still return the parent
        # The on_failure callback should be handled separately
        {:ok, parent}

      {:error, _reason} ->
        # Other errors - still return the parent
        {:ok, parent}
    end
  end

  defp invoke_on_complete(parent, completion_context, domain) do
    parallel_region = completion_context.parallel_region
    on_complete_action = parallel_region.on_complete

    # Reload parent to get fresh state
    parent = Ash.reload!(parent, domain: domain)

    # Call the on_complete action with completion context as arguments
    parent
    |> Ash.Changeset.for_update(on_complete_action, %{
      exit_state: completion_context.exit_state,
      region_states: completion_context.region_states
    })
    |> Ash.update(domain: domain)
  end
end
