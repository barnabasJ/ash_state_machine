# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshStateMachine.BuiltinChanges.GuardedTransition do
  @moduledoc """
  Evaluates guarded transitions and transitions to the first matching target.

  Transitions are evaluated in order. The first transition whose guard
  conditions pass (or has no guard) will be used.
  """
  use Ash.Resource.Change

  def change(changeset, opts, context) do
    transitions = opts[:transitions]
    attribute = AshStateMachine.Info.state_machine_state_attribute!(changeset.resource)
    current_state = Map.get(changeset.data, attribute)

    case find_matching_transition(changeset, transitions, current_state, context) do
      {:ok, transition} ->
        target = hd(transition.to)
        AshStateMachine.transition_state(changeset, target)

      {:error, :no_match} ->
        Ash.Changeset.add_error(
          changeset,
          AshStateMachine.Errors.NoMatchingTransition.exception(
            old_state: current_state,
            target: nil,
            action: changeset.action.name
          )
        )
    end
  end

  defp find_matching_transition(changeset, transitions, current_state, context) do
    Enum.reduce_while(transitions, {:error, :no_match}, fn transition, _acc ->
      if current_state in transition.from and guards_pass?(changeset, transition.guard, context) do
        {:halt, {:ok, transition}}
      else
        {:cont, {:error, :no_match}}
      end
    end)
  end

  defp guards_pass?(_changeset, [], _context), do: true

  defp guards_pass?(changeset, guards, context) do
    Enum.all?(guards, fn guard ->
      {module, opts} = normalize_guard(guard)
      opts = fill_template_opts(changeset, opts, context)

      case module.validate(changeset, opts, context) do
        :ok -> true
        {:ok, _} -> true
        {:error, _} -> false
      end
    end)
  end

  defp normalize_guard({module, opts}) when is_atom(module) and is_list(opts), do: {module, opts}
  defp normalize_guard(module) when is_atom(module), do: {module, []}

  defp fill_template_opts(changeset, opts, context) do
    Ash.Expr.fill_template(
      opts,
      actor: context.actor,
      tenant: changeset.tenant,
      args: changeset.arguments,
      context: changeset.context,
      changeset: changeset
    )
  end

  # Atomic support - not yet implemented for guarded transitions
  # The complexity of evaluating multiple guard conditions atomically
  # requires more work to properly integrate with Ash's atomic validation API
  def atomic(_changeset, _opts, _context) do
    :not_atomic
  end
end
