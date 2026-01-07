# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshStateMachine.EntryExitWithRegionsTest do
  use ExUnit.Case

  # Change that records execution order via messages
  defmodule RecordingChange do
    use Ash.Resource.Change

    def change(changeset, opts, _context) do
      label = opts[:label]
      send(self(), {:callback, label})
      changeset
    end
  end

  # Region machine with entry/exit callbacks
  defmodule PaymentWithCallbacks do
    use Ash.Resource,
      domain: Domain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshStateMachine]

    state_machine do
      initial_states([:pending])
      default_initial_state(:pending)
      failure_states([:failed])

      states do
        state :processing do
          on_enter([
            {AshStateMachine.EntryExitWithRegionsTest.RecordingChange,
             label: :payment_enter_processing}
          ])

          on_exit([
            {AshStateMachine.EntryExitWithRegionsTest.RecordingChange,
             label: :payment_exit_processing}
          ])
        end

        state :completed do
          on_enter([
            {AshStateMachine.EntryExitWithRegionsTest.RecordingChange,
             label: :payment_enter_completed}
          ])
        end
      end

      transitions do
        transition :process, from: :pending, to: :processing, require_atomic?: false
        transition :complete, from: :processing, to: :completed, require_atomic?: false
        transition :fail, from: [:pending, :processing], to: :failed, require_atomic?: false
      end
    end

    actions do
      default_accept(:*)
      defaults([:read, :destroy])
      # All actions auto-generated (including :create)!
    end

    ets do
      private?(true)
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:parent_id, :uuid, allow_nil?: false, public?: true)
    end
  end

  # Simple inventory region without callbacks for comparison
  defmodule InventoryWithCallbacks do
    use Ash.Resource,
      domain: Domain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshStateMachine]

    state_machine do
      initial_states([:pending])
      default_initial_state(:pending)
      failure_states([:unavailable])

      states do
        state :reserved do
          on_enter([
            {AshStateMachine.EntryExitWithRegionsTest.RecordingChange,
             label: :inventory_enter_reserved}
          ])
        end
      end

      transitions do
        transition :reserve, from: :pending, to: :reserving, require_atomic?: false
        transition :confirm, from: :reserving, to: :reserved, require_atomic?: false

        transition :mark_unavailable,
          from: [:pending, :reserving],
          to: :unavailable,
          require_atomic?: false
      end
    end

    actions do
      default_accept(:*)
      defaults([:read, :destroy])
      # All actions auto-generated (including :create)!
    end

    ets do
      private?(true)
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:parent_id, :uuid, allow_nil?: false, public?: true)
    end
  end

  # Parent order with entry/exit callbacks on activation state
  defmodule OrderWithRegionCallbacks do
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
            {AshStateMachine.EntryExitWithRegionsTest.RecordingChange,
             label: :parent_enter_processing}
          ])

          on_exit([
            {AshStateMachine.EntryExitWithRegionsTest.RecordingChange,
             label: :parent_exit_processing}
          ])
        end

        state :completed do
          on_enter([
            {AshStateMachine.EntryExitWithRegionsTest.RecordingChange,
             label: :parent_enter_completed}
          ])
        end
      end

      transitions do
        # ActivateParallelRegions auto-injected for :processing (activation state)
        transition :start_processing, from: :pending, to: :processing, require_atomic?: false
        transition :complete, from: :processing, to: :completed, require_atomic?: false

        transition :handle_regions_complete,
          from: :processing,
          to: :completed,
          require_atomic?: false

        transition :cancel, from: [:pending, :processing], to: :cancelled, require_atomic?: false
      end

      parallel_regions do
        parallel_region :processing, :completed do
          completion_strategy(:all)
          on_complete(:handle_regions_complete)

          region(:payment, AshStateMachine.EntryExitWithRegionsTest.PaymentWithCallbacks)
          region(:inventory, AshStateMachine.EntryExitWithRegionsTest.InventoryWithCallbacks)
        end
      end
    end

    actions do
      default_accept(:*)
      defaults([:read, :destroy])

      # handle_regions_complete needs arguments, so we define it manually
      update :handle_regions_complete do
        require_atomic?(false)
        argument(:exit_state, :atom)
        argument(:region_states, :map)
        # transition_state auto-injected from transition definition
      end

      # Other actions auto-generated (including :create)!
    end

    ets do
      private?(true)
    end

    attributes do
      uuid_primary_key(:id)
    end
  end

  # Helper to collect all callback messages
  defp collect_callbacks(acc \\ []) do
    receive do
      {:callback, label} -> collect_callbacks([label | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  describe "parent entry/exit callbacks with regions" do
    test "parent entry callback runs when transitioning to activation state" do
      {:ok, order} =
        OrderWithRegionCallbacks
        |> Ash.Changeset.for_create(:create, %{})
        |> Ash.create(domain: Domain)

      assert order.state == :pending

      {:ok, order} =
        order
        |> Ash.Changeset.for_update(:start_processing, %{})
        |> Ash.update(domain: Domain)

      assert order.state == :processing

      callbacks = collect_callbacks()
      assert :parent_enter_processing in callbacks
    end

    test "parent exit callback runs when leaving activation state" do
      {:ok, order} =
        OrderWithRegionCallbacks
        |> Ash.Changeset.for_create(:create, %{})
        |> Ash.create(domain: Domain)

      {:ok, order} =
        order
        |> Ash.Changeset.for_update(:start_processing, %{})
        |> Ash.update(domain: Domain)

      # Clear entry callbacks
      _callbacks = collect_callbacks()

      {:ok, order} =
        order
        |> Ash.Changeset.for_update(:complete, %{})
        |> Ash.update(domain: Domain)

      assert order.state == :completed

      callbacks = collect_callbacks()
      assert :parent_exit_processing in callbacks
      assert :parent_enter_completed in callbacks
    end
  end

  describe "region callbacks" do
    test "region entry callbacks run during region transitions" do
      {:ok, order} =
        OrderWithRegionCallbacks
        |> Ash.Changeset.for_create(:create, %{})
        |> Ash.create(domain: Domain)

      {:ok, order} =
        order
        |> Ash.Changeset.for_update(:start_processing, %{})
        |> Ash.update(domain: Domain)

      # Clear parent entry callback
      _parent_callbacks = collect_callbacks()

      # Load and transition payment region
      order = Ash.load!(order, [:payment], domain: Domain)

      {:ok, payment} =
        order.payment
        |> Ash.Changeset.for_update(:process, %{})
        |> Ash.update(domain: Domain)

      assert payment.state == :processing

      callbacks = collect_callbacks()
      assert :payment_enter_processing in callbacks
    end

    test "region exit and entry callbacks run in order during region transitions" do
      {:ok, order} =
        OrderWithRegionCallbacks
        |> Ash.Changeset.for_create(:create, %{})
        |> Ash.create(domain: Domain)

      {:ok, order} =
        order
        |> Ash.Changeset.for_update(:start_processing, %{})
        |> Ash.update(domain: Domain)

      order = Ash.load!(order, [:payment], domain: Domain)

      # Transition payment to processing
      {:ok, payment} =
        order.payment
        |> Ash.Changeset.for_update(:process, %{})
        |> Ash.update(domain: Domain)

      # Clear previous callbacks
      _callbacks = collect_callbacks()

      # Transition payment from processing to completed
      {:ok, payment} =
        payment
        |> Ash.Changeset.for_update(:complete, %{})
        |> Ash.update(domain: Domain)

      assert payment.state == :completed

      callbacks = collect_callbacks()
      # Exit from processing, then enter completed
      assert callbacks == [:payment_exit_processing, :payment_enter_completed]
    end
  end

  describe "combined parent and region callback flow" do
    test "full workflow: parent enter → region transitions → parent exit" do
      {:ok, order} =
        OrderWithRegionCallbacks
        |> Ash.Changeset.for_create(:create, %{})
        |> Ash.create(domain: Domain)

      # Start processing (activates regions, runs parent entry callback)
      {:ok, order} =
        order
        |> Ash.Changeset.for_update(:start_processing, %{})
        |> Ash.update(domain: Domain)

      # Collect parent entry callback
      callbacks_after_start = collect_callbacks()
      assert :parent_enter_processing in callbacks_after_start

      # Load and transition regions
      order = Ash.load!(order, [:payment, :inventory], domain: Domain)

      # Process and complete payment
      {:ok, payment} =
        order.payment
        |> Ash.Changeset.for_update(:process, %{})
        |> Ash.update(domain: Domain)

      {:ok, _payment} =
        payment
        |> Ash.Changeset.for_update(:complete, %{})
        |> Ash.update(domain: Domain)

      # Reserve and confirm inventory
      {:ok, inventory} =
        order.inventory
        |> Ash.Changeset.for_update(:reserve, %{})
        |> Ash.update(domain: Domain)

      {:ok, _inventory} =
        inventory
        |> Ash.Changeset.for_update(:confirm, %{})
        |> Ash.update(domain: Domain)

      # Collect all region callbacks
      region_callbacks = collect_callbacks()

      assert :payment_enter_processing in region_callbacks
      assert :payment_exit_processing in region_callbacks
      assert :payment_enter_completed in region_callbacks
      assert :inventory_enter_reserved in region_callbacks

      # Now complete the parent order
      {:ok, order} =
        order
        |> Ash.Changeset.for_update(:complete, %{})
        |> Ash.update(domain: Domain)

      assert order.state == :completed

      # Collect parent exit and entry callbacks
      parent_callbacks = collect_callbacks()
      assert :parent_exit_processing in parent_callbacks
      assert :parent_enter_completed in parent_callbacks
    end
  end
end
