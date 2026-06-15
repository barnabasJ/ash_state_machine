# SPDX-FileCopyrightText: 2023 ash_state_machine contributors <https://github.com/ash-project/ash_state_machine/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule Domain do
  @moduledoc false
  use Ash.Domain

  resources do
    # New E2E test resources
    resource SupportTicket
    resource Article
    resource Subscription
    resource EcommerceOrder

    # Loan Application resources (parallel regions)
    resource LoanApplication.Application
    resource LoanApplication.IdentityCheck
    resource LoanApplication.IncomeCheck
    resource LoanApplication.EmploymentCheck
    resource LoanApplication.CreditCheck
    resource LoanApplication.RiskAssessment
    resource LoanApplication.ComplianceCheck

    # Legacy resources - kept as insurance during refactoring
    resource ThreeStates
    resource Order
    resource NextStateMachine
    resource Verification
    resource PaymentMachine
    resource InventoryMachine
    resource ParallelOrder
    resource DynamicParallelOrder
    resource DynamicLineItemMachine
    resource AutoTransitionMachine
    resource AutoInjectMachine
    resource AshStateMachine.EntryExitCallbacksTest.OrderWithCallbacks
    resource AshStateMachine.EntryExitCallbacksTest.OrderWithInitialCallback
    resource AshStateMachine.EntryExitWithRegionsTest.PaymentWithCallbacks
    resource AshStateMachine.EntryExitWithRegionsTest.InventoryWithCallbacks
    resource AshStateMachine.EntryExitWithRegionsTest.OrderWithRegionCallbacks
    resource AshStateMachine.TransitionGuardsTest.GuardedMachine
    resource AshStateMachine.TransitionGuardsTest.AllGuardedMachine
  end
end
