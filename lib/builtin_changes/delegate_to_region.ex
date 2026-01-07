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
    exit_state = parallel_region.exit_state
    enter_state = parallel_region.enter_state

    # Reload parent to get fresh state
    parent = Ash.reload!(parent, domain: domain)

    cond do
      # 1. Explicit on_complete action specified - pass completion context as arguments
      parallel_region.on_complete ->
        invoke_action_with_context(
          parent,
          parallel_region.on_complete,
          completion_context,
          domain
        )

      # 2. Look for existing transition from enter_state to exit_state - no args needed
      transition = find_transition(parent.__struct__, enter_state, exit_state) ->
        invoke_action(parent, transition.action, domain)

      # 3. Do inline transition
      true ->
        do_inline_transition(parent, exit_state, domain)
    end
  end

  # Used for explicit on_complete - user's action likely expects these arguments
  defp invoke_action_with_context(parent, action_name, completion_context, domain) do
    parent
    |> Ash.Changeset.for_update(action_name, %{
      exit_state: completion_context.exit_state,
      region_states: completion_context.region_states
    })
    |> Ash.update(domain: domain)
  end

  # Used for auto-detected transitions - no special arguments needed
  defp invoke_action(parent, action_name, domain) do
    parent
    |> Ash.Changeset.for_update(action_name, %{})
    |> Ash.update(domain: domain)
  end

  defp find_transition(resource, from_state, to_state) do
    resource
    |> AshStateMachine.Info.state_machine_transitions()
    |> Enum.find(fn t ->
      from_state in List.wrap(t.from) and to_state in List.wrap(t.to) and t.action != :*
    end)
  end

  defp do_inline_transition(parent, exit_state, domain) do
    state_attr = AshStateMachine.Info.state_machine_state_attribute!(parent.__struct__)

    parent
    |> Ash.Changeset.new()
    |> Ash.Changeset.force_change_attribute(state_attr, exit_state)
    |> Ash.update(domain: domain)
  end
end
