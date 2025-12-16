# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule InventoryMachine do
  @moduledoc """
  Test resource representing an inventory reservation state machine.
  Used as a parallel region in ParallelOrder.
  """
  use Ash.Resource,
    domain: Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshStateMachine]

  state_machine do
    initial_states([:pending])
    default_initial_state(:pending)
    failure_states([:unavailable])

    transitions do
      transition(:reserve, from: :pending, to: :reserving)
      transition(:confirm, from: :reserving, to: :reserved)
      transition(:mark_unavailable, from: [:pending, :reserving], to: :unavailable)
    end
  end

  actions do
    default_accept(:*)
    defaults([:read, :destroy])

    create :create do
      accept([:parent_id])
    end

    update :reserve do
      change(transition_state(:reserving))
    end

    update :confirm do
      change(transition_state(:reserved))
    end

    update :mark_unavailable do
      change(transition_state(:unavailable))
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
