# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule Subscription do
  @moduledoc """
  A SaaS subscription lifecycle with wildcards and auto-generated actions.

  Demonstrates:
  - Wildcard transitions (`:*` for "from any state")
  - Auto-generated actions from transitions
  - Multiple initial states
  - Suspension and reactivation flows

  ## Workflow

  trial -> active -> premium
    |        |          |
    |        +----<-----+  (downgrade)
    |        |
    |        +-> suspended -> active (reactivate)
    |
    +-> expired

  From ANY state -> cancelled (wildcard)
  """
  use Ash.Resource,
    domain: Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshStateMachine]

  state_machine do
    initial_states [:trial, :active]
    default_initial_state :trial

    transitions do
      # Basic lifecycle
      transition :activate, from: :trial, to: :active
      transition :upgrade, from: :active, to: :premium
      transition :downgrade, from: :premium, to: :active

      # Suspension from any paid state
      transition :suspend, from: [:active, :premium], to: :suspended
      transition :reactivate, from: :suspended, to: :active

      # Trial expiration
      transition :expire, from: :trial, to: :expired

      # Wildcard: cancel from any state
      transition :cancel, from: :*, to: :cancelled
    end
  end

  actions do
    default_accept :*
    defaults [:read]

    create :create do
      accept [:plan_name, :user_email]
    end

    # Create directly as active (enterprise signups)
    create :create_active do
      accept [:plan_name, :user_email]
      change set_attribute(:state, :active)
    end

    # Explicitly define actions that need to accept arguments
    update :suspend do
      accept [:suspended_reason]
    end

    update :cancel do
      accept [:cancellation_reason]
    end
  end

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id

    attribute :plan_name, :string, public?: true
    attribute :user_email, :string, public?: true
    attribute :suspended_reason, :string, public?: true
    attribute :cancellation_reason, :string, public?: true
  end

  code_interface do
    define :create
    define :create_active
    define :activate
    define :upgrade
    define :downgrade
    define :suspend
    define :reactivate
    define :expire
    define :cancel
  end
end
