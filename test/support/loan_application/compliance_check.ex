# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule LoanApplication.ComplianceCheck do
  @moduledoc """
  Performs compliance check during loan underwriting phase.
  """
  use Ash.Resource,
    domain: Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshStateMachine]

  state_machine do
    initial_states([:pending])
    default_initial_state(:pending)
    failure_states([:non_compliant])

    transitions do
      transition(:run, from: :pending, to: :running)
      transition(:pass, from: :running, to: :compliant)
      transition(:fail, from: :running, to: :non_compliant)
    end
  end

  actions do
    default_accept(:*)
    defaults([:read, :destroy])

    create :create do
      accept([:parent_id])
    end

    update :run do
      change(transition_state(:running))
    end

    update :pass do
      require_atomic?(false)
      change(transition_state(:compliant))

      change(
        check_parallel_completion(
          parent_attribute: :parent_id,
          parent_resource: LoanApplication.Application
        )
      )
    end

    update :fail do
      require_atomic?(false)
      change(transition_state(:non_compliant))

      change(
        check_parallel_completion(
          parent_attribute: :parent_id,
          parent_resource: LoanApplication.Application
        )
      )
    end
  end

  ets do
    private?(true)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:parent_id, :uuid, allow_nil?: false, public?: true)
  end
end
