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
    # Given a parent that declares region :line_items referencing its
    # has_many :line_items relationship (compiled without a singleton resource module)
    # When the compiled region entity and the relationship are introspected
    [region] =
      AshStateMachine.Info.state_machine_regions_for_state(DynamicParallelOrder, :all_processing)

    relationship = Ash.Resource.Info.relationship(DynamicParallelOrder, :line_items)

    # Then the region is recorded as relationship-sourced (:line_items) over the
    # has_many to the child state-machine resource — no singleton was required
    assert region.name == :line_items
    assert region.relationship == :line_items
    assert region.resource == DynamicLineItemMachine
    assert relationship.type == :has_many
    assert relationship.destination == DynamicLineItemMachine
  end

  @tag story: "US-DPR-02"
  test "activation uses runtime has_many row cardinality" do
    # Given two parents over the same dynamic region — one with three line-item
    # rows and one with five — with no DSL difference between them
    {three_item_order, _three_items} = order_with_items(3)
    {five_item_order, _five_items} = order_with_items(5)

    # When each parent transitions into the region's enter_state and activates
    three_item_order = DynamicParallelOrder.start_all!(three_item_order)
    five_item_order = DynamicParallelOrder.start_all!(five_item_order)

    # Then the tracked child count matches the runtime related-row count per parent
    assert length(AshStateMachine.get_region_states(three_item_order, Domain)) == 3
    assert length(AshStateMachine.get_region_states(five_item_order, Domain)) == 5
  end

  @tag story: "US-DPR-03"
  test "all strategy completes when every dynamic row succeeds" do
    # Given an activated parent with a four-row dynamic region under the :all strategy
    {order, items} = order_with_items(4)
    order = DynamicParallelOrder.start_all!(order)

    # When all four related rows reach a success terminal state and completion is checked
    Enum.each(items, &DynamicLineItemMachine.succeed!/1)

    # Then completion reports :complete with the configured exit_state, computed
    # over the loaded rows
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
    # Given an activated parent with a four-row dynamic region under the :all strategy
    {order, [failed | _pending]} = order_with_items(4)
    order = DynamicParallelOrder.start_all!(order)

    # When one related row fails while the others are still pending
    DynamicLineItemMachine.fail!(failed)

    # Then completion short-circuits to :partial_failure without waiting on siblings
    assert {:error, :partial_failure} = AshStateMachine.check_parallel_completion(order, Domain)
  end

  @tag story: "US-DPR-05"
  test "any strategy completes on first dynamic row success" do
    # Given an activated parent with a three-row dynamic region under the :any strategy
    {order, [successful | _pending]} = order_with_items(3)
    order = DynamicParallelOrder.start_any!(order)

    # When just one related row reaches a success state, the other two still pending
    DynamicLineItemMachine.succeed!(successful)

    # Then completion reports :complete with the exit_state on that first success
    assert {:ok, :complete, context} = AshStateMachine.check_parallel_completion(order, Domain)
    assert context.exit_state == :any_done
    assert Enum.count(context.region_states.line_items, &(&1.state == :succeeded)) == 1
  end

  @tag story: "US-DPR-06"
  test "require_n strategy completes from runtime success count" do
    # Given an activated parent with a five-row dynamic region under {:require_n, 2}
    {order, [first, second | _pending]} = order_with_items(5)
    order = DynamicParallelOrder.start_require_two!(order)

    # When two related rows reach a success state while the rest stay pending
    DynamicLineItemMachine.succeed!(first)
    DynamicLineItemMachine.succeed!(second)

    # Then completion reports :complete once succeeded_count >= 2 over the runtime rows
    assert {:ok, :complete, context} = AshStateMachine.check_parallel_completion(order, Domain)
    assert context.exit_state == :require_two_done
    assert Enum.count(context.region_states.line_items, &(&1.state == :succeeded)) == 2
  end

  @tag story: "US-DPR-07"
  test "require_n strategy returns insufficient completions when quorum is impossible" do
    # Given an activated parent with a four-row dynamic region under {:require_n, 3}
    {order, [first, second | _pending]} = order_with_items(4)
    order = DynamicParallelOrder.start_require_three!(order)

    # When two of the four related rows fail, making 3 successes unreachable
    # (failed_count > total - count)
    DynamicLineItemMachine.fail!(first)
    DynamicLineItemMachine.fail!(second)

    # Then completion reports :insufficient_completions instead of staying pending
    assert {:error, :insufficient_completions} =
             AshStateMachine.check_parallel_completion(order, Domain)
  end

  @tag story: "US-DPR-08"
  test "static regions keep has_one relationships and singleton activation" do
    # Given a parent declaring static regions :payment and :inventory (region :name, Resource)
    # When the resource's region relationships are introspected
    payment_relationship = Ash.Resource.Info.relationship(ParallelOrder, :payment)
    inventory_relationship = Ash.Resource.Info.relationship(ParallelOrder, :inventory)

    # Then AddParallelRegionRelationships still produced a has_one per region
    assert payment_relationship.type == :has_one
    assert inventory_relationship.type == :has_one

    # When the parent enters the region's enter_state and the children are loaded
    order = ParallelOrder.create!() |> ParallelOrder.start_processing!()
    order = Ash.load!(order, [:payment, :inventory], domain: Domain, lazy?: false)

    # Then exactly one child per region is created with parent_id set, unchanged
    # from the pre-dynamic behavior
    assert %PaymentMachine{parent_id: parent_id} = order.payment
    assert parent_id == order.id
    assert %InventoryMachine{parent_id: parent_id} = order.inventory
    assert parent_id == order.id
  end

  @tag story: "US-DPR-09"
  test "verifier rejects dynamic relationship destination without AshStateMachine" do
    # Given a parent declaring a has_many :children dynamic region whose
    # destination resource does NOT use the AshStateMachine extension
    suffix = System.unique_integer([:positive])
    child = Module.concat([:"InvalidDynamicChild#{suffix}"])
    parent = Module.concat([:"InvalidDynamicParent#{suffix}"])

    # When the parent resource is compiled (VerifyParallelRegions runs)
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

    # Then compilation raises a Spark.Error.DslError instructing that the
    # offending region's destination must use AshStateMachine
    assert stderr =~ "must use AshStateMachine"
  end

  @tag story: "US-DPR-10"
  test "region states report one unique child per related row" do
    # Given a parent activated into a dynamic region with three related rows
    {order, items} = order_with_items(3)
    order = DynamicParallelOrder.start_all!(order)

    # When the running parent's region states are inspected
    ids =
      order
      |> AshStateMachine.get_region_states(Domain)
      |> Enum.map(fn {:line_items, item} -> item.id end)
      |> Enum.sort()

    # Then there is exactly one child per related row — a one-to-one mapping with
    # no duplicates or orphans
    assert ids == items |> Enum.map(& &1.id) |> Enum.sort()
  end

  @tag story: "US-DPR-11"
  test "completion recomputes dynamic rows after terminal updates" do
    # Given a parent activated into a three-row dynamic region under the :all strategy
    {order, [first, second, third]} = order_with_items(3)
    order = DynamicParallelOrder.start_all!(order)

    # When only the first child has succeeded and completion is checked
    DynamicLineItemMachine.succeed!(first)

    # Then it returns :pending, reflecting the current per-row statuses
    assert {:ok, :pending} = AshStateMachine.check_parallel_completion(order, Domain)
    assert Enum.frequencies(region_states(order)) == %{pending: 2, succeeded: 1}

    # When the remaining two children later succeed
    DynamicLineItemMachine.succeed!(second)
    DynamicLineItemMachine.succeed!(third)

    # Then a fresh check reloads the rows and now returns :complete — each call
    # recomputes from current data rather than caching the earlier pass
    assert {:ok, :complete, context} = AshStateMachine.check_parallel_completion(order, Domain)

    assert Enum.map(context.region_states.line_items, & &1.state) == [
             :succeeded,
             :succeeded,
             :succeeded
           ]
  end
end
