# SPDX-FileCopyrightText: 2026 ash_state_machine contributors <https://github.com/ash-project/ash_state_machine/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshStateMachine.DynamicParallelRegionsTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  defp order_with_items(count) do
    order = DynamicParallelOrder.create!()

    items =
      for index <- 1..count do
        DynamicLineItemMachine.create!(%{parent_id: order.id, name: "item-#{index}"})
      end

    {order, items}
  end

  defp region_states(order) do
    order
    |> AshStateMachine.get_region_states(Domain)
    |> Enum.map(fn {:line_items, item} -> item.state end)
  end

  @tag story: "US-DPR-01"
  test "relationship sourced region compiles and records has_many source" do
    [region] =
      AshStateMachine.Info.state_machine_regions_for_state(DynamicParallelOrder, :all_processing)

    relationship = Ash.Resource.Info.relationship(DynamicParallelOrder, :line_items)

    assert region.name == :line_items
    assert region.relationship == :line_items
    assert region.resource == DynamicLineItemMachine
    assert relationship.type == :has_many
    assert relationship.destination == DynamicLineItemMachine
  end

  @tag story: "US-DPR-02"
  test "activation uses runtime has_many row cardinality" do
    {three_item_order, _three_items} = order_with_items(3)
    {five_item_order, _five_items} = order_with_items(5)

    three_item_order = DynamicParallelOrder.start_all!(three_item_order)
    five_item_order = DynamicParallelOrder.start_all!(five_item_order)

    assert length(AshStateMachine.get_region_states(three_item_order, Domain)) == 3
    assert length(AshStateMachine.get_region_states(five_item_order, Domain)) == 5
  end

  @tag story: "US-DPR-03"
  test "all strategy completes when every dynamic row succeeds" do
    {order, items} = order_with_items(4)
    order = DynamicParallelOrder.start_all!(order)
    Enum.each(items, &DynamicLineItemMachine.succeed!/1)

    assert {:ok, :complete, context} = AshStateMachine.check_parallel_completion(order, Domain)
    assert context.exit_state == :all_done

    assert Enum.map(context.region_states.line_items, & &1.state) == [
             :succeeded,
             :succeeded,
             :succeeded,
             :succeeded
           ]
  end

  @tag story: "US-DPR-04"
  test "all strategy fails fast when one dynamic row fails" do
    {order, [failed | _pending]} = order_with_items(4)
    order = DynamicParallelOrder.start_all!(order)
    DynamicLineItemMachine.fail!(failed)

    assert {:error, :partial_failure} = AshStateMachine.check_parallel_completion(order, Domain)
  end

  @tag story: "US-DPR-05"
  test "any strategy completes on first dynamic row success" do
    {order, [successful | _pending]} = order_with_items(3)
    order = DynamicParallelOrder.start_any!(order)
    DynamicLineItemMachine.succeed!(successful)

    assert {:ok, :complete, context} = AshStateMachine.check_parallel_completion(order, Domain)
    assert context.exit_state == :any_done
    assert Enum.count(context.region_states.line_items, &(&1.state == :succeeded)) == 1
  end

  @tag story: "US-DPR-06"
  test "require_n strategy completes from runtime success count" do
    {order, [first, second | _pending]} = order_with_items(5)
    order = DynamicParallelOrder.start_require_two!(order)
    DynamicLineItemMachine.succeed!(first)
    DynamicLineItemMachine.succeed!(second)

    assert {:ok, :complete, context} = AshStateMachine.check_parallel_completion(order, Domain)
    assert context.exit_state == :require_two_done
    assert Enum.count(context.region_states.line_items, &(&1.state == :succeeded)) == 2
  end

  @tag story: "US-DPR-07"
  test "require_n strategy returns insufficient completions when quorum is impossible" do
    {order, [first, second | _pending]} = order_with_items(4)
    order = DynamicParallelOrder.start_require_three!(order)
    DynamicLineItemMachine.fail!(first)
    DynamicLineItemMachine.fail!(second)

    assert {:error, :insufficient_completions} =
             AshStateMachine.check_parallel_completion(order, Domain)
  end

  @tag story: "US-DPR-08"
  test "static regions keep has_one relationships and singleton activation" do
    payment_relationship = Ash.Resource.Info.relationship(ParallelOrder, :payment)
    inventory_relationship = Ash.Resource.Info.relationship(ParallelOrder, :inventory)

    assert payment_relationship.type == :has_one
    assert inventory_relationship.type == :has_one

    order = ParallelOrder.create!() |> ParallelOrder.start_processing!()
    order = Ash.load!(order, [:payment, :inventory], domain: Domain, lazy?: false)

    assert %PaymentMachine{parent_id: parent_id} = order.payment
    assert parent_id == order.id
    assert %InventoryMachine{parent_id: parent_id} = order.inventory
    assert parent_id == order.id
  end

  @tag story: "US-DPR-09"
  test "verifier rejects dynamic relationship destination without AshStateMachine" do
    suffix = System.unique_integer([:positive])
    child = Module.concat([:"InvalidDynamicChild#{suffix}"])
    parent = Module.concat([:"InvalidDynamicParent#{suffix}"])

    stderr =
      capture_io(:stderr, fn ->
        Code.eval_string("""
        defmodule #{inspect(child)} do
          use Ash.Resource,
            domain: nil

          actions do
            defaults([:read, :create])
          end

          attributes do
            uuid_primary_key(:id)
            attribute(:parent_id, :uuid, public?: true)
          end
        end

        defmodule #{inspect(parent)} do
          use Ash.Resource,
            domain: nil,
            extensions: [AshStateMachine]

          state_machine do
            initial_states([:pending])
            default_initial_state(:pending)

            transitions do
              transition(:start, from: :pending, to: :processing)
              transition(:finish, from: :processing, to: :done)
            end

            parallel_regions do
              parallel_region :processing, :done do
                region(:children, relationship: :children)
              end
            end
          end

          relationships do
            has_many(:children, #{inspect(child)}, destination_attribute: :parent_id)
          end

          actions do
            defaults([:read, :create])
          end

          attributes do
            uuid_primary_key(:id)
          end
        end
        """)
      end)

    assert stderr =~ "must use AshStateMachine"
  end

  @tag story: "US-DPR-10"
  test "region states report one unique child per related row" do
    {order, items} = order_with_items(3)
    order = DynamicParallelOrder.start_all!(order)

    ids =
      order
      |> AshStateMachine.get_region_states(Domain)
      |> Enum.map(fn {:line_items, item} -> item.id end)
      |> Enum.sort()

    assert ids == items |> Enum.map(& &1.id) |> Enum.sort()
  end

  @tag story: "US-DPR-11"
  test "completion recomputes dynamic rows after terminal updates" do
    {order, [first, second, third]} = order_with_items(3)
    order = DynamicParallelOrder.start_all!(order)
    DynamicLineItemMachine.succeed!(first)

    assert {:ok, :pending} = AshStateMachine.check_parallel_completion(order, Domain)
    assert Enum.frequencies(region_states(order)) == %{pending: 2, succeeded: 1}

    DynamicLineItemMachine.succeed!(second)
    DynamicLineItemMachine.succeed!(third)

    assert {:ok, :complete, context} = AshStateMachine.check_parallel_completion(order, Domain)

    assert Enum.map(context.region_states.line_items, & &1.state) == [
             :succeeded,
             :succeeded,
             :succeeded
           ]
  end
end
