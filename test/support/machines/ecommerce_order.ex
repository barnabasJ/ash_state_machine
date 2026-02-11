# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule EcommerceOrder do
  @moduledoc """
  An e-commerce order with basic transitions and helper functions.

  Demonstrates:
  - Simple linear state machine workflow
  - Multiple initial states
  - Cancellation from multiple states
  - `possible_next_states` helper function
  - Invalid transition error handling

  ## Workflow

  cart -> pending -> confirmed -> shipped -> delivered
    |        |           |
    +--------+-----------+-> cancelled
                                  |
                               returned (from delivered)
  """
  use Ash.Resource,
    domain: Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshStateMachine]

  state_machine do
    initial_states [:cart, :pending]
    default_initial_state :cart

    transitions do
      transition :checkout, from: :cart, to: :pending
      transition :confirm, from: :pending, to: :confirmed
      transition :ship, from: :confirmed, to: :shipped
      transition :deliver, from: :shipped, to: :delivered
      transition :cancel, from: [:cart, :pending, :confirmed], to: :cancelled
      transition :return, from: :delivered, to: :returned
    end
  end

  actions do
    default_accept :*
    defaults [:read]

    create :create do
      accept [:customer_email, :total_amount]
    end

    # Create with pending state (phone orders, API imports)
    create :create_pending do
      accept [:customer_email, :total_amount]
      change set_attribute(:state, :pending)
    end

    # Ship action needs to accept tracking_number
    update :ship do
      accept [:tracking_number]
    end
  end

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id

    attribute :customer_email, :string, public?: true
    attribute :total_amount, :decimal, public?: true
    attribute :shipping_address, :string, public?: true
    attribute :tracking_number, :string, public?: true
  end

  code_interface do
    define :create
    define :create_pending
    define :checkout
    define :confirm
    define :ship
    define :deliver
    define :cancel
    define :return
  end
end
