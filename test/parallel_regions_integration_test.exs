# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshStateMachine.ParallelRegionsIntegrationTest do
  @moduledoc """
  Integration tests demonstrating the complete parallel regions workflow
  using the new ergonomic features:

  1. Auto-generated wrapper actions on parent (no direct region calls needed)
  2. Automatic completion checking after each region action
  3. Automatic on_complete callback invocation when criteria met
  """
  use ExUnit.Case

  describe "complete order processing flow with parallel regions" do
    test "processes order through full lifecycle using only parent actions" do
      # Step 1: Create order in pending state
      order = ParallelOrder.create!()
      assert order.state == :pending

      # Step 2: Start processing - activates payment and inventory regions
      order = ParallelOrder.start_processing!(order)
      assert order.state == :processing

      # Verify regions were created in their initial states
      order = Ash.load!(order, [:payment, :inventory], domain: Domain)
      assert order.payment.state == :pending
      assert order.inventory.state == :pending

      # Step 3: Process payment using auto-generated wrapper action
      # (No direct PaymentMachine.process! call needed)
      order =
        order
        |> Ash.Changeset.for_update(:payment_process, %{}, domain: Domain)
        |> Ash.update!()

      order = Ash.load!(order, [:payment], domain: Domain, lazy?: false)
      assert order.payment.state == :processing
      # Parent unchanged
      assert order.state == :processing

      # Step 4: Complete payment using wrapper action
      order =
        order
        |> Ash.Changeset.for_update(:payment_complete, %{}, domain: Domain)
        |> Ash.update!()

      order = Ash.load!(order, [:payment], domain: Domain, lazy?: false)
      assert order.payment.state == :completed
      # Still waiting for inventory
      assert order.state == :processing

      # Step 5: Reserve inventory using wrapper action
      order =
        order
        |> Ash.Changeset.for_update(:inventory_reserve, %{}, domain: Domain)
        |> Ash.update!()

      order = Ash.load!(order, [:inventory], domain: Domain, lazy?: false)
      assert order.inventory.state == :reserving
      assert order.state == :processing

      # Step 6: Confirm inventory - this completes all regions
      order =
        order
        |> Ash.Changeset.for_update(:inventory_confirm, %{}, domain: Domain)
        |> Ash.update!()

      # The on_complete callback should have fired automatically!
      order = Ash.reload!(order, domain: Domain)
      assert order.state == :completed

      # Verify final region states
      order = Ash.load!(order, [:payment, :inventory], domain: Domain, lazy?: false)
      assert order.payment.state == :completed
      assert order.inventory.state == :reserved
    end

    test "handles payment failure gracefully" do
      order = ParallelOrder.create!() |> ParallelOrder.start_processing!()

      # Fail the payment using wrapper action
      order =
        order
        |> Ash.Changeset.for_update(:payment_fail, %{}, domain: Domain)
        |> Ash.update!()

      order = Ash.load!(order, [:payment], domain: Domain, lazy?: false)
      assert order.payment.state == :failed

      # Parent should still be processing (completion criteria not met with :all strategy)
      order = Ash.reload!(order, domain: Domain)
      assert order.state == :processing

      # Even if inventory completes, parent won't transition (payment failed)
      order =
        order
        |> Ash.Changeset.for_update(:inventory_reserve, %{}, domain: Domain)
        |> Ash.update!()

      order =
        order
        |> Ash.Changeset.for_update(:inventory_confirm, %{}, domain: Domain)
        |> Ash.update!()

      order = Ash.reload!(order, domain: Domain)
      # With :all strategy, payment failure prevents completion
      assert order.state == :processing
    end

    test "handles inventory unavailable gracefully" do
      order = ParallelOrder.create!() |> ParallelOrder.start_processing!()

      # Complete payment successfully
      order =
        order
        |> Ash.Changeset.for_update(:payment_process, %{}, domain: Domain)
        |> Ash.update!()

      order =
        order
        |> Ash.Changeset.for_update(:payment_complete, %{}, domain: Domain)
        |> Ash.update!()

      # Mark inventory unavailable
      order =
        order
        |> Ash.Changeset.for_update(:inventory_mark_unavailable, %{}, domain: Domain)
        |> Ash.update!()

      order = Ash.load!(order, [:payment, :inventory], domain: Domain, lazy?: false)
      assert order.payment.state == :completed
      assert order.inventory.state == :unavailable

      # Parent should not complete (inventory failed)
      order = Ash.reload!(order, domain: Domain)
      assert order.state == :processing
    end

    test "regions can be progressed in any order" do
      order = ParallelOrder.create!() |> ParallelOrder.start_processing!()

      # Start with inventory first
      order =
        order
        |> Ash.Changeset.for_update(:inventory_reserve, %{}, domain: Domain)
        |> Ash.update!()

      order =
        order
        |> Ash.Changeset.for_update(:inventory_confirm, %{}, domain: Domain)
        |> Ash.update!()

      order = Ash.reload!(order, domain: Domain)
      # Still waiting for payment
      assert order.state == :processing

      # Then complete payment
      order =
        order
        |> Ash.Changeset.for_update(:payment_process, %{}, domain: Domain)
        |> Ash.update!()

      order =
        order
        |> Ash.Changeset.for_update(:payment_complete, %{}, domain: Domain)
        |> Ash.update!()

      # Now both complete - parent should transition
      order = Ash.reload!(order, domain: Domain)
      assert order.state == :completed
    end

    test "interleaved region operations work correctly" do
      order = ParallelOrder.create!() |> ParallelOrder.start_processing!()

      # Interleave operations between regions
      order =
        order
        |> Ash.Changeset.for_update(:payment_process, %{}, domain: Domain)
        |> Ash.update!()

      order =
        order
        |> Ash.Changeset.for_update(:inventory_reserve, %{}, domain: Domain)
        |> Ash.update!()

      order =
        order
        |> Ash.Changeset.for_update(:payment_complete, %{}, domain: Domain)
        |> Ash.update!()

      # Verify states at this point
      order = Ash.load!(order, [:payment, :inventory], domain: Domain, lazy?: false)
      assert order.payment.state == :completed
      assert order.inventory.state == :reserving

      order = Ash.reload!(order, domain: Domain)
      assert order.state == :processing

      # Final operation completes everything
      order =
        order
        |> Ash.Changeset.for_update(:inventory_confirm, %{}, domain: Domain)
        |> Ash.update!()

      order = Ash.reload!(order, domain: Domain)
      assert order.state == :completed
    end
  end

  describe "developer experience comparison" do
    @tag :skip
    @doc """
    This test documents the improved developer experience.

    BEFORE (manual approach):
    ```elixir
    # Had to call region resources directly
    order = ParallelOrder.create!() |> ParallelOrder.start_processing!()
    order = Ash.load!(order, [:payment], domain: Domain)

    # Direct call to PaymentMachine
    payment = order.payment
    |> Ash.Changeset.for_update(:process, %{}, domain: Domain)
    |> Ash.update!()

    # Then manually check completion
    case AshStateMachine.check_parallel_completion(order, Domain) do
      {:ok, :complete} ->
        # Manually invoke completion action
        order |> Ash.Changeset.for_update(:handle_regions_complete, %{}, domain: Domain) |> Ash.update!()
      _ -> :noop
    end
    ```

    AFTER (ergonomic approach):
    ```elixir
    # Everything through parent actions
    order = ParallelOrder.create!() |> ParallelOrder.start_processing!()

    # Auto-generated wrapper action handles everything:
    # 1. Loads region
    # 2. Calls region action
    # 3. Checks completion
    # 4. Invokes on_complete if criteria met
    order
    |> Ash.Changeset.for_update(:payment_process, %{}, domain: Domain)
    |> Ash.update!()
    ```
    """
    test "documents the before/after developer experience" do
      # This test is skipped - it's documentation only
    end
  end
end
