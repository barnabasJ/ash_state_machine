# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshStateMachine.Verifiers.VerifyParallelRegions do
  @moduledoc """
  Verifies that parallel regions are properly configured.

  This verifier checks that:
  1. Each parallel_region has a unique enter_state
  2. enter_state and exit_state exist in the state machine's states
  3. Each region resource uses the AshStateMachine extension
  4. Region resources are valid Ash resources
  """
  use Spark.Dsl.Verifier

  def verify(dsl_state) do
    parallel_regions = AshStateMachine.Info.state_machine_parallel_regions(dsl_state)

    if Enum.empty?(parallel_regions) do
      :ok
    else
      module = Spark.Dsl.Verifier.get_persisted(dsl_state, :module)
      all_states = AshStateMachine.Info.state_machine_all_states(dsl_state)

      # Verify unique enter_states
      verify_unique_enter_states!(parallel_regions, module)

      # Verify each parallel region
      Enum.each(parallel_regions, fn parallel_region ->
        verify_parallel_region(dsl_state, parallel_region, all_states, module)
      end)

      :ok
    end
  end

  defp verify_unique_enter_states!(parallel_regions, module) do
    enter_states = Enum.map(parallel_regions, & &1.enter_state)
    duplicates = enter_states -- Enum.uniq(enter_states)

    unless Enum.empty?(duplicates) do
      raise Spark.Error.DslError,
        module: module,
        path: [:state_machine, :parallel_regions],
        message: """
        Duplicate enter_state(s) found: #{inspect(Enum.uniq(duplicates))}

        Each parallel_region must have a unique enter_state. Only one parallel_region
        can be activated per parent state.
        """
    end
  end

  defp verify_parallel_region(dsl_state, parallel_region, all_states, module) do
    # Verify enter_state exists
    unless parallel_region.enter_state in all_states do
      raise Spark.Error.DslError,
        module: module,
        path: [:state_machine, :parallel_regions, :parallel_region, parallel_region.enter_state],
        message: """
        enter_state `:#{parallel_region.enter_state}` is not a valid state.

        Valid states: #{inspect(all_states)}
        """
    end

    # Verify exit_state exists
    unless parallel_region.exit_state in all_states do
      raise Spark.Error.DslError,
        module: module,
        path: [:state_machine, :parallel_regions, :parallel_region, parallel_region.enter_state],
        message: """
        exit_state `:#{parallel_region.exit_state}` is not a valid state.

        Valid states: #{inspect(all_states)}
        """
    end

    # Verify each region in the group
    regions = parallel_region.regions || []

    Enum.each(regions, fn region ->
      verify_region(dsl_state, region, parallel_region.enter_state, module)
    end)
  end

  defp verify_region(dsl_state, region, enter_state, module) do
    resource = resolve_region_resource!(dsl_state, region, enter_state, module)

    # Check if the resource module is loaded and is an Ash resource
    unless Code.ensure_loaded?(resource) do
      raise Spark.Error.DslError,
        module: module,
        path: [
          :state_machine,
          :parallel_regions,
          :parallel_region,
          enter_state,
          :region,
          region.name
        ],
        message: """
        Region `:#{region.name}` references resource `#{inspect(resource)}` which could not be loaded.
        Ensure the module exists and is compiled.
        """
    end

    # Check if the resource uses AshStateMachine
    unless uses_ash_state_machine?(resource) do
      raise Spark.Error.DslError,
        module: module,
        path: [
          :state_machine,
          :parallel_regions,
          :parallel_region,
          enter_state,
          :region,
          region.name
        ],
        message: """
        Region `:#{region.name}` references resource `#{inspect(resource)}` which must use AshStateMachine.

        Add the AshStateMachine extension to the resource:

            use Ash.Resource,
              extensions: [AshStateMachine]

            state_machine do
              initial_states [:pending]
              # ...
            end
        """
    end
  end

  defp resolve_region_resource!(dsl_state, region, enter_state, module) do
    if AshStateMachine.Region.dynamic?(region) do
      relationship_name = AshStateMachine.Region.relationship_name(region)

      case Ash.Resource.Info.relationship(dsl_state, relationship_name) do
        %{type: :has_many, destination: destination} ->
          destination

        %{type: type} ->
          raise Spark.Error.DslError,
            module: module,
            path: region_path(enter_state, region),
            message:
              "Dynamic region `:#{region.name}` must reference a has_many relationship, got `#{inspect(type)}`."

        nil ->
          raise Spark.Error.DslError,
            module: module,
            path: region_path(enter_state, region),
            message:
              "Dynamic region `:#{region.name}` references missing relationship `:#{relationship_name}`."
      end
    else
      region.resource
    end
  end

  defp region_path(enter_state, region) do
    [
      :state_machine,
      :parallel_regions,
      :parallel_region,
      enter_state,
      :region,
      region.name
    ]
  end

  defp uses_ash_state_machine?(resource) do
    # Check if the resource has the AshStateMachine extension by checking for
    # the presence of state_machine-related functions or DSL sections
    function_exported?(resource, :spark_dsl_config, 0) &&
      has_state_machine_extension?(resource)
  end

  defp has_state_machine_extension?(resource) do
    try do
      # If the resource has AshStateMachine, it will have state_machine info
      case AshStateMachine.Info.state_machine_initial_states(resource) do
        {:ok, _} -> true
        _ -> false
      end
    rescue
      _ -> false
    end
  end
end
