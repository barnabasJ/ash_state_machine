# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshStateMachine.ParallelCoordinator do
  @moduledoc """
  Coordinates completion of parallel region resources.

  Checks if all required parallel regions have completed based on
  the parallel region group's completion strategy.

  ## Completion Strategies

  - `:all` - All regions must reach success terminal states
  - `:any` - Any region reaching success is enough
  - `{:require_n, count}` - At least `count` regions must succeed

  ## Usage

  This module is typically used automatically by the `CheckParallelCompletion`
  change, but can also be called directly:

      case AshStateMachine.ParallelCoordinator.check_completion(order, domain) do
        {:ok, :complete, context} -> # Ready to invoke on_complete callback
        {:ok, :pending} -> # Still waiting for regions
        {:error, :partial_failure} -> # Failed with :all strategy
        {:error, :insufficient_completions} -> # Failed with {:require_n, count}
      end

  The `context` map contains:
  - `:parallel_region` - The parallel region group that completed
  - `:exit_state` - The configured exit state for callback reference
  - `:region_states` - Map of region name to current state
  """

  require Ash.Query

  @type strategy ::
          :all
          | :any
          | {:require_n, pos_integer()}

  @type completion_context :: %{
          parallel_region: AshStateMachine.ParallelRegion.t(),
          exit_state: atom(),
          region_states: %{atom() => atom()}
        }

  @type completion_result ::
          {:ok, :complete, completion_context()}
          | {:ok, :pending}
          | {:error, :partial_failure | :insufficient_completions | :no_active_region}

  @doc """
  Checks if parallel regions meet completion criteria.

  Finds the active parallel_region based on parent's current state and checks
  all regions against the group's `completion_strategy`:
  - `:all` - All regions must reach success terminal states
  - `:any` - Any region reaching success is enough
  - `{:require_n, count}` - At least `count` regions must succeed

  Returns:
  - `{:ok, :complete, context}` if completion criteria is met
  - `{:ok, :pending}` if still waiting for regions
  - `{:error, :partial_failure}` if a region has failed with `:all` strategy
  - `{:error, :insufficient_completions}` if `{:require_n, count}` cannot be met
  - `{:error, :no_active_region}` if parent is not in a parallel region state
  """
  @spec check_completion(Ash.Resource.record(), Ash.Domain.t() | nil) :: completion_result()
  def check_completion(parent, domain \\ nil) do
    parallel_regions = AshStateMachine.Info.state_machine_parallel_regions(parent.__struct__)
    current_state = get_state(parent)

    # Find the active parallel_region based on parent's current state
    active_region =
      Enum.find(parallel_regions, fn pr -> pr.enter_state == current_state end)

    case active_region do
      nil ->
        {:error, :no_active_region}

      parallel_region ->
        regions = parallel_region.regions || []

        if Enum.empty?(regions) do
          build_complete_result(parallel_region, %{})
        else
          region_states = fetch_region_states(parent, regions, domain)
          strategy = parallel_region.completion_strategy || :all
          check_group_completion(parallel_region, region_states, strategy)
        end
    end
  end

  @doc """
  Checks if all parallel regions in the active group are in terminal states.

  This is a simpler check that doesn't consider success/failure,
  just whether all regions have finished processing.

  Returns false if no parallel region is active for the parent's current state.
  """
  @spec all_regions_terminal?(Ash.Resource.record(), Ash.Domain.t() | nil) :: boolean()
  def all_regions_terminal?(parent, domain \\ nil) do
    case find_active_parallel_region(parent) do
      nil ->
        false

      parallel_region ->
        regions = parallel_region.regions || []

        if Enum.empty?(regions) do
          true
        else
          region_states = fetch_region_states(parent, regions, domain)
          Enum.all?(region_states, &terminal_state?/1)
        end
    end
  end

  @doc """
  Checks if all parallel regions in the active group completed successfully.

  Returns true only if all regions are in their configured success terminal states.
  Returns false if no parallel region is active for the parent's current state.
  """
  @spec all_regions_succeeded?(Ash.Resource.record(), Ash.Domain.t() | nil) :: boolean()
  def all_regions_succeeded?(parent, domain \\ nil) do
    case find_active_parallel_region(parent) do
      nil ->
        false

      parallel_region ->
        regions = parallel_region.regions || []

        if Enum.empty?(regions) do
          true
        else
          region_states = fetch_region_states(parent, regions, domain)
          Enum.all?(region_states, &terminal_success?/1)
        end
    end
  end

  @doc """
  Returns the current state of all parallel regions in the active group.

  Returns a list of `{region_name, region_record}` tuples, where
  `region_record` may be `nil` if the region hasn't been activated yet.

  Returns an empty list if no parallel region is active for the parent's current state.
  """
  @spec get_region_states(Ash.Resource.record(), Ash.Domain.t() | nil) ::
          [{atom(), Ash.Resource.record() | nil}]
  def get_region_states(parent, domain \\ nil) do
    case find_active_parallel_region(parent) do
      nil ->
        []

      parallel_region ->
        regions = parallel_region.regions || []

        Enum.map(regions, fn region ->
          record = load_region(parent, region, domain)
          {region.name, record}
        end)
    end
  end

  @doc """
  Finds the active parallel region for a parent's current state.

  Returns the parallel region group whose `enter_state` matches the parent's
  current state, or `nil` if no parallel region is active.
  """
  @spec find_active_parallel_region(Ash.Resource.record()) ::
          AshStateMachine.ParallelRegion.t() | nil
  def find_active_parallel_region(parent) do
    parallel_regions = AshStateMachine.Info.state_machine_parallel_regions(parent.__struct__)
    current_state = get_state(parent)
    Enum.find(parallel_regions, fn pr -> pr.enter_state == current_state end)
  end

  # Private functions

  defp fetch_region_states(parent, regions, domain) do
    Enum.map(regions, fn region ->
      record = load_region(parent, region, domain)
      {region, record}
    end)
  end

  defp load_region(parent, region, domain) do
    domain = domain || Ash.Resource.Info.domain(parent.__struct__)
    loaded = Ash.load!(parent, [region.name], domain: domain)
    Map.get(loaded, region.name)
  end

  # Check group completion based on strategy
  defp check_group_completion(parallel_region, region_states, :all) do
    # All regions must succeed
    statuses = Enum.map(region_states, &region_status/1)

    cond do
      # If any region has failed, the whole group fails
      Enum.any?(statuses, &(&1 == :failed)) ->
        {:error, :partial_failure}

      # If all regions succeeded, complete
      Enum.all?(statuses, &(&1 == :succeeded)) ->
        build_complete_result(parallel_region, region_states)

      # Otherwise still pending
      true ->
        {:ok, :pending}
    end
  end

  defp check_group_completion(parallel_region, region_states, :any) do
    # Any region succeeding is enough
    statuses = Enum.map(region_states, &region_status/1)

    cond do
      # If any region succeeded, complete
      Enum.any?(statuses, &(&1 == :succeeded)) ->
        build_complete_result(parallel_region, region_states)

      # If all regions have failed (terminal but not success), fail
      Enum.all?(statuses, &(&1 == :failed)) ->
        {:error, :partial_failure}

      # Otherwise still pending
      true ->
        {:ok, :pending}
    end
  end

  defp check_group_completion(parallel_region, region_states, {:require_n, count}) do
    # At least count regions must succeed
    statuses = Enum.map(region_states, &region_status/1)
    succeeded_count = Enum.count(statuses, &(&1 == :succeeded))
    failed_count = Enum.count(statuses, &(&1 == :failed))
    pending_count = Enum.count(statuses, &(&1 == :pending))
    total = length(statuses)

    cond do
      # If we have enough successes, complete
      succeeded_count >= count ->
        build_complete_result(parallel_region, region_states)

      # If it's impossible to reach count (too many failed), error
      failed_count > total - count ->
        {:error, :insufficient_completions}

      # If all regions are terminal but we don't have enough, error
      pending_count == 0 and succeeded_count < count ->
        {:error, :insufficient_completions}

      # Otherwise still pending
      true ->
        {:ok, :pending}
    end
  end

  # Determine the status of a single region
  defp region_status({_region, nil}), do: :pending

  defp region_status({region, record}) do
    cond do
      terminal_success_for_region?(record, region) -> :succeeded
      terminal_failure_for_region?(record, region) -> :failed
      true -> :pending
    end
  end

  # Build the completion result with context
  defp build_complete_result(parallel_region, region_states) do
    state_map =
      region_states
      |> Enum.map(fn
        {region, nil} -> {region.name, nil}
        {region, record} -> {region.name, get_state(record)}
      end)
      |> Map.new()

    context = %{
      parallel_region: parallel_region,
      exit_state: parallel_region.exit_state,
      region_states: state_map
    }

    {:ok, :complete, context}
  end

  # These functions work with {region, record} tuples from fetch_region_states
  defp terminal_success?({_region, nil}), do: false

  defp terminal_success?({region, record}) do
    terminal_success_for_region?(record, region)
  end

  defp terminal_state?({_region, nil}), do: false

  defp terminal_state?({region, record}) do
    terminal_state_for_region?(record, region)
  end

  # Single record/region versions
  defp terminal_success_for_region?(record, region) do
    success_states = get_success_terminal_states(region.resource)
    state = get_state(record)
    state in success_states
  end

  defp terminal_failure_for_region?(record, region) do
    state = get_state(record)
    terminal_states = get_all_terminal_states(region.resource)
    success_states = get_success_terminal_states(region.resource)

    state in terminal_states and state not in success_states
  end

  defp terminal_state_for_region?(record, region) do
    terminal_states = get_all_terminal_states(region.resource)
    state = get_state(record)
    state in terminal_states
  end

  defp get_state(record) do
    state_attribute =
      AshStateMachine.Info.state_machine_state_attribute!(record.__struct__)

    Map.get(record, state_attribute)
  end

  defp get_success_terminal_states(resource) do
    # Terminal states that are NOT failure states
    terminal = get_all_terminal_states(resource)
    failure = get_failure_terminal_states(resource)
    terminal -- failure
  end

  defp get_failure_terminal_states(resource) do
    AshStateMachine.Info.state_machine_failure_states!(resource)
  end

  defp get_all_terminal_states(resource) do
    transitions = AshStateMachine.Info.state_machine_transitions(resource)
    all_states = AshStateMachine.Info.state_machine_all_states(resource)

    # States that appear in "from" but never as targets are terminal
    # Also states that never appear in "from" but appear in "to" are terminal
    from_states =
      transitions
      |> Enum.flat_map(fn t -> List.wrap(t.from) end)
      |> Enum.reject(&(&1 == :*))
      |> MapSet.new()

    to_states =
      transitions
      |> Enum.flat_map(fn t -> List.wrap(t.to) end)
      |> Enum.reject(&(&1 == :*))
      |> MapSet.new()

    # Terminal states are states that have no outgoing transitions
    all_states
    |> Enum.filter(fn state ->
      not MapSet.member?(from_states, state) or
        (MapSet.member?(to_states, state) and not has_transition_from?(transitions, state))
    end)
  end

  defp has_transition_from?(transitions, state) do
    Enum.any?(transitions, fn t ->
      state in List.wrap(t.from) or t.from == :*
    end)
  end
end
