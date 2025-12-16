# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshStateMachine.ParallelRegion do
  @moduledoc """
  Represents a parallel region configuration within a state machine.

  Parallel regions allow multiple state machines to run concurrently within
  a parent state. Each region references a separate Ash resource that uses
  AshStateMachine, enabling independent state transitions that can be
  coordinated through completion strategies.

  ## Fields

    * `:name` - The name of the parallel region (atom)
    * `:resource` - The Ash resource module that implements the region's state machine
    * `:activate_on` - The parent state that triggers activation of this region
    * `:completion_strategy` - Strategy for determining completion (`:require_all` or `:allow_partial`)
    * `:__identifier__` - Internal identifier used by Spark DSL

  ## Example

      parallel_regions do
        region :payment, PaymentMachine, activate_on: :processing, completion_strategy: :require_all
        region :inventory, InventoryMachine, activate_on: :processing, completion_strategy: :allow_partial
      end
  """

  @type t :: %__MODULE__{
          name: atom(),
          resource: module(),
          activate_on: atom(),
          completion_strategy: :require_all | :allow_partial,
          __identifier__: any(),
          __spark_metadata__: Spark.Dsl.Entity.spark_meta()
        }

  defstruct [
    :name,
    :resource,
    :activate_on,
    :completion_strategy,
    :__identifier__,
    :__spark_metadata__
  ]
end
