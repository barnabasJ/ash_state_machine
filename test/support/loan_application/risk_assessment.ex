# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule LoanApplication.RiskAssessment do
  @moduledoc """
  Performs risk assessment during loan underwriting phase.
  """
  use Ash.Resource,
    domain: Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshStateMachine]

  state_machine do
    initial_states([:pending])
    default_initial_state(:pending)
    failure_states([:high_risk])

    transitions do
      transition(:run, from: :pending, to: :running)
      transition(:mark_low_risk, from: :running, to: :acceptable)
      transition(:mark_high_risk, from: :running, to: :high_risk)
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

    update :mark_low_risk do
      require_atomic?(false)
      change(transition_state(:acceptable))

      change(
        check_parallel_completion(
          parent_attribute: :parent_id,
          parent_resource: LoanApplication.Application
        )
      )
    end

    update :mark_high_risk do
      require_atomic?(false)
      change(transition_state(:high_risk))

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
