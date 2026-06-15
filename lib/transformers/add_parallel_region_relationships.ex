# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshStateMachine.Transformers.AddParallelRegionRelationships do
  @moduledoc """
  Adds has_one relationships for parallel regions.

  For each region defined within `parallel_region` groups, this transformer adds a
  `has_one` relationship from the parent resource to the region's resource.

  ## Example

  Given a state machine with:

      parallel_regions do
        parallel_region :processing, :completed do
          region :payment, PaymentMachine
          region :inventory, InventoryMachine
        end
      end

  This transformer will add:

      relationships do
        has_one :payment, PaymentMachine, destination_attribute: :parent_id
        has_one :inventory, InventoryMachine, destination_attribute: :parent_id
      end

  The region resources should have a unique index on `parent_id` to prevent
  duplicate region creation.
  """
  use Spark.Dsl.Transformer
  alias Spark.Dsl.Transformer

  # Run before SetRelationshipSource so our relationships get their source set
  def before?(Ash.Resource.Transformers.SetRelationshipSource), do: true
  def before?(Ash.Resource.Transformers.DefaultAccept), do: true
  def before?(_), do: false

  def after?(AshStateMachine.Transformers.FillInTransitionDefaults), do: true
  def after?(_), do: false

  def transform(dsl_state) do
    parallel_regions = AshStateMachine.Info.state_machine_parallel_regions(dsl_state)

    if Enum.empty?(parallel_regions) do
      {:ok, dsl_state}
    else
      module = Transformer.get_persisted(dsl_state, :module)

      # Add relationships for each region within each parallel_region group
      Enum.reduce_while(parallel_regions, {:ok, dsl_state}, fn parallel_region,
                                                               {:ok, dsl_state} ->
        add_relationships_for_group(dsl_state, parallel_region, module)
      end)
    end
  end

  defp add_relationships_for_group(dsl_state, parallel_region, _module) do
    regions = parallel_region.regions || []

    result =
      Enum.reduce_while(regions, {:ok, dsl_state}, fn region, {:ok, dsl_state} ->
        case add_region_relationship(dsl_state, region) do
          {:ok, dsl_state} -> {:cont, {:ok, dsl_state}}
          {:error, error} -> {:halt, {:error, error}}
        end
      end)

    case result do
      {:ok, dsl_state} -> {:cont, {:ok, dsl_state}}
      {:error, error} -> {:halt, {:error, error}}
    end
  end

  defp add_region_relationship(dsl_state, region) do
    if AshStateMachine.Region.dynamic?(region) do
      validate_dynamic_relationship(dsl_state, region)
    else
      # Static regions keep the original singleton has_one semantics.
      Ash.Resource.Builder.add_new_relationship(
        dsl_state,
        :has_one,
        region.name,
        region.resource,
        destination_attribute: :parent_id
      )
    end
  end

  defp validate_dynamic_relationship(dsl_state, region) do
    relationship_name = AshStateMachine.Region.relationship_name(region)

    case Ash.Resource.Info.relationship(dsl_state, relationship_name) do
      %{type: :has_many} ->
        {:ok, dsl_state}

      %{type: type} ->
        {:error,
         Spark.Error.DslError.exception(
           module: Transformer.get_persisted(dsl_state, :module),
           path: [:state_machine, :parallel_regions, :region, region.name],
           message:
             "Dynamic region `:#{region.name}` must reference a has_many relationship, got `#{inspect(type)}`."
         )}

      nil ->
        {:error,
         Spark.Error.DslError.exception(
           module: Transformer.get_persisted(dsl_state, :module),
           path: [:state_machine, :parallel_regions, :region, region.name],
           message:
             "Dynamic region `:#{region.name}` references missing relationship `:#{relationship_name}`."
         )}
    end
  end
end
