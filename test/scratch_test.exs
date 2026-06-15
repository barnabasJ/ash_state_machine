# test/scratch_test.exs - Scratch file for quick tests
defmodule ScratchTest do
  use ExUnit.Case

  test "test subscription suspend with map" do
    {:ok, sub} = Subscription.create(%{plan_name: "Basic"})
    {:ok, sub} = Subscription.activate(sub)
    assert sub.state == :active

    # Try calling with the reason as a map
    {:ok, sub} = Subscription.suspend(sub, %{suspended_reason: "Test"})
    assert sub.state == :suspended
    assert sub.suspended_reason == "Test"
  end

  test "test ecommerce ship with map" do
    {:ok, order} = EcommerceOrder.create(%{customer_email: "test@example.com"})
    {:ok, order} = EcommerceOrder.checkout(order)
    {:ok, order} = EcommerceOrder.confirm(order)

    {:ok, order} = EcommerceOrder.ship(order, %{tracking_number: "TRACK123"})
    assert order.state == :shipped
    assert order.tracking_number == "TRACK123"
  end
end
