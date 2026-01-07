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
      transition(:start_processing, from: :pending, to: :processing, require_atomic?: false)
      # This transition is auto-detected as the on_complete target
      transition(:complete, from: :processing, to: :completed, require_atomic?: false)
      transition(:cancel, from: [:pending, :processing], to: :cancelled, require_atomic?: false)
    end

    parallel_regions do
      parallel_region :processing, :completed do
        completion_strategy(:all)
        # on_complete is optional - system auto-detects :complete transition

        region(:payment, PaymentMachine)
        region(:inventory, InventoryMachine)
      end
    end
  end

  actions do
    default_accept(:*)
    defaults([:read, :destroy])
    # All actions auto-generated from transitions!
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
