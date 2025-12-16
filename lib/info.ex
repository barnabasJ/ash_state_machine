# SPDX-FileCopyrightText: 2023 ash_state_machine contributors <https://github.com/ash-project/ash_state_machine/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshStateMachine.Info do
  @moduledoc "Introspection helpers for `AshStateMachine`"
  use Spark.InfoGenerator, extension: AshStateMachine, sections: [:state_machine]

  @spec state_machine_transitions(Ash.Resource.t() | map(), name :: atom) ::
          list(AshStateMachine.Transition.t())
  def state_machine_transitions(resource_or_dsl, name) do
    resource_or_dsl
    |> state_machine_transitions()
    |> Enum.filter(&(&1.action == :* || &1.action == name))
  end

  @spec state_machine_all_states(Ash.Resource.t() | map()) :: list(atom)
  def state_machine_all_states(resource_or_dsl) do
    Spark.Dsl.Extension.get_persisted(resource_or_dsl, :all_state_machine_states, [])
  end

  @doc """
  Returns the list of parallel regions configured for the state machine.
  """
  @spec state_machine_parallel_regions(Ash.Resource.t() | map()) ::
          list(AshStateMachine.ParallelRegion.t())
  def state_machine_parallel_regions(resource_or_dsl) do
    Spark.Dsl.Extension.get_entities(resource_or_dsl, [:state_machine, :parallel_regions])
  end

  @doc """
  Returns the parallel region group for a given enter_state.

  Returns `nil` if no parallel region is configured for that state.
  """
  @spec state_machine_parallel_region_for_state(Ash.Resource.t() | map(), atom()) ::
          AshStateMachine.ParallelRegion.t() | nil
  def state_machine_parallel_region_for_state(resource_or_dsl, state) do
    resource_or_dsl
    |> state_machine_parallel_regions()
    |> Enum.find(&(&1.enter_state == state))
  end

  @doc """
  Returns the regions that should be activated for a given parent state.

  This returns the individual region entries from within the matching parallel_region group.
  """
  @spec state_machine_regions_for_state(Ash.Resource.t() | map(), atom()) ::
          list(AshStateMachine.Region.t())
  def state_machine_regions_for_state(resource_or_dsl, state) do
    case state_machine_parallel_region_for_state(resource_or_dsl, state) do
      nil -> []
      parallel_region -> parallel_region.regions || []
    end
  end

  @doc """
  Returns all unique states that trigger parallel region activation.
  """
  @spec state_machine_region_activation_states(Ash.Resource.t() | map()) :: list(atom())
  def state_machine_region_activation_states(resource_or_dsl) do
    resource_or_dsl
    |> state_machine_parallel_regions()
    |> Enum.map(& &1.enter_state)
    |> Enum.uniq()
  end
end
