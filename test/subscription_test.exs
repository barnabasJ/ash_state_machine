# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshStateMachine.SubscriptionTest do
  @moduledoc """
  Tests for the Subscription workflow demonstrating wildcards and auto-generated actions.

  The Subscription demonstrates:
  - Wildcard transitions (`:*` means "from any state")
  - Auto-generated update actions from transitions
  - Multiple initial states
  - Suspension and reactivation flows

  Key insight: The `:cancel` transition uses `from: :*` which means
  it can be triggered from any state - trial, active, premium, suspended, etc.
  """
  use ExUnit.Case

  describe "subscription lifecycle" do
    test "default initial state is trial" do
      {:ok, sub} = Subscription.create(%{plan_name: "Starter", user_email: "user@example.com"})
      assert sub.state == :trial
    end

    test "trial -> activate -> active" do
      {:ok, sub} = Subscription.create(%{plan_name: "Basic"})
      assert sub.state == :trial

      {:ok, sub} = Subscription.activate(sub)
      assert sub.state == :active
    end

    test "active -> upgrade -> premium" do
      {:ok, sub} = Subscription.create(%{plan_name: "Basic"})
      {:ok, sub} = Subscription.activate(sub)

      {:ok, sub} = Subscription.upgrade(sub)
      assert sub.state == :premium
    end

    test "premium -> downgrade -> active" do
      {:ok, sub} = Subscription.create(%{plan_name: "Premium"})
      {:ok, sub} = Subscription.activate(sub)
      {:ok, sub} = Subscription.upgrade(sub)

      {:ok, sub} = Subscription.downgrade(sub)
      assert sub.state == :active
    end

    test "full upgrade path: trial -> active -> premium" do
      {:ok, sub} = Subscription.create(%{plan_name: "Starter"})
      assert sub.state == :trial

      {:ok, sub} = Subscription.activate(sub)
      assert sub.state == :active

      {:ok, sub} = Subscription.upgrade(sub)
      assert sub.state == :premium
    end
  end

  describe "suspension and reactivation" do
    test "can suspend active subscription" do
      {:ok, sub} = Subscription.create(%{plan_name: "Basic"})
      {:ok, sub} = Subscription.activate(sub)

      {:ok, sub} = Subscription.suspend(sub, %{suspended_reason: "Payment failed"})
      assert sub.state == :suspended
      assert sub.suspended_reason == "Payment failed"
    end

    test "can suspend premium subscription" do
      {:ok, sub} = Subscription.create(%{plan_name: "Premium"})
      {:ok, sub} = Subscription.activate(sub)
      {:ok, sub} = Subscription.upgrade(sub)

      {:ok, sub} = Subscription.suspend(sub, %{suspended_reason: "Account review"})
      assert sub.state == :suspended
    end

    test "can reactivate suspended subscription" do
      {:ok, sub} = Subscription.create(%{plan_name: "Basic"})
      {:ok, sub} = Subscription.activate(sub)
      {:ok, sub} = Subscription.suspend(sub, %{suspended_reason: "Payment failed"})

      {:ok, sub} = Subscription.reactivate(sub)
      assert sub.state == :active
    end

    test "cannot suspend trial subscription" do
      {:ok, sub} = Subscription.create(%{plan_name: "Basic"})
      assert sub.state == :trial

      {:error, error} = Subscription.suspend(sub, %{suspended_reason: "Test"})
      assert Exception.message(error) =~ "suspend"
    end
  end

  describe "trial expiration" do
    test "trial can expire" do
      {:ok, sub} = Subscription.create(%{plan_name: "Basic"})
      assert sub.state == :trial

      {:ok, sub} = Subscription.expire(sub)
      assert sub.state == :expired
    end

    test "cannot expire active subscription" do
      {:ok, sub} = Subscription.create(%{plan_name: "Basic"})
      {:ok, sub} = Subscription.activate(sub)

      {:error, error} = Subscription.expire(sub)
      assert Exception.message(error) =~ "expire"
    end
  end

  describe "wildcard cancellation" do
    test "can cancel from trial" do
      {:ok, sub} = Subscription.create(%{plan_name: "Basic"})
      assert sub.state == :trial

      {:ok, sub} = Subscription.cancel(sub, %{cancellation_reason: "Changed mind"})
      assert sub.state == :cancelled
      assert sub.cancellation_reason == "Changed mind"
    end

    test "can cancel from active" do
      {:ok, sub} = Subscription.create(%{plan_name: "Basic"})
      {:ok, sub} = Subscription.activate(sub)

      {:ok, sub} = Subscription.cancel(sub, %{cancellation_reason: "Too expensive"})
      assert sub.state == :cancelled
    end

    test "can cancel from premium" do
      {:ok, sub} = Subscription.create(%{plan_name: "Premium"})
      {:ok, sub} = Subscription.activate(sub)
      {:ok, sub} = Subscription.upgrade(sub)

      {:ok, sub} = Subscription.cancel(sub, %{cancellation_reason: "Switching providers"})
      assert sub.state == :cancelled
    end

    test "can cancel from suspended" do
      {:ok, sub} = Subscription.create(%{plan_name: "Basic"})
      {:ok, sub} = Subscription.activate(sub)
      {:ok, sub} = Subscription.suspend(sub, %{suspended_reason: "Payment failed"})

      {:ok, sub} = Subscription.cancel(sub, %{cancellation_reason: "Giving up"})
      assert sub.state == :cancelled
    end

    test "can cancel from expired" do
      {:ok, sub} = Subscription.create(%{plan_name: "Basic"})
      {:ok, sub} = Subscription.expire(sub)

      {:ok, sub} = Subscription.cancel(sub, %{cancellation_reason: "Not renewing"})
      assert sub.state == :cancelled
    end

    test "can cancel already cancelled subscription (wildcard includes cancelled)" do
      {:ok, sub} = Subscription.create(%{plan_name: "Basic"})
      {:ok, sub} = Subscription.cancel(sub, %{cancellation_reason: "First reason"})

      # Wildcard allows transition from any state including cancelled
      {:ok, sub} = Subscription.cancel(sub, %{cancellation_reason: "Updated reason"})
      assert sub.state == :cancelled
      assert sub.cancellation_reason == "Updated reason"
    end
  end

  describe "multiple initial states" do
    test "can create with default trial state" do
      {:ok, sub} = Subscription.create(%{plan_name: "Basic"})
      assert sub.state == :trial
    end

    test "can create directly as active (enterprise signup)" do
      {:ok, sub} =
        Subscription.create_active(%{plan_name: "Enterprise", user_email: "corp@example.com"})

      assert sub.state == :active
    end

    test "enterprise signup can upgrade immediately" do
      {:ok, sub} = Subscription.create_active(%{plan_name: "Enterprise"})
      assert sub.state == :active

      {:ok, sub} = Subscription.upgrade(sub)
      assert sub.state == :premium
    end
  end

  describe "auto-generated actions" do
    test "activate action was auto-generated from transition" do
      action = Ash.Resource.Info.action(Subscription, :activate)
      assert action != nil
      assert action.type == :update
    end

    test "upgrade action was auto-generated from transition" do
      action = Ash.Resource.Info.action(Subscription, :upgrade)
      assert action != nil
      assert action.type == :update
    end

    test "cancel action was auto-generated from transition" do
      action = Ash.Resource.Info.action(Subscription, :cancel)
      assert action != nil
      assert action.type == :update
    end
  end

  describe "invalid transitions" do
    test "cannot activate already active subscription" do
      {:ok, sub} = Subscription.create(%{plan_name: "Basic"})
      {:ok, sub} = Subscription.activate(sub)

      {:error, error} = Subscription.activate(sub)
      assert Exception.message(error) =~ "activate"
    end

    test "cannot upgrade from trial" do
      {:ok, sub} = Subscription.create(%{plan_name: "Basic"})

      {:error, error} = Subscription.upgrade(sub)
      assert Exception.message(error) =~ "upgrade"
    end

    test "cannot downgrade from active" do
      {:ok, sub} = Subscription.create(%{plan_name: "Basic"})
      {:ok, sub} = Subscription.activate(sub)

      {:error, error} = Subscription.downgrade(sub)
      assert Exception.message(error) =~ "downgrade"
    end

    test "cannot reactivate non-suspended subscription" do
      {:ok, sub} = Subscription.create(%{plan_name: "Basic"})
      {:ok, sub} = Subscription.activate(sub)

      {:error, error} = Subscription.reactivate(sub)
      assert Exception.message(error) =~ "reactivate"
    end
  end

  describe "possible_next_states helper" do
    test "returns correct states for trial" do
      {:ok, sub} = Subscription.create(%{plan_name: "Basic"})
      next_states = AshStateMachine.possible_next_states(sub)

      assert :active in next_states
      assert :expired in next_states
      assert :cancelled in next_states
    end

    test "returns correct states for active" do
      {:ok, sub} = Subscription.create(%{plan_name: "Basic"})
      {:ok, sub} = Subscription.activate(sub)
      next_states = AshStateMachine.possible_next_states(sub)

      assert :premium in next_states
      assert :suspended in next_states
      assert :cancelled in next_states
    end

    test "returns correct states for premium" do
      {:ok, sub} = Subscription.create(%{plan_name: "Premium"})
      {:ok, sub} = Subscription.activate(sub)
      {:ok, sub} = Subscription.upgrade(sub)
      next_states = AshStateMachine.possible_next_states(sub)

      assert :active in next_states
      assert :suspended in next_states
      assert :cancelled in next_states
    end
  end
end
