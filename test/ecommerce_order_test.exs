# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshStateMachine.EcommerceOrderTest do
  @moduledoc """
  Tests for the EcommerceOrder workflow demonstrating basic state machine features.

  The EcommerceOrder demonstrates:
  - Simple linear state machine workflow
  - Multiple initial states (cart vs pending)
  - Cancellation from multiple states
  - `possible_next_states` helper function
  - Invalid transition error handling

  This is a good starting point for understanding AshStateMachine basics.
  """
  use ExUnit.Case

  describe "order lifecycle - happy path" do
    test "default initial state is cart" do
      {:ok, order} = EcommerceOrder.create(%{customer_email: "buyer@example.com"})
      assert order.state == :cart
    end

    test "full workflow: cart -> pending -> confirmed -> shipped -> delivered" do
      {:ok, order} =
        EcommerceOrder.create(%{customer_email: "buyer@example.com", total_amount: 99.99})

      assert order.state == :cart

      {:ok, order} = EcommerceOrder.checkout(order)
      assert order.state == :pending

      {:ok, order} = EcommerceOrder.confirm(order)
      assert order.state == :confirmed

      {:ok, order} = EcommerceOrder.ship(order, %{tracking_number: "TRACK123"})
      assert order.state == :shipped
      assert order.tracking_number == "TRACK123"

      {:ok, order} = EcommerceOrder.deliver(order)
      assert order.state == :delivered
    end
  end

  describe "multiple initial states" do
    test "can create order starting in cart state" do
      {:ok, order} = EcommerceOrder.create(%{customer_email: "buyer@example.com"})
      assert order.state == :cart
    end

    test "can create order directly as pending (phone orders, API imports)" do
      {:ok, order} = EcommerceOrder.create_pending(%{customer_email: "phone@example.com"})
      assert order.state == :pending
    end

    test "pending orders can proceed to confirmation" do
      {:ok, order} = EcommerceOrder.create_pending(%{customer_email: "phone@example.com"})

      {:ok, order} = EcommerceOrder.confirm(order)
      assert order.state == :confirmed
    end
  end

  describe "cancellation" do
    test "can cancel from cart" do
      {:ok, order} = EcommerceOrder.create(%{customer_email: "buyer@example.com"})
      assert order.state == :cart

      {:ok, order} = EcommerceOrder.cancel(order)
      assert order.state == :cancelled
    end

    test "can cancel from pending" do
      {:ok, order} = EcommerceOrder.create(%{customer_email: "buyer@example.com"})
      {:ok, order} = EcommerceOrder.checkout(order)

      {:ok, order} = EcommerceOrder.cancel(order)
      assert order.state == :cancelled
    end

    test "can cancel from confirmed" do
      {:ok, order} = EcommerceOrder.create(%{customer_email: "buyer@example.com"})
      {:ok, order} = EcommerceOrder.checkout(order)
      {:ok, order} = EcommerceOrder.confirm(order)

      {:ok, order} = EcommerceOrder.cancel(order)
      assert order.state == :cancelled
    end

    test "cannot cancel shipped order" do
      {:ok, order} = EcommerceOrder.create(%{customer_email: "buyer@example.com"})
      {:ok, order} = EcommerceOrder.checkout(order)
      {:ok, order} = EcommerceOrder.confirm(order)
      {:ok, order} = EcommerceOrder.ship(order, %{tracking_number: "TRACK123"})

      {:error, error} = EcommerceOrder.cancel(order)
      assert Exception.message(error) =~ "cancel"
    end

    test "cannot cancel delivered order" do
      {:ok, order} = EcommerceOrder.create(%{customer_email: "buyer@example.com"})
      {:ok, order} = EcommerceOrder.checkout(order)
      {:ok, order} = EcommerceOrder.confirm(order)
      {:ok, order} = EcommerceOrder.ship(order, %{tracking_number: "TRACK123"})
      {:ok, order} = EcommerceOrder.deliver(order)

      {:error, error} = EcommerceOrder.cancel(order)
      assert Exception.message(error) =~ "cancel"
    end
  end

  describe "returns" do
    test "can return delivered order" do
      {:ok, order} = EcommerceOrder.create(%{customer_email: "buyer@example.com"})
      {:ok, order} = EcommerceOrder.checkout(order)
      {:ok, order} = EcommerceOrder.confirm(order)
      {:ok, order} = EcommerceOrder.ship(order, %{tracking_number: "TRACK123"})
      {:ok, order} = EcommerceOrder.deliver(order)

      {:ok, order} = EcommerceOrder.return(order)
      assert order.state == :returned
    end

    test "cannot return undelivered order" do
      {:ok, order} = EcommerceOrder.create(%{customer_email: "buyer@example.com"})
      {:ok, order} = EcommerceOrder.checkout(order)
      {:ok, order} = EcommerceOrder.confirm(order)
      {:ok, order} = EcommerceOrder.ship(order, %{tracking_number: "TRACK123"})

      {:error, error} = EcommerceOrder.return(order)
      assert Exception.message(error) =~ "return"
    end

    test "cannot return order in cart" do
      {:ok, order} = EcommerceOrder.create(%{customer_email: "buyer@example.com"})

      {:error, error} = EcommerceOrder.return(order)
      assert Exception.message(error) =~ "return"
    end
  end

  describe "invalid transitions" do
    test "cannot checkout already checked out order" do
      {:ok, order} = EcommerceOrder.create(%{customer_email: "buyer@example.com"})
      {:ok, order} = EcommerceOrder.checkout(order)

      {:error, error} = EcommerceOrder.checkout(order)
      assert Exception.message(error) =~ "checkout"
    end

    test "cannot confirm unprocessed order" do
      {:ok, order} = EcommerceOrder.create(%{customer_email: "buyer@example.com"})

      {:error, error} = EcommerceOrder.confirm(order)
      assert Exception.message(error) =~ "confirm"
    end

    test "cannot ship unconfirmed order" do
      {:ok, order} = EcommerceOrder.create(%{customer_email: "buyer@example.com"})
      {:ok, order} = EcommerceOrder.checkout(order)

      {:error, error} = EcommerceOrder.ship(order, %{tracking_number: "TRACK"})
      assert Exception.message(error) =~ "ship"
    end

    test "cannot deliver unshipped order" do
      {:ok, order} = EcommerceOrder.create(%{customer_email: "buyer@example.com"})
      {:ok, order} = EcommerceOrder.checkout(order)
      {:ok, order} = EcommerceOrder.confirm(order)

      {:error, error} = EcommerceOrder.deliver(order)
      assert Exception.message(error) =~ "deliver"
    end

    test "cannot go backwards in workflow" do
      {:ok, order} = EcommerceOrder.create(%{customer_email: "buyer@example.com"})
      {:ok, order} = EcommerceOrder.checkout(order)
      {:ok, order} = EcommerceOrder.confirm(order)
      {:ok, order} = EcommerceOrder.ship(order, %{tracking_number: "TRACK123"})
      {:ok, order} = EcommerceOrder.deliver(order)

      # Cannot go back to any previous state
      {:error, _} = EcommerceOrder.checkout(order)
      {:error, _} = EcommerceOrder.confirm(order)
      {:error, _} = EcommerceOrder.ship(order, %{tracking_number: "NEW"})
    end
  end

  describe "possible_next_states helper" do
    test "returns possible states from cart" do
      {:ok, order} = EcommerceOrder.create(%{customer_email: "buyer@example.com"})
      next_states = AshStateMachine.possible_next_states(order)

      assert :pending in next_states
      assert :cancelled in next_states
      refute :confirmed in next_states
      refute :delivered in next_states
    end

    test "returns possible states from pending" do
      {:ok, order} = EcommerceOrder.create(%{customer_email: "buyer@example.com"})
      {:ok, order} = EcommerceOrder.checkout(order)
      next_states = AshStateMachine.possible_next_states(order)

      assert :confirmed in next_states
      assert :cancelled in next_states
      refute :cart in next_states
      refute :shipped in next_states
    end

    test "returns possible states from confirmed" do
      {:ok, order} = EcommerceOrder.create(%{customer_email: "buyer@example.com"})
      {:ok, order} = EcommerceOrder.checkout(order)
      {:ok, order} = EcommerceOrder.confirm(order)
      next_states = AshStateMachine.possible_next_states(order)

      assert :shipped in next_states
      assert :cancelled in next_states
      refute :pending in next_states
    end

    test "returns possible states from shipped" do
      {:ok, order} = EcommerceOrder.create(%{customer_email: "buyer@example.com"})
      {:ok, order} = EcommerceOrder.checkout(order)
      {:ok, order} = EcommerceOrder.confirm(order)
      {:ok, order} = EcommerceOrder.ship(order, %{tracking_number: "TRACK123"})
      next_states = AshStateMachine.possible_next_states(order)

      assert :delivered in next_states
      # Cannot cancel or return from shipped
      refute :cancelled in next_states
      refute :returned in next_states
    end

    test "returns possible states from delivered" do
      {:ok, order} = EcommerceOrder.create(%{customer_email: "buyer@example.com"})
      {:ok, order} = EcommerceOrder.checkout(order)
      {:ok, order} = EcommerceOrder.confirm(order)
      {:ok, order} = EcommerceOrder.ship(order, %{tracking_number: "TRACK123"})
      {:ok, order} = EcommerceOrder.deliver(order)
      next_states = AshStateMachine.possible_next_states(order)

      assert :returned in next_states
      refute :cancelled in next_states
    end

    test "returns empty for terminal states" do
      {:ok, order} = EcommerceOrder.create(%{customer_email: "buyer@example.com"})
      {:ok, order} = EcommerceOrder.cancel(order)
      next_states = AshStateMachine.possible_next_states(order)

      assert next_states == []
    end

    test "returned is a terminal state" do
      {:ok, order} = EcommerceOrder.create(%{customer_email: "buyer@example.com"})
      {:ok, order} = EcommerceOrder.checkout(order)
      {:ok, order} = EcommerceOrder.confirm(order)
      {:ok, order} = EcommerceOrder.ship(order, %{tracking_number: "TRACK123"})
      {:ok, order} = EcommerceOrder.deliver(order)
      {:ok, order} = EcommerceOrder.return(order)
      next_states = AshStateMachine.possible_next_states(order)

      assert next_states == []
    end
  end

  describe "possible_next_states with action filter" do
    test "can filter by specific action" do
      {:ok, order} = EcommerceOrder.create(%{customer_email: "buyer@example.com"})

      # Only checkout leads to pending
      states_from_checkout = AshStateMachine.possible_next_states(order, :checkout)
      assert states_from_checkout == [:pending]

      # Cancel leads to cancelled
      states_from_cancel = AshStateMachine.possible_next_states(order, :cancel)
      assert states_from_cancel == [:cancelled]
    end
  end
end
