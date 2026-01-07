# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshStateMachine.BuiltinChanges.CheckParallelCompletion do
  @moduledoc """
  A change that checks if the parent resource should transition after a region completes.

  This change is intended to be used on parallel region resources. After the region
  transitions to a terminal state, it checks if the parent's completion criteria are met
  and invokes the `on_complete` callback defined on the parallel_region group.

  ## Usage

  Add to actions that transition to terminal states:

      update :complete do
        change transition_state(:completed)
        change check_parallel_completion(
          parent_attribute: :order_id,
          parent_resource: Order
        )
      end

  The `on_complete` callback is defined on the parent's parallel_region:

      parallel_region :processing, :completed do
        completion_strategy :all
        on_complete :handle_regions_complete

        region :payment, PaymentMachine
        region :inventory, InventoryMachine
      end

  When all regions meet the completion criteria, the `:handle_regions_complete`
  action will be invoked on the parent.

  ## Accessing Completion Context

  If the callback action needs completion context (exit_state, region_states),
  it can be accessed via the changeset context:

      def change(changeset, _opts, _context) do
        case Ash.Changeset.get_context(changeset, :parallel_completion) do
          nil -> changeset
          context ->
            # context contains: %{exit_state: atom, region_states: %{atom => atom}}
            # Do something with it...
            changeset
        end
      end

  ## Options

  - `:parent_attribute` - The attribute on this resource that references the parent (required)
  - `:parent_resource` - The parent resource module (required)
  - `:on_failure` - Action to call on parent when completion fails with `:all` strategy (optional)
  """
  use Ash.Resource.Change

  @doc false
  def change(changeset, opts, context) do
    parent_attribute = Keyword.fetch!(opts, :parent_attribute)
    parent_resource = Keyword.fetch!(opts, :parent_resource)
    on_failure = Keyword.get(opts, :on_failure)

    Ash.Changeset.after_action(changeset, fn _changeset, result ->
      parent_id = Map.get(result, parent_attribute)

      if parent_id do
        check_and_invoke_callback(
          parent_id,
          parent_resource,
          on_failure,
          context
        )
      end

      {:ok, result}
    end)
  end

  defp check_and_invoke_callback(parent_id, parent_resource, on_failure, context) do
    domain = Ash.Resource.Info.domain(parent_resource)

    # Load the parent
    case load_parent(parent_resource, parent_id, domain) do
      {:ok, parent} ->
        # Check completion
        case AshStateMachine.ParallelCoordinator.check_completion(parent, domain) do
          {:ok, :complete, completion_context} ->
            invoke_on_complete(parent, completion_context, domain, context)

          {:error, _reason} when not is_nil(on_failure) ->
            invoke_callback(parent, on_failure, %{}, domain, context)

          _ ->
            :ok
        end

      {:error, _} ->
        :ok
    end
  end

  defp invoke_on_complete(parent, completion_context, domain, context) do
    parallel_region = completion_context.parallel_region
    exit_state = parallel_region.exit_state
    enter_state = parallel_region.enter_state

    cond do
      # 1. Explicit on_complete action specified
      parallel_region.on_complete ->
        invoke_callback(parent, parallel_region.on_complete, completion_context, domain, context)

      # 2. Look for existing transition from enter_state to exit_state
      transition = find_transition(parent.__struct__, enter_state, exit_state) ->
        invoke_callback(parent, transition.action, completion_context, domain, context)

      # 3. Do inline transition
      true ->
        do_inline_transition(parent, exit_state, domain, context)
    end
  end

  defp find_transition(resource, from_state, to_state) do
    resource
    |> AshStateMachine.Info.state_machine_transitions()
    |> Enum.find(fn t ->
      from_state in List.wrap(t.from) and to_state in List.wrap(t.to) and t.action != :*
    end)
  end

  defp do_inline_transition(parent, exit_state, domain, context) do
    state_attr = AshStateMachine.Info.state_machine_state_attribute!(parent.__struct__)

    parent
    |> Ash.Changeset.new()
    |> Ash.Changeset.force_change_attribute(state_attr, exit_state)
    |> Ash.update(domain: domain, tenant: context.tenant, actor: context.actor)
  end

  defp load_parent(parent_resource, parent_id, domain) do
    parent_resource
    |> Ash.Query.filter(id == ^parent_id)
    |> Ash.Query.limit(1)
    |> Ash.read_one(domain: domain)
  end

  defp invoke_callback(parent, action, completion_context, domain, context) do
    # Don't pass arguments - callback actions typically just transition state.
    # If the callback needs completion context, it can be accessed via
    # changeset context using: Ash.Changeset.get_context(changeset, :parallel_completion)
    parent
    |> Ash.Changeset.for_update(action, %{},
      domain: domain,
      tenant: context.tenant,
      actor: context.actor
    )
    |> Ash.Changeset.set_context(%{parallel_completion: completion_context})
    |> Ash.update()
  end
end
