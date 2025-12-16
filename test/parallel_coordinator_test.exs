# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshStateMachine.ParallelCoordinatorTest do
  use ExUnit.Case

  describe "check_completion/2" do
    test "returns :no_active_region when not in a parallel region state" do
      order = ParallelOrder.create!()

      # Before activation, parent is in :pending state which has no parallel_region
      assert {:error, :no_active_region} =
               AshStateMachine.check_parallel_completion(order, Domain)
    end

    test "returns :pending when regions exist but haven't completed" do
      order = ParallelOrder.create!() |> ParallelOrder.start_processing!()
      order = Ash.load!(order, [:payment, :inventory], domain: Domain)

      # Both regions are in :pending state, not terminal
      assert {:ok, :pending} = AshStateMachine.check_parallel_completion(order, Domain)
    end

    test "returns :complete with context when all regions are in terminal success states" do
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

      assert {:ok, :complete, context} =
               AshStateMachine.check_parallel_completion(order, Domain)

      # Verify context contains expected data
      assert context.exit_state == :completed
      assert context.region_states[:payment] == :completed
      assert context.region_states[:inventory] == :reserved
      assert context.parallel_region.enter_state == :processing
    end

    test "returns :partial_failure when a region fails with :all strategy" do
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

      assert {:error, :partial_failure} =
               AshStateMachine.check_parallel_completion(order, Domain)
    end
  end

  describe "all_regions_terminal?/2" do
    test "returns false when not in a parallel region state" do
      order = ParallelOrder.create!()

      # Not in a parallel region state
      assert AshStateMachine.all_regions_terminal?(order, Domain) == false
    end

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
    test "returns false when not in a parallel region state" do
      order = ParallelOrder.create!()

      assert AshStateMachine.all_regions_succeeded?(order, Domain) == false
    end

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
    test "returns region name and record pairs when in parallel region state" do
      order = ParallelOrder.create!() |> ParallelOrder.start_processing!()

      states = AshStateMachine.get_region_states(order, Domain)

      assert length(states) == 2

      assert {:payment, %PaymentMachine{}} =
               Enum.find(states, fn {name, _} -> name == :payment end)

      assert {:inventory, %InventoryMachine{}} =
               Enum.find(states, fn {name, _} -> name == :inventory end)
    end

    test "returns empty list when not in a parallel region state" do
      order = ParallelOrder.create!()

      # Before activation, parent is not in a parallel region state
      states = AshStateMachine.get_region_states(order, Domain)

      assert states == []
    end
  end

  describe "find_active_parallel_region/1" do
    test "returns nil when not in a parallel region state" do
      order = ParallelOrder.create!()

      assert AshStateMachine.ParallelCoordinator.find_active_parallel_region(order) == nil
    end

    test "returns the parallel region when in enter_state" do
      order = ParallelOrder.create!() |> ParallelOrder.start_processing!()

      parallel_region = AshStateMachine.ParallelCoordinator.find_active_parallel_region(order)

      assert parallel_region != nil
      assert parallel_region.enter_state == :processing
      assert parallel_region.exit_state == :completed
      assert parallel_region.completion_strategy == :all
      assert length(parallel_region.regions) == 2
    end
  end
end
