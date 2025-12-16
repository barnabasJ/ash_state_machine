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
  """

  @type t :: %__MODULE__{
          name: atom(),
          resource: module(),
          __identifier__: any(),
          __spark_metadata__: Spark.Dsl.Entity.spark_meta()
        }

  defstruct [
    :name,
    :resource,
    :__identifier__,
    :__spark_metadata__
  ]
end
