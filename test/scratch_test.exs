# test/scratch_test.exs - Scratch file for quick tests
defmodule ScratchTest do
  use ExUnit.Case

  test "test subscription suspend with map" do
    {:ok, sub} = Subscription.create(%{plan_name: "Basic"})
    {:ok, sub} = Subscription.activate(sub)
    IO.inspect(sub.state, label: "State before suspend")

    # Try calling with the reason as a map
    {:ok, sub} = Subscription.suspend(sub, %{suspended_reason: "Test"})
    IO.inspect(sub.state, label: "State after suspend")
    IO.inspect(sub.suspended_reason, label: "Suspended reason")
  end

  test "test ecommerce ship with map" do
    {:ok, order} = EcommerceOrder.create(%{customer_email: "test@example.com"})
    {:ok, order} = EcommerceOrder.checkout(order)
    {:ok, order} = EcommerceOrder.confirm(order)

    {:ok, order} = EcommerceOrder.ship(order, %{tracking_number: "TRACK123"})
    IO.inspect(order.state, label: "State after ship")
    IO.inspect(order.tracking_number, label: "Tracking number")
  end
end
