# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshStateMachine.ParallelRegion do
  @moduledoc """
  Represents a parallel region group within a state machine.

  A parallel region groups multiple state machines (regions) that run concurrently
  when the parent enters a specific state. Each region is an Ash resource that uses
  AshStateMachine.

  ## Fields

    * `:enter_state` - The parent state that activates this parallel region (also the identifier)
    * `:exit_state` - The valid exit state when region completes (passed to callback)
    * `:completion_strategy` - Strategy for determining completion (`:all`, `:any`, or `{:require_n, count}`)
    * `:on_complete` - Callback action invoked when completion strategy is satisfied
    * `:regions` - List of `AshStateMachine.Region` structs

  ## Completion Strategies

    * `:all` - All regions must reach success terminal states
    * `:any` - Any region reaching success is enough
    * `{:require_n, count}` - At least `count` regions must succeed

  ## Example

      parallel_regions do
        parallel_region :processing, :completed do
          completion_strategy :all
          on_complete :handle_regions_complete

          region :payment, PaymentMachine
          region :inventory, InventoryMachine
        end
      end
  """

  @type completion_strategy :: :all | :any | {:require_n, pos_integer()}

  @type t :: %__MODULE__{
          enter_state: atom(),
          exit_state: atom(),
          completion_strategy: completion_strategy(),
          on_complete: atom(),
          regions: [AshStateMachine.Region.t()],
          __identifier__: any(),
          __spark_metadata__: Spark.Dsl.Entity.spark_meta()
        }

  defstruct [
    :enter_state,
    :exit_state,
    :completion_strategy,
    :on_complete,
    :regions,
    :__identifier__,
    :__spark_metadata__
  ]
end
