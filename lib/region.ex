# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshStateMachine.Region do
  @moduledoc """
  Represents an individual region (state machine) within a parallel region group.

  Each region references an Ash resource that implements its own state machine
  via AshStateMachine.

  ## Fields

    * `:name` - The name used for the relationship to this region's resource
    * `:resource` - The Ash resource module implementing the region's state machine
    * `:relationship` - Optional parent `has_many` relationship used for dynamic regions
    * `:needs` - Optional relationship on dynamic rows that lists prerequisite rows
  """

  @type t :: %__MODULE__{
          name: atom(),
          resource: module() | nil,
          relationship: atom() | nil,
          needs: atom() | nil,
          __identifier__: any(),
          __spark_metadata__: Spark.Dsl.Entity.spark_meta()
        }

  defstruct [
    :name,
    :resource,
    :relationship,
    :needs,
    :__identifier__,
    :__spark_metadata__
  ]

  @doc "Returns true when the region is sourced from a parent relationship."
  @spec dynamic?(region :: t()) :: boolean()
  def dynamic?(%__MODULE__{relationship: relationship})
      when is_atom(relationship) and not is_nil(relationship),
      do: true

  def dynamic?(%__MODULE__{resource: nil}), do: true
  def dynamic?(%__MODULE__{}), do: false

  @doc "Returns true when the region creates a singleton child resource."
  @spec static?(region :: t()) :: boolean()
  def static?(region), do: not dynamic?(region)

  @doc "Returns the authored relationship name for a dynamic region."
  @spec relationship_name(region :: t()) :: atom()
  def relationship_name(%__MODULE__{relationship: relationship})
      when is_atom(relationship) and not is_nil(relationship),
      do: relationship

  def relationship_name(%__MODULE__{name: name}), do: name
end
