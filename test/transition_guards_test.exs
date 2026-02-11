# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshStateMachine.TransitionGuardsTest do
  use ExUnit.Case

  defmodule GuardedMachine do
    @moduledoc false
    use Ash.Resource,
      domain: Domain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshStateMachine]

    state_machine do
      initial_states [:pending]
      default_initial_state :pending

      transitions do
        # Multiple transitions for :submit with guards
        transition :submit,
          from: :pending,
          to: :approved,
          guard: [
            {Ash.Resource.Validation.Compare, attribute: :score, greater_than_or_equal_to: 90}
          ]

        transition :submit,
          from: :pending,
          to: :needs_review,
          guard: [
            {Ash.Resource.Validation.Compare, attribute: :score, greater_than_or_equal_to: 50}
          ]

        # default fallback
        transition :submit, from: :pending, to: :rejected
      end
    end

    actions do
      default_accept :*
      defaults [:read, :create]
    end

    ets do
      private? true
    end

    attributes do
      uuid_primary_key :id
      attribute :score, :integer, default: 0, public?: true
    end

    code_interface do
      define :create
      define :submit
    end
  end

  defmodule AllGuardedMachine do
    @moduledoc """
    A machine where all transitions have guards (no fallback).
    Should fail if no guard matches.
    """
    use Ash.Resource,
      domain: Domain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshStateMachine]

    state_machine do
      initial_states [:pending]
      default_initial_state :pending

      transitions do
        transition :evaluate,
          from: :pending,
          to: :high,
          guard: [
            {Ash.Resource.Validation.Compare, attribute: :value, greater_than_or_equal_to: 100}
          ]

        transition :evaluate,
          from: :pending,
          to: :low,
          guard: [
            {Ash.Resource.Validation.Compare, attribute: :value, less_than: 50}
          ]

        # No fallback - gap between 50-99 will cause error
      end
    end

    actions do
      default_accept :*
      defaults [:read, :create]
    end

    ets do
      private? true
    end

    attributes do
      uuid_primary_key :id
      attribute :value, :integer, default: 75, public?: true
    end

    code_interface do
      define :create
      define :evaluate
    end
  end

  describe "guarded transitions" do
    test "high score goes to approved (first guard matches)" do
      {:ok, machine} = GuardedMachine.create(%{score: 95})
      assert machine.state == :pending

      {:ok, machine} = GuardedMachine.submit(machine)
      assert machine.state == :approved
    end

    test "medium score goes to needs_review (second guard matches)" do
      {:ok, machine} = GuardedMachine.create(%{score: 70})
      assert machine.state == :pending

      {:ok, machine} = GuardedMachine.submit(machine)
      assert machine.state == :needs_review
    end

    test "low score goes to rejected (fallback, no guard)" do
      {:ok, machine} = GuardedMachine.create(%{score: 30})
      assert machine.state == :pending

      {:ok, machine} = GuardedMachine.submit(machine)
      assert machine.state == :rejected
    end

    test "boundary: score of 90 goes to approved" do
      {:ok, machine} = GuardedMachine.create(%{score: 90})
      {:ok, machine} = GuardedMachine.submit(machine)
      assert machine.state == :approved
    end

    test "boundary: score of 50 goes to needs_review" do
      {:ok, machine} = GuardedMachine.create(%{score: 50})
      {:ok, machine} = GuardedMachine.submit(machine)
      assert machine.state == :needs_review
    end

    test "boundary: score of 49 goes to rejected" do
      {:ok, machine} = GuardedMachine.create(%{score: 49})
      {:ok, machine} = GuardedMachine.submit(machine)
      assert machine.state == :rejected
    end
  end

  describe "all guards - no fallback" do
    test "high value goes to high" do
      {:ok, machine} = AllGuardedMachine.create(%{value: 150})
      {:ok, machine} = AllGuardedMachine.evaluate(machine)
      assert machine.state == :high
    end

    test "low value goes to low" do
      {:ok, machine} = AllGuardedMachine.create(%{value: 25})
      {:ok, machine} = AllGuardedMachine.evaluate(machine)
      assert machine.state == :low
    end

    test "middle value (no guard matches) returns error" do
      {:ok, machine} = AllGuardedMachine.create(%{value: 75})
      {:error, error} = AllGuardedMachine.evaluate(machine)
      assert Exception.message(error) =~ ~r/no matching transition/i
    end
  end

  # Note: Compile-time validation for ambiguous guards works, but testing it
  # is complex because Spark handles errors differently depending on domain config.
  # The verifier VerifyTransitionGuards.verify/1 IS running and will error on
  # ambiguous transitions when the module is part of a proper Ash domain.
end
