# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule LoanApplication.Application do
  @moduledoc """
  A loan application that progresses through multiple phases, each with
  concurrent parallel regions.

  ## Workflow

  1. **submitted** → **verifying**: Three concurrent verification checks
     - Identity verification
     - Income verification
     - Employment verification
     All must pass (completion_strategy: :all)

  2. **verified** → **underwriting**: Three concurrent underwriting checks
     - Credit check
     - Risk assessment
     - Compliance check
     At least 2 must pass (completion_strategy: {:require_n, 2})

  3. **underwritten** → **approved** or **denied**

  This demonstrates:
  - Multiple parallel_region groups on different states
  - Different completion strategies (:all vs {:require_n, 2})
  - Callback-based completion handling
  """
  use Ash.Resource,
    domain: Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshStateMachine]

  state_machine do
    initial_states([:submitted])
    default_initial_state(:submitted)

    transitions do
      # Start verification phase
      transition(:start_verification, from: :submitted, to: :verifying)

      # Verification callbacks
      transition(:verification_complete, from: :verifying, to: :verified)
      transition(:verification_failed, from: :verifying, to: :denied)

      # Start underwriting phase
      transition(:start_underwriting, from: :verified, to: :underwriting)

      # Underwriting callbacks
      transition(:underwriting_complete, from: :underwriting, to: :underwritten)
      transition(:underwriting_failed, from: :underwriting, to: :denied)

      # Final decision
      transition(:approve, from: :underwritten, to: :approved)
      transition(:deny, from: :underwritten, to: :denied)

      # Cancel at any point before approval
      transition(:cancel,
        from: [:submitted, :verifying, :verified, :underwriting],
        to: :cancelled
      )
    end

    parallel_regions do
      # Phase 1: Verification - all checks must pass
      parallel_region :verifying, :verified do
        completion_strategy(:all)
        on_complete(:verification_complete)

        region(:identity_check, LoanApplication.IdentityCheck)
        region(:income_check, LoanApplication.IncomeCheck)
        region(:employment_check, LoanApplication.EmploymentCheck)
      end

      # Phase 2: Underwriting - 2 of 3 checks must pass
      parallel_region :underwriting, :underwritten do
        completion_strategy({:require_n, 2})
        on_complete(:underwriting_complete)

        region(:credit_check, LoanApplication.CreditCheck)
        region(:risk_assessment, LoanApplication.RiskAssessment)
        region(:compliance_check, LoanApplication.ComplianceCheck)
      end
    end
  end

  actions do
    default_accept(:*)
    defaults([:read, :destroy])

    create :create do
      primary?(true)
    end

    # Start verification - activates verification parallel region
    update :start_verification do
      require_atomic?(false)
      change(transition_state(:verifying))
      change(activate_parallel_regions())
    end

    # Callback when all verification checks complete
    # Called automatically by check_parallel_completion when all regions succeed
    update :verification_complete do
      change(transition_state(:verified))
    end

    # Callback when verification fails
    update :verification_failed do
      change(transition_state(:denied))
    end

    # Start underwriting - activates underwriting parallel region
    update :start_underwriting do
      require_atomic?(false)
      change(transition_state(:underwriting))
      change(activate_parallel_regions())
    end

    # Callback when underwriting checks complete (2 of 3 passed)
    # Called automatically by check_parallel_completion when {:require_n, 2} is satisfied
    update :underwriting_complete do
      change(transition_state(:underwritten))
    end

    # Callback when underwriting fails
    update :underwriting_failed do
      change(transition_state(:denied))
    end

    # Final approval
    update :approve do
      change(transition_state(:approved))
    end

    # Final denial
    update :deny do
      change(transition_state(:denied))
    end

    # Cancel application
    update :cancel do
      change(transition_state(:cancelled))
    end
  end

  code_interface do
    define(:create)
    define(:start_verification)
    define(:start_underwriting)
    define(:approve)
    define(:deny)
    define(:cancel)
  end

  ets do
    private?(true)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:applicant_name, :string, public?: true)
    attribute(:loan_amount, :decimal, public?: true)
  end
end
