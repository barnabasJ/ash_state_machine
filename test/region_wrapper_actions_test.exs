# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshStateMachine.RegionWrapperActionsTest do
  use ExUnit.Case

  describe "GenerateRegionActions transformer" do
    test "generates wrapper actions for each region's update actions" do
      # Check that ParallelOrder has generated wrapper actions
      actions = Ash.Resource.Info.actions(ParallelOrder)
      action_names = Enum.map(actions, & &1.name)

      # Payment region actions (process, complete, fail)
      assert :payment_process in action_names
      assert :payment_complete in action_names
      assert :payment_fail in action_names

      # Inventory region actions (reserve, confirm, mark_unavailable)
      assert :inventory_reserve in action_names
      assert :inventory_confirm in action_names
      assert :inventory_mark_unavailable in action_names
    end

    test "generated wrapper actions are update type" do
      actions = Ash.Resource.Info.actions(ParallelOrder)

      for action_name <- [
            :payment_process,
            :payment_complete,
            :payment_fail,
            :inventory_reserve,
            :inventory_confirm,
            :inventory_mark_unavailable
          ] do
        action = Enum.find(actions, &(&1.name == action_name))
        assert action != nil, "Action #{action_name} should exist"
        assert action.type == :update, "Action #{action_name} should be an update action"
      end
    end

    test "wrapper actions have DelegateToRegion change" do
      action = Ash.Resource.Info.action(ParallelOrder, :payment_process)
      assert action != nil

      # Find the DelegateToRegion change
      delegate_change =
        Enum.find(action.changes, fn change ->
          case change.change do
            {AshStateMachine.BuiltinChanges.DelegateToRegion, _opts} -> true
            _ -> false
          end
        end)

      assert delegate_change != nil, "Expected DelegateToRegion change"

      {_module, opts} = delegate_change.change
      assert opts[:region] == :payment
      assert opts[:action] == :process
    end

    test "does not overwrite manually defined actions" do
      # ParallelOrder has a manually defined :complete action
      # The transformer should NOT generate :payment_complete_manual or similar
      # if one existed with that name
      action = Ash.Resource.Info.action(ParallelOrder, :complete)
      assert action != nil

      # The manually defined :complete should have transition_state, not delegate_to_region
      has_transition_state =
        Enum.any?(action.changes, fn change ->
          case change.change do
            {AshStateMachine.BuiltinChanges.TransitionState, _opts} -> true
            AshStateMachine.BuiltinChanges.TransitionState -> true
            _ -> false
          end
        end)

      assert has_transition_state, "Manual :complete action should have TransitionState change"
    end
  end

  describe "DelegateToRegion change" do
    test "delegates action to region and updates region state" do
      # Create and activate order
      order = ParallelOrder.create!() |> ParallelOrder.start_processing!()

      # Load initial region state
      order = Ash.load!(order, [:payment], domain: Domain)
      assert order.payment.state == :pending

      # Call the wrapper action on parent
      order =
        order
        |> Ash.Changeset.for_update(:payment_process, %{}, domain: Domain)
        |> Ash.update!()

      # Reload and verify region state changed
      order = Ash.load!(order, [:payment], domain: Domain, lazy?: false)
      assert order.payment.state == :processing
    end

    test "can progress region through multiple states via wrapper actions" do
      order = ParallelOrder.create!() |> ParallelOrder.start_processing!()

      # Process payment
      order =
        order
        |> Ash.Changeset.for_update(:payment_process, %{}, domain: Domain)
        |> Ash.update!()

      order = Ash.load!(order, [:payment], domain: Domain, lazy?: false)
      assert order.payment.state == :processing

      # Complete payment
      order =
        order
        |> Ash.Changeset.for_update(:payment_complete, %{}, domain: Domain)
        |> Ash.update!()

      order = Ash.load!(order, [:payment], domain: Domain, lazy?: false)
      assert order.payment.state == :completed
    end

    test "wrapper actions work for inventory region" do
      order = ParallelOrder.create!() |> ParallelOrder.start_processing!()

      # Reserve inventory
      order =
        order
        |> Ash.Changeset.for_update(:inventory_reserve, %{}, domain: Domain)
        |> Ash.update!()

      order = Ash.load!(order, [:inventory], domain: Domain, lazy?: false)
      assert order.inventory.state == :reserving

      # Confirm inventory
      order =
        order
        |> Ash.Changeset.for_update(:inventory_confirm, %{}, domain: Domain)
        |> Ash.update!()

      order = Ash.load!(order, [:inventory], domain: Domain, lazy?: false)
      assert order.inventory.state == :reserved
    end

    test "returns error when region not activated" do
      # Create order but don't activate regions
      order = ParallelOrder.create!()
      assert order.state == :pending

      # Try to call wrapper action - should fail
      result =
        order
        |> Ash.Changeset.for_update(:payment_process, %{}, domain: Domain)
        |> Ash.update()

      assert {:error, _} = result
    end

    test "invokes on_complete callback when all regions complete" do
      order = ParallelOrder.create!() |> ParallelOrder.start_processing!()
      assert order.state == :processing

      # Complete payment region
      order =
        order
        |> Ash.Changeset.for_update(:payment_process, %{}, domain: Domain)
        |> Ash.update!()

      order =
        order
        |> Ash.Changeset.for_update(:payment_complete, %{}, domain: Domain)
        |> Ash.update!()

      # Parent should still be processing (inventory not done)
      order = Ash.reload!(order, domain: Domain)
      assert order.state == :processing

      # Complete inventory region
      order =
        order
        |> Ash.Changeset.for_update(:inventory_reserve, %{}, domain: Domain)
        |> Ash.update!()

      order =
        order
        |> Ash.Changeset.for_update(:inventory_confirm, %{}, domain: Domain)
        |> Ash.update!()

      # Now parent should transition to completed via on_complete callback
      order = Ash.reload!(order, domain: Domain)
      assert order.state == :completed
    end

    test "does not invoke on_complete when only some regions complete" do
      order = ParallelOrder.create!() |> ParallelOrder.start_processing!()

      # Complete only payment region
      order =
        order
        |> Ash.Changeset.for_update(:payment_process, %{}, domain: Domain)
        |> Ash.update!()

      order =
        order
        |> Ash.Changeset.for_update(:payment_complete, %{}, domain: Domain)
        |> Ash.update!()

      # Parent should still be processing
      order = Ash.reload!(order, domain: Domain)
      assert order.state == :processing

      # Verify payment is complete but inventory is still pending
      order = Ash.load!(order, [:payment, :inventory], domain: Domain, lazy?: false)
      assert order.payment.state == :completed
      assert order.inventory.state == :pending
    end
  end
end
