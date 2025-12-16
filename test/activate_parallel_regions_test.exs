# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshStateMachine.ActivateParallelRegionsTest do
  use ExUnit.Case

  describe "activate_parallel_regions change" do
    test "creates region resources when parent transitions to activation state" do
      # Create an order
      order = ParallelOrder.create!()
      assert order.state == :pending

      # Start processing - this should activate regions
      order = ParallelOrder.start_processing!(order)
      assert order.state == :processing

      # Load the relationships to verify region resources were created
      order = Ash.load!(order, [:payment, :inventory], domain: Domain)

      assert order.payment != nil, "Expected payment region to be created"
      assert order.payment.state == :pending
      assert order.payment.parent_id == order.id

      assert order.inventory != nil, "Expected inventory region to be created"
      assert order.inventory.state == :pending
      assert order.inventory.parent_id == order.id
    end

    test "region resources can transition independently" do
      # Create and activate order
      order = ParallelOrder.create!() |> ParallelOrder.start_processing!()
      order = Ash.load!(order, [:payment, :inventory], domain: Domain)

      # Process payment
      payment =
        order.payment
        |> Ash.Changeset.for_update(:process, %{}, domain: Domain)
        |> Ash.update!()

      assert payment.state == :processing

      # Complete payment
      payment =
        payment
        |> Ash.Changeset.for_update(:complete, %{}, domain: Domain)
        |> Ash.update!()

      assert payment.state == :completed

      # Reserve inventory
      inventory =
        order.inventory
        |> Ash.Changeset.for_update(:reserve, %{}, domain: Domain)
        |> Ash.update!()

      assert inventory.state == :reserving

      # Confirm inventory
      inventory =
        inventory
        |> Ash.Changeset.for_update(:confirm, %{}, domain: Domain)
        |> Ash.update!()

      assert inventory.state == :reserved
    end

    test "does not create duplicate regions on subsequent calls" do
      order = ParallelOrder.create!() |> ParallelOrder.start_processing!()

      # Load regions
      order = Ash.load!(order, [:payment, :inventory], domain: Domain)
      payment_id = order.payment.id
      inventory_id = order.inventory.id

      # Regions should exist with specific IDs
      assert payment_id != nil
      assert inventory_id != nil

      # Reload - same IDs should be present
      reloaded_order = Ash.load!(order, [:payment, :inventory], domain: Domain, lazy?: false)
      assert reloaded_order.payment.id == payment_id
      assert reloaded_order.inventory.id == inventory_id
    end
  end
end
