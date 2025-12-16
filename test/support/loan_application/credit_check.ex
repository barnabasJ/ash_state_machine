# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule LoanApplication.CreditCheck do
  @moduledoc """
  Performs credit check during loan underwriting phase.
  """
  use Ash.Resource,
    domain: Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshStateMachine]

  state_machine do
    initial_states([:pending])
    default_initial_state(:pending)
    failure_states([:rejected])

    transitions do
      transition(:run, from: :pending, to: :running)
      transition(:approve, from: :running, to: :approved)
      transition(:reject, from: :running, to: :rejected)
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

    update :approve do
      require_atomic?(false)
      change(transition_state(:approved))

      change(
        check_parallel_completion(
          parent_attribute: :parent_id,
          parent_resource: LoanApplication.Application
        )
      )
    end

    update :reject do
      require_atomic?(false)
      change(transition_state(:rejected))

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
