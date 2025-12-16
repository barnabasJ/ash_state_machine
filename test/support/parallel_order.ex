# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule ParallelOrder do
  @moduledoc """
  Test resource demonstrating parallel regions functionality.

  When the order enters the :processing state, payment and inventory
  regions are activated and can progress independently.
  """
  use Ash.Resource,
    domain: Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshStateMachine]

  state_machine do
    initial_states([:pending])
    default_initial_state(:pending)

    transitions do
      transition(:start_processing, from: :pending, to: :processing)
      transition(:complete, from: :processing, to: :completed)
      transition(:cancel, from: [:pending, :processing], to: :cancelled)
    end

    parallel_regions do
      region(:payment, PaymentMachine,
        activate_on: :processing,
        completion_strategy: :require_all
      )

      region(:inventory, InventoryMachine,
        activate_on: :processing,
        completion_strategy: :require_all
      )
    end
  end

  actions do
    default_accept(:*)
    defaults([:read, :destroy])

    create :create do
      primary?(true)
    end

    update :start_processing do
      require_atomic?(false)
      change(transition_state(:processing))
      change(activate_parallel_regions())
    end

    update :complete do
      change(transition_state(:completed))
    end

    update :cancel do
      change(transition_state(:cancelled))
    end
  end

  code_interface do
    define(:create)
    define(:start_processing)
    define(:complete)
    define(:cancel)
  end

  ets do
    private?(true)
  end

  attributes do
    uuid_primary_key(:id)
  end
end
