# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshStateMachine.ParallelCoordinatorTest do
  use ExUnit.Case

  describe "check_completion/2" do
    test "returns :pending when no regions have been activated" do
      order = ParallelOrder.create!()

      # Before activation, check_completion should return :pending
      # because regions don't exist yet
      assert {:ok, :pending} = AshStateMachine.check_parallel_completion(order, Domain)
    end

    test "returns :pending when regions exist but haven't completed" do
      order = ParallelOrder.create!() |> ParallelOrder.start_processing!()
      order = Ash.load!(order, [:payment, :inventory], domain: Domain)

      # Both regions are in :pending state, not terminal
      assert {:ok, :pending} = AshStateMachine.check_parallel_completion(order, Domain)
    end

    test "returns :complete when all regions are in terminal success states" do
      order = ParallelOrder.create!() |> ParallelOrder.start_processing!()
      order = Ash.load!(order, [:payment, :inventory], domain: Domain)

      # Complete payment
      _payment =
        order.payment
        |> Ash.Changeset.for_update(:process, %{}, domain: Domain)
        |> Ash.update!()
        |> Ash.Changeset.for_update(:complete, %{}, domain: Domain)
        |> Ash.update!()

      # Complete inventory
      _inventory =
        order.inventory
        |> Ash.Changeset.for_update(:reserve, %{}, domain: Domain)
        |> Ash.update!()
        |> Ash.Changeset.for_update(:confirm, %{}, domain: Domain)
        |> Ash.update!()

      # Reload order to get fresh data
      order = Ash.get!(ParallelOrder, order.id, domain: Domain)

      assert {:ok, :complete} = AshStateMachine.check_parallel_completion(order, Domain)
    end

    test "returns :partial_failure when a region fails with require_all strategy" do
      order = ParallelOrder.create!() |> ParallelOrder.start_processing!()
      order = Ash.load!(order, [:payment, :inventory], domain: Domain)

      # Fail payment
      _payment =
        order.payment
        |> Ash.Changeset.for_update(:process, %{}, domain: Domain)
        |> Ash.update!()
        |> Ash.Changeset.for_update(:fail, %{}, domain: Domain)
        |> Ash.update!()

      # Reload order to get fresh data
      order = Ash.get!(ParallelOrder, order.id, domain: Domain)

      assert {:error, :partial_failure} = AshStateMachine.check_parallel_completion(order, Domain)
    end
  end

  describe "all_regions_terminal?/2" do
    test "returns false when regions haven't completed" do
      order = ParallelOrder.create!() |> ParallelOrder.start_processing!()

      assert AshStateMachine.all_regions_terminal?(order, Domain) == false
    end

    test "returns true when all regions are in terminal states" do
      order = ParallelOrder.create!() |> ParallelOrder.start_processing!()
      order = Ash.load!(order, [:payment, :inventory], domain: Domain)

      # Complete payment
      _payment =
        order.payment
        |> Ash.Changeset.for_update(:process, %{}, domain: Domain)
        |> Ash.update!()
        |> Ash.Changeset.for_update(:complete, %{}, domain: Domain)
        |> Ash.update!()

      # Mark inventory unavailable (terminal failure state)
      _inventory =
        order.inventory
        |> Ash.Changeset.for_update(:mark_unavailable, %{}, domain: Domain)
        |> Ash.update!()

      # Reload order to get fresh data
      order = Ash.get!(ParallelOrder, order.id, domain: Domain)

      # Both are in terminal states (one success, one failure)
      assert AshStateMachine.all_regions_terminal?(order, Domain) == true
    end
  end

  describe "all_regions_succeeded?/2" do
    test "returns false when any region has failed" do
      order = ParallelOrder.create!() |> ParallelOrder.start_processing!()
      order = Ash.load!(order, [:payment, :inventory], domain: Domain)

      # Complete payment
      _payment =
        order.payment
        |> Ash.Changeset.for_update(:process, %{}, domain: Domain)
        |> Ash.update!()
        |> Ash.Changeset.for_update(:complete, %{}, domain: Domain)
        |> Ash.update!()

      # Mark inventory unavailable (failure state)
      _inventory =
        order.inventory
        |> Ash.Changeset.for_update(:mark_unavailable, %{}, domain: Domain)
        |> Ash.update!()

      # Reload order to get fresh data
      order = Ash.get!(ParallelOrder, order.id, domain: Domain)

      assert AshStateMachine.all_regions_succeeded?(order, Domain) == false
    end

    test "returns true when all regions completed successfully" do
      order = ParallelOrder.create!() |> ParallelOrder.start_processing!()
      order = Ash.load!(order, [:payment, :inventory], domain: Domain)

      # Complete payment
      _payment =
        order.payment
        |> Ash.Changeset.for_update(:process, %{}, domain: Domain)
        |> Ash.update!()
        |> Ash.Changeset.for_update(:complete, %{}, domain: Domain)
        |> Ash.update!()

      # Complete inventory
      _inventory =
        order.inventory
        |> Ash.Changeset.for_update(:reserve, %{}, domain: Domain)
        |> Ash.update!()
        |> Ash.Changeset.for_update(:confirm, %{}, domain: Domain)
        |> Ash.update!()

      # Reload order to get fresh data
      order = Ash.get!(ParallelOrder, order.id, domain: Domain)

      assert AshStateMachine.all_regions_succeeded?(order, Domain) == true
    end
  end

  describe "get_region_states/2" do
    test "returns region name and record pairs" do
      order = ParallelOrder.create!() |> ParallelOrder.start_processing!()

      states = AshStateMachine.get_region_states(order, Domain)

      assert length(states) == 2

      assert {:payment, %PaymentMachine{}} =
               Enum.find(states, fn {name, _} -> name == :payment end)

      assert {:inventory, %InventoryMachine{}} =
               Enum.find(states, fn {name, _} -> name == :inventory end)
    end

    test "returns nil for regions not yet created" do
      order = ParallelOrder.create!()

      # Before activation, regions don't exist
      states = AshStateMachine.get_region_states(order, Domain)

      assert length(states) == 2
      assert {:payment, nil} = Enum.find(states, fn {name, _} -> name == :payment end)
      assert {:inventory, nil} = Enum.find(states, fn {name, _} -> name == :inventory end)
    end
  end
end
