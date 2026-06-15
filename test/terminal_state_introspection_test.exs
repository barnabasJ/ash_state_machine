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
    # Given a state machine whose terminal states are :succeeded and :failed
    # When you call the success-terminal-states Info API
    # Then it returns the terminal states minus the failure states (only :succeeded)
    assert AshStateMachine.Info.state_machine_success_terminal_states(DynamicLineItemMachine) == [
             :succeeded
           ]
  end

  @tag story: "US-TSI-02"
  test "terminal states are states with no outgoing transitions" do
    # Given a state machine whose only terminal states are :failed and :succeeded
    # When you call the terminal-states Info API
    # Then it returns every terminal state regardless of success or failure
    assert DynamicLineItemMachine
           |> AshStateMachine.Info.state_machine_terminal_states()
           |> Enum.sort() == [:failed, :succeeded]
  end

  @tag story: "US-TSI-03"
  test "external readiness filters can use public success terminal states" do
    # Given line items in distinct states: one succeeded, one failed, one pending
    {order, [ready, failed, _pending]} = order_with_items()
    DynamicLineItemMachine.succeed!(ready)
    DynamicLineItemMachine.fail!(failed)

    # When a downstream consumer builds a readiness filter from the success-terminal-states
    # Info API (instead of re-deriving the states from raw transitions)
    success_states =
      AshStateMachine.Info.state_machine_success_terminal_states(DynamicLineItemMachine)

    ready_ids =
      DynamicLineItemMachine
      |> Ash.Query.filter(parent_id == ^order.id and state in ^success_states)
      |> Ash.read!(domain: Domain)
      |> Enum.map(& &1.id)

    # Then the filter matches only the succeeded item, not the failed or pending ones
    assert ready_ids == [ready.id]
  end
end
