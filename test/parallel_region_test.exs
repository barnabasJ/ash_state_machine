# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshStateMachine.ParallelRegionTest do
  use ExUnit.Case

  describe "ParallelRegion struct" do
    test "has required fields" do
      region = %AshStateMachine.ParallelRegion{
        name: :payment,
        resource: PaymentMachine
      }

      assert region.name == :payment
      assert region.resource == PaymentMachine
    end

    test "has optional activate_on field" do
      region = %AshStateMachine.ParallelRegion{
        name: :inventory,
        resource: InventoryMachine,
        activate_on: :processing
      }

      assert region.activate_on == :processing
    end

    test "has all expected struct keys" do
      region = %AshStateMachine.ParallelRegion{}

      assert Map.has_key?(region, :name)
      assert Map.has_key?(region, :resource)
      assert Map.has_key?(region, :activate_on)
      assert Map.has_key?(region, :__identifier__)
      assert Map.has_key?(region, :__spark_metadata__)
    end
  end
end
