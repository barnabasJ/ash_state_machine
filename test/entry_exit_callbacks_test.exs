# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshStateMachine.EntryExitCallbacksTest do
  use ExUnit.Case

  # Test change module that records when it runs
  defmodule RecordingChange do
    use Ash.Resource.Change

    def change(changeset, opts, _context) do
      field = opts[:field]
      send(self(), {:change_run, field})

      Ash.Changeset.force_change_attribute(changeset, field, DateTime.utc_now())
    end
  end

  # Test validation module
  defmodule AlwaysValidValidation do
    use Ash.Resource.Validation

    def validate(_changeset, _opts, _context), do: :ok
  end

  defmodule AlwaysInvalidValidation do
    use Ash.Resource.Validation

    def validate(_changeset, opts, _context) do
      {:error,
       Ash.Error.Changes.InvalidAttribute.exception(
         field: opts[:field] || :state,
         message: opts[:message] || "validation failed"
       )}
    end
  end

  # Test resource with entry/exit callbacks
  defmodule OrderWithCallbacks do
    use Ash.Resource,
      domain: Domain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshStateMachine]

    state_machine do
      initial_states([:pending])
      default_initial_state(:pending)

      states do
        state :processing do
          on_enter([
            {AshStateMachine.EntryExitCallbacksTest.RecordingChange,
             field: :processing_started_at}
          ])

          on_exit([
            {AshStateMachine.EntryExitCallbacksTest.RecordingChange, field: :processing_ended_at}
          ])
        end

        state :completed do
          on_enter([
            {AshStateMachine.EntryExitCallbacksTest.RecordingChange, field: :completed_at}
          ])
        end
      end

      transitions do
        transition(:start, from: :pending, to: :processing)
        transition(:complete, from: :processing, to: :completed)
        transition(:cancel, from: [:pending, :processing], to: :cancelled)
      end
    end

    actions do
      default_accept(:*)
      defaults([:read, :destroy])

      create :create do
        primary?(true)
      end

      update :start do
        require_atomic?(false)
        change(transition_state(:processing))
      end

      update :complete do
        require_atomic?(false)
        change(transition_state(:completed))
      end

      update :cancel do
        require_atomic?(false)
        change(transition_state(:cancelled))
      end
    end

    ets do
      private?(true)
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:processing_started_at, :utc_datetime_usec, public?: true)
      attribute(:processing_ended_at, :utc_datetime_usec, public?: true)
      attribute(:completed_at, :utc_datetime_usec, public?: true)
    end
  end

  describe "entry callbacks" do
    test "runs on_enter changes when transitioning to a state" do
      {:ok, order} =
        OrderWithCallbacks
        |> Ash.Changeset.for_create(:create, %{})
        |> Ash.create(domain: Domain)

      assert order.state == :pending
      assert order.processing_started_at == nil

      {:ok, order} =
        order
        |> Ash.Changeset.for_update(:start, %{})
        |> Ash.update(domain: Domain)

      assert order.state == :processing
      # Entry change should have recorded the timestamp
      assert_received {:change_run, :processing_started_at}
    end

    test "runs on_enter for target state regardless of source state" do
      {:ok, order} =
        OrderWithCallbacks
        |> Ash.Changeset.for_create(:create, %{})
        |> Ash.create(domain: Domain)

      {:ok, order} =
        order
        |> Ash.Changeset.for_update(:start, %{})
        |> Ash.update(domain: Domain)

      {:ok, order} =
        order
        |> Ash.Changeset.for_update(:complete, %{})
        |> Ash.update(domain: Domain)

      assert order.state == :completed
      assert_received {:change_run, :completed_at}
    end
  end

  describe "exit callbacks" do
    test "runs on_exit changes when leaving a state" do
      {:ok, order} =
        OrderWithCallbacks
        |> Ash.Changeset.for_create(:create, %{})
        |> Ash.create(domain: Domain)

      {:ok, order} =
        order
        |> Ash.Changeset.for_update(:start, %{})
        |> Ash.update(domain: Domain)

      assert order.state == :processing
      # Clear message queue
      assert_received {:change_run, :processing_started_at}

      {:ok, order} =
        order
        |> Ash.Changeset.for_update(:complete, %{})
        |> Ash.update(domain: Domain)

      assert order.state == :completed
      # Exit change should have run
      assert_received {:change_run, :processing_ended_at}
      # Entry change for completed should also have run
      assert_received {:change_run, :completed_at}
    end
  end

  describe "callback execution order" do
    test "exit changes run before entry changes" do
      {:ok, order} =
        OrderWithCallbacks
        |> Ash.Changeset.for_create(:create, %{})
        |> Ash.create(domain: Domain)

      {:ok, _order} =
        order
        |> Ash.Changeset.for_update(:start, %{})
        |> Ash.update(domain: Domain)

      # Clear the entry message
      assert_received {:change_run, :processing_started_at}

      {:ok, order} =
        Ash.get!(OrderWithCallbacks, order.id, domain: Domain)
        |> Ash.Changeset.for_update(:complete, %{})
        |> Ash.update(domain: Domain)

      assert order.state == :completed

      # Exit runs first, then entry
      messages = collect_messages()
      assert messages == [{:change_run, :processing_ended_at}, {:change_run, :completed_at}]
    end
  end

  describe "states without callbacks" do
    test "transitions to states without callbacks work normally" do
      {:ok, order} =
        OrderWithCallbacks
        |> Ash.Changeset.for_create(:create, %{})
        |> Ash.create(domain: Domain)

      {:ok, order} =
        order
        |> Ash.Changeset.for_update(:cancel, %{})
        |> Ash.update(domain: Domain)

      # :cancelled has no callbacks defined
      assert order.state == :cancelled
    end

    test "exiting from a state without callbacks works" do
      {:ok, order} =
        OrderWithCallbacks
        |> Ash.Changeset.for_create(:create, %{})
        |> Ash.create(domain: Domain)

      # :pending has no exit callbacks
      {:ok, order} =
        order
        |> Ash.Changeset.for_update(:start, %{})
        |> Ash.update(domain: Domain)

      assert order.state == :processing
      assert_received {:change_run, :processing_started_at}
    end
  end

  describe "DSL introspection" do
    test "can retrieve state definitions" do
      states = AshStateMachine.Info.state_machine_states(OrderWithCallbacks)
      assert length(states) == 2

      processing = Enum.find(states, &(&1.name == :processing))
      assert processing != nil
      assert length(processing.on_enter) == 1
      assert length(processing.on_exit) == 1
    end

    test "can check if resource has state callbacks" do
      assert AshStateMachine.Info.has_state_callbacks?(OrderWithCallbacks)
    end

    test "state_entry_changes returns changes for a state" do
      changes = AshStateMachine.Info.state_entry_changes(OrderWithCallbacks, :processing)
      assert length(changes) == 1
    end

    test "state_exit_changes returns changes for a state" do
      changes = AshStateMachine.Info.state_exit_changes(OrderWithCallbacks, :processing)
      assert length(changes) == 1
    end

    test "returns empty list for states without callbacks" do
      assert AshStateMachine.Info.state_entry_changes(OrderWithCallbacks, :pending) == []
      assert AshStateMachine.Info.state_exit_changes(OrderWithCallbacks, :pending) == []
    end
  end

  # Helper to collect all messages in order
  defp collect_messages(acc \\ []) do
    receive do
      msg -> collect_messages([msg | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end
