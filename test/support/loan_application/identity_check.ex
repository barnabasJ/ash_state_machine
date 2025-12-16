# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule LoanApplication.IdentityCheck do
  @moduledoc """
  Verifies applicant identity during loan verification phase.
  """
  use Ash.Resource,
    domain: Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshStateMachine]

  state_machine do
    initial_states([:pending])
    default_initial_state(:pending)
    failure_states([:failed])

    transitions do
      transition(:start_check, from: :pending, to: :checking)
      transition(:verify, from: :checking, to: :verified)
      transition(:fail, from: [:pending, :checking], to: :failed)
    end
  end

  actions do
    default_accept(:*)
    defaults([:read, :destroy])

    create :create do
      accept([:parent_id])
    end

    update :start_check do
      change(transition_state(:checking))
    end

    update :verify do
      require_atomic?(false)
      change(transition_state(:verified))

      change(
        check_parallel_completion(
          parent_attribute: :parent_id,
          parent_resource: LoanApplication.Application
        )
      )
    end

    update :fail do
      require_atomic?(false)
      change(transition_state(:failed))

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
