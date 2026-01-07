# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshStateMachine.Transformers.InjectEntryExitChanges do
  @moduledoc """
  Injects the RunEntryExitChanges change when states have entry/exit callbacks.

  This transformer checks if any states have entry/exit callbacks defined.
  If so, it adds the `RunEntryExitChanges` change to the resource's global
  changes, which will execute the callbacks during state transitions.
  """

  use Spark.Dsl.Transformer

  # Run after states are collected
  def after?(AshStateMachine.Transformers.AddState), do: true
  def after?(_), do: false

  def transform(dsl_state) do
    if AshStateMachine.Info.has_state_callbacks?(dsl_state) do
      # Add the entry/exit change to the resource
      Ash.Resource.Builder.add_change(
        dsl_state,
        AshStateMachine.BuiltinChanges.RunEntryExitChanges
      )
    else
      {:ok, dsl_state}
    end
  end
end
