# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshStateMachine.Verifiers.VerifyParallelRegions do
  @moduledoc """
  Verifies that parallel region resources are properly configured.

  This verifier checks that:
  1. Each region resource uses the AshStateMachine extension
  2. Region resources are valid Ash resources
  """
  use Spark.Dsl.Verifier

  def verify(dsl_state) do
    regions = AshStateMachine.Info.state_machine_parallel_regions(dsl_state)

    Enum.each(regions, fn region ->
      verify_region(dsl_state, region)
    end)

    :ok
  end

  defp verify_region(dsl_state, region) do
    resource = region.resource

    # Check if the resource module is loaded and is an Ash resource
    unless Code.ensure_loaded?(resource) do
      raise Spark.Error.DslError,
        module: Spark.Dsl.Verifier.get_persisted(dsl_state, :module),
        path: [:state_machine, :parallel_regions, :region, region.name],
        message: """
        Parallel region `:#{region.name}` references resource `#{inspect(resource)}` which could not be loaded.
        Ensure the module exists and is compiled.
        """
    end

    # Check if the resource uses AshStateMachine
    unless uses_ash_state_machine?(resource) do
      raise Spark.Error.DslError,
        module: Spark.Dsl.Verifier.get_persisted(dsl_state, :module),
        path: [:state_machine, :parallel_regions, :region, region.name],
        message: """
        Parallel region `:#{region.name}` references resource `#{inspect(resource)}` which must use AshStateMachine.

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
