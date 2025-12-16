# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule PaymentMachine do
  @moduledoc """
  Test resource representing a payment processing state machine.
  Used as a parallel region in ParallelOrder.
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
      transition(:process, from: :pending, to: :processing)
      transition(:complete, from: :processing, to: :completed)
      transition(:fail, from: [:pending, :processing], to: :failed)
    end
  end

  actions do
    default_accept(:*)
    defaults([:read, :destroy])

    create :create do
      accept([:parent_id])
    end

    update :process do
      change(transition_state(:processing))
    end

    update :complete do
      change(transition_state(:completed))
    end

    update :fail do
      change(transition_state(:failed))
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
