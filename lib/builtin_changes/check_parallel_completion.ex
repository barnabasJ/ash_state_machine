# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshStateMachine.BuiltinChanges.CheckParallelCompletion do
  @moduledoc """
  A change that checks if the parent resource should transition after a region completes.

  This change is intended to be used on parallel region resources. After the region
  transitions to a terminal state, it checks if the parent's completion criteria are met
  and optionally triggers the parent's completion action.

  ## Usage

  Add to actions that transition to terminal states:

      update :complete do
        change transition_state(:completed)
        change check_parallel_completion(
          parent_attribute: :order_id,
          parent_resource: Order,
          on_complete: :complete,
          on_failure: :fail
        )
      end

  ## Options

  - `:parent_attribute` - The attribute on this resource that references the parent (required)
  - `:parent_resource` - The parent resource module (required)
  - `:on_complete` - Action to call on parent when completion criteria are met (optional)
  - `:on_failure` - Action to call on parent when completion fails with :require_all (optional)
  """
  use Ash.Resource.Change

  @doc false
  def change(changeset, opts, context) do
    parent_attribute = Keyword.fetch!(opts, :parent_attribute)
    parent_resource = Keyword.fetch!(opts, :parent_resource)
    on_complete = Keyword.get(opts, :on_complete)
    on_failure = Keyword.get(opts, :on_failure)

    Ash.Changeset.after_action(changeset, fn _changeset, result ->
      parent_id = Map.get(result, parent_attribute)

      if parent_id do
        check_and_transition_parent(
          parent_id,
          parent_resource,
          on_complete,
          on_failure,
          context
        )
      end

      {:ok, result}
    end)
  end

  defp check_and_transition_parent(parent_id, parent_resource, on_complete, on_failure, context) do
    domain = Ash.Resource.Info.domain(parent_resource)

    # Load the parent
    case load_parent(parent_resource, parent_id, domain) do
      {:ok, parent} ->
        # Check completion
        case AshStateMachine.ParallelCoordinator.check_completion(parent, domain) do
          {:ok, :complete} when not is_nil(on_complete) ->
            transition_parent(parent, on_complete, domain, context)

          {:error, _reason} when not is_nil(on_failure) ->
            transition_parent(parent, on_failure, domain, context)

          _ ->
            :ok
        end

      {:error, _} ->
        :ok
    end
  end

  defp load_parent(parent_resource, parent_id, domain) do
    parent_resource
    |> Ash.Query.filter(id == ^parent_id)
    |> Ash.Query.limit(1)
    |> Ash.read_one(domain: domain)
  end

  defp transition_parent(parent, action, domain, context) do
    parent
    |> Ash.Changeset.for_update(action, %{},
      domain: domain,
      tenant: context.tenant,
      actor: context.actor
    )
    |> Ash.update()
  end
end
