# SPDX-FileCopyrightText: 2026 ash_state_machine contributors <https://github.com/ash-project/ash_state_machine/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshStateMachine.TerminalStateIntrospectionTest do
  use ExUnit.Case

  require Ash.Query

  defp order_with_items do
    order = DynamicParallelOrder.create!()

    items =
      for name <- ["ready", "failed", "pending"] do
        DynamicLineItemMachine.create!(%{parent_id: order.id, name: name})
      end

    {order, items}
  end

  @tag story: "US-TSI-01"
  test "success terminal states are terminal states minus failure states" do
    assert AshStateMachine.Info.state_machine_success_terminal_states(DynamicLineItemMachine) == [
             :succeeded
           ]
  end

  @tag story: "US-TSI-02"
  test "terminal states are states with no outgoing transitions" do
    assert DynamicLineItemMachine
           |> AshStateMachine.Info.state_machine_terminal_states()
           |> Enum.sort() == [:failed, :succeeded]
  end

  @tag story: "US-TSI-03"
  test "external readiness filters can use public success terminal states" do
    {order, [ready, failed, _pending]} = order_with_items()
    DynamicLineItemMachine.succeed!(ready)
    DynamicLineItemMachine.fail!(failed)

    success_states =
      AshStateMachine.Info.state_machine_success_terminal_states(DynamicLineItemMachine)

    ready_ids =
      DynamicLineItemMachine
      |> Ash.Query.filter(parent_id == ^order.id and state in ^success_states)
      |> Ash.read!(domain: Domain)
      |> Enum.map(& &1.id)

    assert ready_ids == [ready.id]
  end
end
