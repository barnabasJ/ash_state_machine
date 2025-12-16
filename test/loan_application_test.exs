# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshStateMachine.LoanApplicationTest do
  @moduledoc """
  Tests for the loan application workflow demonstrating multiple parallel regions.

  This test suite exercises a real-world scenario where a loan application
  progresses through multiple phases, each with concurrent checks:

  1. Verification phase (all 3 checks must pass)
  2. Underwriting phase (2 of 3 checks must pass)

  The tests use the full flow with `check_parallel_completion` on region
  resources, so callbacks are invoked automatically when completion criteria
  are met.
  """
  use ExUnit.Case

  alias LoanApplication.Application

  describe "loan application with multiple parallel regions" do
    test "has correct parallel region configuration" do
      parallel_regions = AshStateMachine.Info.state_machine_parallel_regions(Application)

      assert length(parallel_regions) == 2

      # Find verification region
      verification = Enum.find(parallel_regions, &(&1.enter_state == :verifying))
      assert verification.exit_state == :verified
      assert verification.completion_strategy == :all
      assert verification.on_complete == :verification_complete
      assert length(verification.regions) == 3

      verification_region_names = Enum.map(verification.regions, & &1.name)
      assert :identity_check in verification_region_names
      assert :income_check in verification_region_names
      assert :employment_check in verification_region_names

      # Find underwriting region
      underwriting = Enum.find(parallel_regions, &(&1.enter_state == :underwriting))
      assert underwriting.exit_state == :underwritten
      assert underwriting.completion_strategy == {:require_n, 2}
      assert underwriting.on_complete == :underwriting_complete
      assert length(underwriting.regions) == 3

      underwriting_region_names = Enum.map(underwriting.regions, & &1.name)
      assert :credit_check in underwriting_region_names
      assert :risk_assessment in underwriting_region_names
      assert :compliance_check in underwriting_region_names
    end

    test "creates verification regions when entering verifying state" do
      app = Application.create!()
      assert app.state == :submitted

      app = Application.start_verification!(app)
      assert app.state == :verifying

      # Load and verify all verification regions were created
      app = Ash.load!(app, [:identity_check, :income_check, :employment_check], domain: Domain)

      assert app.identity_check != nil
      assert app.identity_check.state == :pending
      assert app.identity_check.parent_id == app.id

      assert app.income_check != nil
      assert app.income_check.state == :pending
      assert app.income_check.parent_id == app.id

      assert app.employment_check != nil
      assert app.employment_check.state == :pending
      assert app.employment_check.parent_id == app.id
    end

    test "verification phase - automatically transitions when all checks pass" do
      app = Application.create!() |> Application.start_verification!()
      app = Ash.load!(app, [:identity_check, :income_check, :employment_check], domain: Domain)

      # Complete first two checks - parent should still be in :verifying
      complete_verification_check(app.identity_check)
      complete_verification_check(app.income_check)

      app = Ash.get!(Application, app.id, domain: Domain)
      assert app.state == :verifying

      # Complete the last check - parent should automatically transition to :verified
      app = Ash.load!(app, [:employment_check], domain: Domain)
      complete_verification_check(app.employment_check)

      # Reload parent - should have automatically transitioned
      app = Ash.get!(Application, app.id, domain: Domain)
      assert app.state == :verified
    end

    test "verification phase - stays in verifying if any check fails" do
      app = Application.create!() |> Application.start_verification!()
      app = Ash.load!(app, [:identity_check, :income_check, :employment_check], domain: Domain)

      # Complete two checks, fail one
      complete_verification_check(app.identity_check)
      complete_verification_check(app.income_check)
      fail_verification_check(app.employment_check)

      # Parent should still be in :verifying (callback not invoked due to failure)
      app = Ash.get!(Application, app.id, domain: Domain)
      assert app.state == :verifying

      # But completion check should return error
      assert {:error, :partial_failure} = AshStateMachine.check_parallel_completion(app, Domain)
    end

    test "verification phase - pending while checks in progress" do
      app = Application.create!() |> Application.start_verification!()
      app = Ash.load!(app, [:identity_check, :income_check, :employment_check], domain: Domain)

      # Complete only one check
      complete_verification_check(app.identity_check)

      # Parent should still be in :verifying
      app = Ash.get!(Application, app.id, domain: Domain)
      assert app.state == :verifying
      assert {:ok, :pending} = AshStateMachine.check_parallel_completion(app, Domain)
    end

    test "transitions from verification to underwriting phase" do
      # Complete verification phase
      app = complete_verification_phase()
      assert app.state == :verified

      # Start underwriting phase
      app = Application.start_underwriting!(app)
      assert app.state == :underwriting

      # Verify underwriting regions were created
      app = Ash.load!(app, [:credit_check, :risk_assessment, :compliance_check], domain: Domain)

      assert app.credit_check != nil
      assert app.credit_check.state == :pending

      assert app.risk_assessment != nil
      assert app.risk_assessment.state == :pending

      assert app.compliance_check != nil
      assert app.compliance_check.state == :pending
    end

    test "underwriting phase - automatically transitions when 2 of 3 pass" do
      app = complete_verification_phase() |> Application.start_underwriting!()
      app = Ash.load!(app, [:credit_check, :risk_assessment, :compliance_check], domain: Domain)

      # Pass credit check - not enough yet
      complete_underwriting_check(app.credit_check, :approve)

      app = Ash.get!(Application, app.id, domain: Domain)
      assert app.state == :underwriting

      # Pass risk assessment - now 2 of 3, should auto-transition
      app = Ash.load!(app, [:risk_assessment], domain: Domain)
      complete_underwriting_check(app.risk_assessment, :mark_low_risk)

      # Parent should have automatically transitioned to :underwritten
      app = Ash.get!(Application, app.id, domain: Domain)
      assert app.state == :underwritten
    end

    test "underwriting phase - still transitions with 2 pass and 1 fail" do
      app = complete_verification_phase() |> Application.start_underwriting!()
      app = Ash.load!(app, [:credit_check, :risk_assessment, :compliance_check], domain: Domain)

      # Pass credit check
      complete_underwriting_check(app.credit_check, :approve)

      # Fail compliance check
      fail_underwriting_check(app.compliance_check, :fail)

      app = Ash.get!(Application, app.id, domain: Domain)
      assert app.state == :underwriting

      # Pass risk assessment - now 2 passed, should auto-transition
      app = Ash.load!(app, [:risk_assessment], domain: Domain)
      complete_underwriting_check(app.risk_assessment, :mark_low_risk)

      app = Ash.get!(Application, app.id, domain: Domain)
      assert app.state == :underwritten
    end

    test "underwriting phase - stays pending when 2 fail (impossible to meet criteria)" do
      app = complete_verification_phase() |> Application.start_underwriting!()
      app = Ash.load!(app, [:credit_check, :risk_assessment, :compliance_check], domain: Domain)

      # Fail 2 of 3 checks
      fail_underwriting_check(app.credit_check, :reject)
      fail_underwriting_check(app.risk_assessment, :mark_high_risk)

      # Parent should still be in :underwriting
      app = Ash.get!(Application, app.id, domain: Domain)
      assert app.state == :underwriting

      # Completion check should return insufficient_completions
      assert {:error, :insufficient_completions} =
               AshStateMachine.check_parallel_completion(app, Domain)
    end

    test "full workflow - happy path to approval" do
      # 1. Create application
      app = Application.create!()
      assert app.state == :submitted

      # 2. Start and complete verification (auto-transitions to :verified)
      app = Application.start_verification!(app)
      assert app.state == :verifying

      app = Ash.load!(app, [:identity_check, :income_check, :employment_check], domain: Domain)
      complete_verification_check(app.identity_check)
      complete_verification_check(app.income_check)
      complete_verification_check(app.employment_check)

      app = Ash.get!(Application, app.id, domain: Domain)
      assert app.state == :verified

      # 3. Start and complete underwriting (auto-transitions to :underwritten)
      app = Application.start_underwriting!(app)
      assert app.state == :underwriting

      app = Ash.load!(app, [:credit_check, :compliance_check], domain: Domain)
      complete_underwriting_check(app.credit_check, :approve)
      complete_underwriting_check(app.compliance_check, :pass)

      app = Ash.get!(Application, app.id, domain: Domain)
      assert app.state == :underwritten

      # 4. Final approval
      app = Application.approve!(app)
      assert app.state == :approved
    end

    test "get_region_states returns correct regions based on current state" do
      # In verification phase
      app = Application.create!() |> Application.start_verification!()

      states = AshStateMachine.get_region_states(app, Domain)
      assert length(states) == 3

      region_names = Enum.map(states, fn {name, _} -> name end)
      assert :identity_check in region_names
      assert :income_check in region_names
      assert :employment_check in region_names

      # Transition to underwriting phase
      app = complete_verification_phase_from(app)
      app = Application.start_underwriting!(app)

      # Now should return underwriting regions
      states = AshStateMachine.get_region_states(app, Domain)
      assert length(states) == 3

      region_names = Enum.map(states, fn {name, _} -> name end)
      assert :credit_check in region_names
      assert :risk_assessment in region_names
      assert :compliance_check in region_names
    end

    test "find_active_parallel_region returns correct region for each state" do
      app = Application.create!()

      # No parallel region in submitted state
      assert AshStateMachine.ParallelCoordinator.find_active_parallel_region(app) == nil

      # Verification region in verifying state
      app = Application.start_verification!(app)
      region = AshStateMachine.ParallelCoordinator.find_active_parallel_region(app)
      assert region.enter_state == :verifying
      assert region.completion_strategy == :all

      # Complete verification
      app = complete_verification_phase_from(app)

      # No parallel region in verified state
      assert AshStateMachine.ParallelCoordinator.find_active_parallel_region(app) == nil

      # Underwriting region in underwriting state
      app = Application.start_underwriting!(app)
      region = AshStateMachine.ParallelCoordinator.find_active_parallel_region(app)
      assert region.enter_state == :underwriting
      assert region.completion_strategy == {:require_n, 2}
    end

    test "can cancel application at various stages" do
      # Cancel from submitted
      app = Application.create!()
      app = Application.cancel!(app)
      assert app.state == :cancelled

      # Cancel from verifying
      app = Application.create!() |> Application.start_verification!()
      app = Application.cancel!(app)
      assert app.state == :cancelled

      # Cancel from verified
      app = complete_verification_phase()
      app = Application.cancel!(app)
      assert app.state == :cancelled

      # Cancel from underwriting
      app = complete_verification_phase() |> Application.start_underwriting!()
      app = Application.cancel!(app)
      assert app.state == :cancelled
    end
  end

  # Helper functions

  defp complete_verification_check(check) do
    check
    |> Ash.Changeset.for_update(:start_check, %{}, domain: Domain)
    |> Ash.update!()
    |> Ash.Changeset.for_update(:verify, %{}, domain: Domain)
    |> Ash.update!()
  end

  defp fail_verification_check(check) do
    check
    |> Ash.Changeset.for_update(:start_check, %{}, domain: Domain)
    |> Ash.update!()
    |> Ash.Changeset.for_update(:fail, %{}, domain: Domain)
    |> Ash.update!()
  end

  defp complete_underwriting_check(check, action) do
    check
    |> Ash.Changeset.for_update(:run, %{}, domain: Domain)
    |> Ash.update!()
    |> Ash.Changeset.for_update(action, %{}, domain: Domain)
    |> Ash.update!()
  end

  defp fail_underwriting_check(check, action) do
    check
    |> Ash.Changeset.for_update(:run, %{}, domain: Domain)
    |> Ash.update!()
    |> Ash.Changeset.for_update(action, %{}, domain: Domain)
    |> Ash.update!()
  end

  defp complete_verification_phase do
    Application.create!()
    |> Application.start_verification!()
    |> complete_verification_phase_from()
  end

  defp complete_verification_phase_from(app) do
    app = Ash.load!(app, [:identity_check, :income_check, :employment_check], domain: Domain)
    complete_verification_check(app.identity_check)
    complete_verification_check(app.income_check)
    complete_verification_check(app.employment_check)
    Ash.get!(Application, app.id, domain: Domain)
  end
end
