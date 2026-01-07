# SPDX-FileCopyrightText: 2023 ash_state_machine contributors <https://github.com/ash-project/ash_state_machine/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule Domain do
  @moduledoc false
  use Ash.Domain

  resources do
    resource ThreeStates
    resource Order
    resource NextStateMachine
    resource Verification
    resource PaymentMachine
    resource InventoryMachine
    resource ParallelOrder

    # Loan Application resources
    resource LoanApplication.Application
    resource LoanApplication.IdentityCheck
    resource LoanApplication.IncomeCheck
    resource LoanApplication.EmploymentCheck
    resource LoanApplication.CreditCheck
    resource LoanApplication.RiskAssessment
    resource LoanApplication.ComplianceCheck

    # Auto-transition test resources
    resource AutoTransitionMachine
    resource AutoInjectMachine

    # Entry/exit callback test resources
    resource AshStateMachine.EntryExitCallbacksTest.OrderWithCallbacks
    resource AshStateMachine.EntryExitCallbacksTest.OrderWithInitialCallback

    # Entry/exit with regions test resources
    resource AshStateMachine.EntryExitWithRegionsTest.PaymentWithCallbacks
    resource AshStateMachine.EntryExitWithRegionsTest.InventoryWithCallbacks
    resource AshStateMachine.EntryExitWithRegionsTest.OrderWithRegionCallbacks
  end
end
