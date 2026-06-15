# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshStateMachine.AutoTransitionTest do
  @moduledoc """
  Tests for automatic state transition injection and action generation.
  """
  use ExUnit.Case

  describe "auto-generated actions from transitions" do
    @tag story: "US-GTA-01"
    test "generated no-input transition actions expose metadata and transition state" do
      # Given transitions that reference actions the resource did not define explicitly
      # When AshStateMachine generates those update actions from the transitions
      # Then each generated action exposes `accept: []` input metadata (not nil)
      for action_name <- [:approve, :reject, :archive] do
        action = Ash.Resource.Info.action(AutoTransitionMachine, action_name)

        assert action
        assert action.accept == []
      end

      # When the generated actions run as normal no-input Ash update actions
      record = AutoTransitionMachine.create!()
      assert record.state == :pending

      # Then they still perform the configured state transition
      approved = AutoTransitionMachine.approve!(record)
      assert approved.state == :approved

      archived = AutoTransitionMachine.archive!(approved)
      assert archived.state == :archived
    end

    test "generated actions reject invalid transitions" do
      record = AutoTransitionMachine.create!()
      assert record.state == :pending

      # Cannot archive from pending (only from approved/rejected)
      assert_raise Ash.Error.Invalid, fn ->
        AutoTransitionMachine.archive!(record)
      end
    end

    test "can transition through full workflow" do
      record = AutoTransitionMachine.create!()

      # Reject path
      rejected = AutoTransitionMachine.reject!(record)
      assert rejected.state == :rejected

      # Archive from rejected
      archived = AutoTransitionMachine.archive!(rejected)
      assert archived.state == :archived
    end
  end

  describe "auto-injection into existing actions" do
    test "transitions are injected into actions without manual transition_state" do
      record = AutoInjectMachine.create!()
      assert record.state == :pending

      # Start transition with custom argument
      started = AutoInjectMachine.start!(record, "test-user")
      assert started.state == :running

      # Complete transition with custom argument
      completed = AutoInjectMachine.complete!(started, DateTime.utc_now())
      assert completed.state == :completed
    end

    test "actions preserve custom arguments" do
      record = AutoInjectMachine.create!()

      # The start action should accept the started_by argument
      changeset =
        record
        |> Ash.Changeset.for_update(:start, %{started_by: "admin"})

      assert changeset.valid?
      assert Ash.Changeset.get_argument(changeset, :started_by) == "admin"
    end

    test "fail transition works with injected transition" do
      record = AutoInjectMachine.create!()

      started = AutoInjectMachine.start!(record, "user")
      assert started.state == :running

      failed = AutoInjectMachine.fail!(started, "network error")
      assert failed.state == :failed
    end

    test "invalid transitions are still rejected" do
      record = AutoInjectMachine.create!()

      # Cannot complete from pending (must be running first)
      assert_raise Ash.Error.Invalid, fn ->
        AutoInjectMachine.complete!(record, DateTime.utc_now())
      end
    end
  end

  describe "opt-out behavior" do
    test "existing resources with manual transitions still work" do
      # ThreeStates has manual transition_state calls - should work as before
      record = ThreeStates.create!()
      assert record.state == :pending

      begun = ThreeStates.begin!(record)
      assert begun.state == :executing

      completed = ThreeStates.complete!(begun)
      assert completed.state == :complete
    end
  end
end
