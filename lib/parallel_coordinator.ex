# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshStateMachine.ParallelCoordinator do
  @moduledoc """
  Coordinates completion of parallel region resources.

  Checks if all required parallel regions have completed based on
  the parent resource's completion strategy.

  ## Completion Strategies

  - `:require_all` - All regions must reach success terminal states
  - `:allow_partial` - Proceed when all reach any terminal state
  - `{:require_n, count}` - Proceed when N regions succeed

  ## Usage

  This module is typically used automatically by the `CheckParallelCompletion`
  change, but can also be called directly:

      case AshStateMachine.ParallelCoordinator.check_completion(order, domain) do
        {:ok, :complete} -> # Ready to transition parent
        {:ok, :pending} -> # Still waiting for regions
        {:error, :partial_failure} -> # Failed with :require_all strategy
      end
  """

  require Ash.Query

  @type strategy ::
          :require_all
          | :allow_partial
          | {:require_n, pos_integer()}

  @type completion_result ::
          {:ok, :complete}
          | {:ok, :pending}
          | {:error, :partial_failure | :insufficient_completions}

  @doc """
  Checks if parallel regions meet completion criteria.

  Each region is checked against its own `completion_strategy`:
  - `:require_all` - region must be in a success terminal state
  - `:allow_partial` - region can be in any terminal state

  Returns:
  - `{:ok, :complete}` if all regions meet their completion criteria
  - `{:ok, :pending}` if still waiting for regions
  - `{:error, :partial_failure}` if a `:require_all` region has failed
  """
  @spec check_completion(Ash.Resource.record(), Ash.Domain.t() | nil) :: completion_result()
  def check_completion(parent, domain \\ nil) do
    regions = AshStateMachine.Info.state_machine_parallel_regions(parent.__struct__)

    if Enum.empty?(regions) do
      {:ok, :complete}
    else
      region_states = fetch_region_states(parent, regions, domain)
      check_all_regions(region_states)
    end
  end

  @doc """
  Checks if all parallel regions are in terminal states.

  This is a simpler check that doesn't consider success/failure,
  just whether all regions have finished processing.
  """
  @spec all_regions_terminal?(Ash.Resource.record(), Ash.Domain.t() | nil) :: boolean()
  def all_regions_terminal?(parent, domain \\ nil) do
    regions = AshStateMachine.Info.state_machine_parallel_regions(parent.__struct__)

    if Enum.empty?(regions) do
      true
    else
      region_states = fetch_region_states(parent, regions, domain)
      Enum.all?(region_states, &terminal_state?(&1, regions))
    end
  end

  @doc """
  Checks if all parallel regions completed successfully.

  Returns true only if all regions are in their configured success terminal states.
  """
  @spec all_regions_succeeded?(Ash.Resource.record(), Ash.Domain.t() | nil) :: boolean()
  def all_regions_succeeded?(parent, domain \\ nil) do
    regions = AshStateMachine.Info.state_machine_parallel_regions(parent.__struct__)

    if Enum.empty?(regions) do
      true
    else
      region_states = fetch_region_states(parent, regions, domain)
      Enum.all?(region_states, &terminal_success?(&1, regions))
    end
  end

  @doc """
  Returns the current state of all parallel regions for a parent.

  Returns a list of `{region_name, region_record}` tuples.
  """
  @spec get_region_states(Ash.Resource.record(), Ash.Domain.t() | nil) ::
          [{atom(), Ash.Resource.record() | nil}]
  def get_region_states(parent, domain \\ nil) do
    regions = AshStateMachine.Info.state_machine_parallel_regions(parent.__struct__)

    Enum.map(regions, fn region ->
      record = load_region(parent, region, domain)
      {region.name, record}
    end)
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

  # Check all regions against their individual completion strategies
  defp check_all_regions(region_states) do
    results = Enum.map(region_states, &check_region_completion/1)

    cond do
      # If any required region has failed, return error
      Enum.any?(results, &match?({:error, _}, &1)) ->
        {:error, :partial_failure}

      # If all regions are complete, return complete
      Enum.all?(results, &match?({:ok, :complete}, &1)) ->
        {:ok, :complete}

      # Otherwise still pending
      true ->
        {:ok, :pending}
    end
  end

  # Check a single region against its completion strategy
  defp check_region_completion({_region, nil}) do
    # Region not yet created - pending
    {:ok, :pending}
  end

  defp check_region_completion({region, record}) do
    strategy = region.completion_strategy || :require_all

    case strategy do
      :require_all ->
        cond do
          terminal_success_for_region?(record, region) -> {:ok, :complete}
          terminal_failure_for_region?(record, region) -> {:error, :partial_failure}
          true -> {:ok, :pending}
        end

      :allow_partial ->
        if terminal_state_for_region?(record, region) do
          {:ok, :complete}
        else
          {:ok, :pending}
        end
    end
  end

  # These functions work with {region, record} tuples from fetch_region_states
  defp terminal_success?({_region, nil}, _regions), do: false

  defp terminal_success?({region, record}, _regions) do
    terminal_success_for_region?(record, region)
  end

  defp terminal_state?({_region, nil}, _regions), do: false

  defp terminal_state?({region, record}, _regions) do
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
    # Failure states are identified by naming convention: :failed, :error, :cancelled, :unavailable
    terminal = get_all_terminal_states(resource)
    failure = get_failure_terminal_states(resource)
    terminal -- failure
  end

  defp get_failure_terminal_states(_resource) do
    # Use naming convention to identify failure states
    # Future: Add DSL for terminal_failure_states configuration
    [:failed, :error, :cancelled, :unavailable, :rejected, :aborted, :timeout]
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
