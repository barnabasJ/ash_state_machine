# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshStateMachine.BuiltinChanges.RunEntryExitChanges do
  @moduledoc """
  Executes entry/exit changes and validations based on state transitions.

  This change is automatically added to resources that have states with
  entry/exit callbacks defined.

  ## Execution Order

  1. Exit validations (can block transition)
  2. Exit changes
  3. (other action changes run here)
  4. Entry changes
  5. Entry validations (can rollback)

  ## How It Works

  This change detects when the state attribute is being modified and:
  - If exiting a state with callbacks, runs those callbacks
  - If entering a state with callbacks, schedules those to run after the action
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, context) do
    resource = changeset.resource
    state_attribute = AshStateMachine.Info.state_machine_state_attribute!(resource)

    old_state = get_old_state(changeset, state_attribute)
    new_state = Ash.Changeset.get_attribute(changeset, state_attribute)

    # Only run if state is changing
    if old_state != new_state and not is_nil(new_state) do
      changeset
      |> run_exit_callbacks(old_state, resource, context)
      |> schedule_entry_callbacks(new_state, resource, context)
    else
      changeset
    end
  end

  defp get_old_state(changeset, state_attribute) do
    case changeset.action_type do
      :create -> nil
      _ -> Map.get(changeset.data, state_attribute)
    end
  end

  # Run exit validations and changes immediately (before transition)
  defp run_exit_callbacks(changeset, nil, _resource, _context), do: changeset

  defp run_exit_callbacks(changeset, old_state, resource, context) do
    exit_validations = AshStateMachine.Info.state_exit_validations(resource, old_state)
    exit_changes = AshStateMachine.Info.state_exit_changes(resource, old_state)

    changeset
    |> run_validations(exit_validations, context)
    |> run_changes(exit_changes, context)
  end

  # Schedule entry callbacks to run after the action completes
  defp schedule_entry_callbacks(changeset, nil, _resource, _context), do: changeset

  defp schedule_entry_callbacks(changeset, new_state, resource, context) do
    entry_changes = AshStateMachine.Info.state_entry_changes(resource, new_state)
    entry_validations = AshStateMachine.Info.state_entry_validations(resource, new_state)

    if entry_changes == [] and entry_validations == [] do
      changeset
    else
      Ash.Changeset.after_action(changeset, fn _changeset, result ->
        # Run entry changes first, then validations
        case run_entry_changes(result, entry_changes, context) do
          {:ok, result} ->
            run_entry_validations(result, entry_validations, context)

          {:error, error} ->
            {:error, error}
        end
      end)
    end
  end

  # Run changes on the changeset (for exit changes)
  defp run_changes(changeset, [], _context), do: changeset

  defp run_changes(changeset, change_specs, context) do
    Enum.reduce(change_specs, changeset, fn change_spec, acc ->
      run_single_change(acc, change_spec, context)
    end)
  end

  # Run validations on the changeset (for exit validations)
  defp run_validations(changeset, [], _context), do: changeset

  defp run_validations(changeset, validation_specs, context) do
    Enum.reduce(validation_specs, changeset, fn validation_spec, acc ->
      run_single_validation(acc, validation_spec, context)
    end)
  end

  # Run entry changes after action (on the result record)
  defp run_entry_changes(result, [], _context), do: {:ok, result}

  defp run_entry_changes(result, change_specs, context) do
    # For entry changes, we create a temporary changeset, run changes, and extract attributes
    # This allows changes to modify the record after it's been saved
    changeset = Ash.Changeset.new(result)

    final_changeset =
      Enum.reduce(change_specs, changeset, fn change_spec, acc ->
        run_single_change(acc, change_spec, context)
      end)

    # If there are errors, return them
    if final_changeset.errors != [] do
      {:error, Ash.Error.to_error_class(final_changeset.errors)}
    else
      {:ok, result}
    end
  end

  # Run entry validations after action (on the result record)
  defp run_entry_validations(result, [], _context), do: {:ok, result}

  defp run_entry_validations(result, validation_specs, context) do
    changeset = Ash.Changeset.new(result)

    final_changeset =
      Enum.reduce(validation_specs, changeset, fn validation_spec, acc ->
        run_single_validation(acc, validation_spec, context)
      end)

    if final_changeset.errors != [] do
      {:error, Ash.Error.to_error_class(final_changeset.errors)}
    else
      {:ok, result}
    end
  end

  # Execute a single change specification
  defp run_single_change(changeset, change_spec, context) do
    case change_spec do
      # Module: MyApp.Changes.DoSomething
      module when is_atom(module) and not is_nil(module) ->
        module.change(changeset, [], context)

      # Module with options: {MyApp.Changes.DoSomething, opt: value}
      {module, opts} when is_atom(module) and is_list(opts) ->
        module.change(changeset, opts, context)

      other ->
        raise ArgumentError, """
        Invalid change specification: #{inspect(other)}

        Expected one of:
        - Module atom: MyApp.Changes.DoSomething
        - {Module, opts}: {MyApp.Changes.DoSomething, opt: value}
        """
    end
  end

  # Execute a single validation specification
  defp run_single_validation(changeset, validation_spec, context) do
    case validation_spec do
      # Module: MyApp.Validations.IsValid
      module when is_atom(module) and not is_nil(module) ->
        run_validation_module(changeset, module, [], context)

      # Module with options: {MyApp.Validations.IsValid, opt: value}
      {module, opts} when is_atom(module) and is_list(opts) ->
        run_validation_module(changeset, module, opts, context)

      other ->
        raise ArgumentError, """
        Invalid validation specification: #{inspect(other)}

        Expected one of:
        - Module atom: MyApp.Validations.IsValid
        - {Module, opts}: {MyApp.Validations.IsValid, opt: value}
        """
    end
  end

  defp run_validation_module(changeset, module, opts, context) do
    # Validations should implement the Ash.Resource.Validation behaviour
    case module.validate(changeset, opts, context) do
      :ok ->
        changeset

      {:ok, changeset} ->
        changeset

      {:error, error} ->
        Ash.Changeset.add_error(changeset, error)
    end
  end
end
