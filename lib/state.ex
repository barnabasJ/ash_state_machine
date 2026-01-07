# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshStateMachine.State do
  @moduledoc """
  Represents a state definition with entry/exit callbacks.

  States can define callbacks that run when entering or exiting the state.
  These callbacks are automatically executed for ANY transition to/from that state.

  ## Fields

    * `:name` - The name of the state (atom)
    * `:on_enter` - List of changes to run when entering this state
    * `:on_enter_validate` - List of validations to run when entering this state
    * `:on_exit` - List of changes to run when exiting this state
    * `:on_exit_validate` - List of validations to run when exiting this state

  ## Example

      states do
        state :processing do
          on_enter [
            MyApp.Changes.AllocateResources,
            {MyApp.Changes.RecordTimestamp, field: :started_at}
          ]

          on_enter_validate [MyApp.Validations.HasCapacity]

          on_exit [MyApp.Changes.ReleaseResources]
        end
      end
  """

  @type change_spec :: module() | {module(), keyword()}
  @type validation_spec :: module() | {module(), keyword()}

  @type t :: %__MODULE__{
          name: atom(),
          on_enter: [change_spec()],
          on_enter_validate: [validation_spec()],
          on_exit: [change_spec()],
          on_exit_validate: [validation_spec()],
          __identifier__: any(),
          __spark_metadata__: Spark.Dsl.Entity.spark_meta()
        }

  defstruct name: nil,
            on_enter: [],
            on_enter_validate: [],
            on_exit: [],
            on_exit_validate: [],
            __identifier__: nil,
            __spark_metadata__: nil
end
