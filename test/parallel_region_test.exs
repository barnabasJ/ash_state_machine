# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshStateMachine.ParallelRegionTest do
  use ExUnit.Case

  describe "Region struct" do
    test "has required fields" do
      region = %AshStateMachine.Region{
        name: :payment,
        resource: PaymentMachine
      }

      assert region.name == :payment
      assert region.resource == PaymentMachine
    end

    test "has all expected struct keys" do
      region = %AshStateMachine.Region{}

      assert Map.has_key?(region, :name)
      assert Map.has_key?(region, :resource)
      assert Map.has_key?(region, :__identifier__)
      assert Map.has_key?(region, :__spark_metadata__)
    end
  end

  describe "ParallelRegion struct" do
    test "has required fields" do
      parallel_region = %AshStateMachine.ParallelRegion{
        enter_state: :processing,
        exit_state: :completed,
        completion_strategy: :all,
        on_complete: :handle_complete,
        regions: [
          %AshStateMachine.Region{name: :payment, resource: PaymentMachine},
          %AshStateMachine.Region{name: :inventory, resource: InventoryMachine}
        ]
      }

      assert parallel_region.enter_state == :processing
      assert parallel_region.exit_state == :completed
      assert parallel_region.completion_strategy == :all
      assert parallel_region.on_complete == :handle_complete
      assert length(parallel_region.regions) == 2
    end

    test "supports all completion strategies" do
      # :all strategy
      pr_all = %AshStateMachine.ParallelRegion{completion_strategy: :all}
      assert pr_all.completion_strategy == :all

      # :any strategy
      pr_any = %AshStateMachine.ParallelRegion{completion_strategy: :any}
      assert pr_any.completion_strategy == :any

      # {:require_n, count} strategy
      pr_require_n = %AshStateMachine.ParallelRegion{completion_strategy: {:require_n, 2}}
      assert pr_require_n.completion_strategy == {:require_n, 2}
    end

    test "has all expected struct keys" do
      parallel_region = %AshStateMachine.ParallelRegion{}

      assert Map.has_key?(parallel_region, :enter_state)
      assert Map.has_key?(parallel_region, :exit_state)
      assert Map.has_key?(parallel_region, :completion_strategy)
      assert Map.has_key?(parallel_region, :on_complete)
      assert Map.has_key?(parallel_region, :regions)
      assert Map.has_key?(parallel_region, :__identifier__)
      assert Map.has_key?(parallel_region, :__spark_metadata__)
    end
  end
end
