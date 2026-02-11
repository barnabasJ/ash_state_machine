# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule SupportTicket do
  @moduledoc """
  A customer support ticket with priority-based routing using guards.

  Demonstrates:
  - Transition guards for conditional routing
  - Multiple transitions for the same action with different outcomes
  - Fallback transitions when no guard matches
  - Full ticket lifecycle management

  ## Workflow

  New tickets are triaged based on priority:
  - Priority 8-10: Escalated immediately
  - Priority 5-7: High priority queue
  - Priority 1-4: Standard queue

  Then tickets flow through: assign -> in_progress -> resolve -> close
  Tickets can be reopened from resolved or closed states.
  """
  use Ash.Resource,
    domain: Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshStateMachine]

  state_machine do
    initial_states [:new]
    default_initial_state :new

    transitions do
      # Guards route tickets based on priority
      transition :triage,
        from: :new,
        to: :escalated,
        guard: [
          {Ash.Resource.Validation.Compare, attribute: :priority, greater_than_or_equal_to: 8}
        ]

      transition :triage,
        from: :new,
        to: :high_priority,
        guard: [
          {Ash.Resource.Validation.Compare, attribute: :priority, greater_than_or_equal_to: 5}
        ]

      # Fallback - no guard means it catches everything else
      transition :triage, from: :new, to: :standard

      # Assignment
      transition :assign, from: [:standard, :high_priority], to: :in_progress
      transition :assign, from: :escalated, to: :in_progress

      # Escalation from in_progress
      transition :escalate, from: :in_progress, to: :escalated

      # Resolution
      transition :resolve, from: [:in_progress, :escalated], to: :resolved

      # Closing
      transition :close, from: :resolved, to: :closed

      # Reopening
      transition :reopen, from: [:resolved, :closed], to: :in_progress
    end
  end

  actions do
    default_accept :*
    defaults [:read, :create]

    update :triage do
      require_atomic? false
    end

    update :assign do
      accept [:assigned_to]
    end

    update :escalate
    update :resolve
    update :close
    update :reopen
  end

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string, public?: true
    attribute :description, :string, public?: true
    attribute :priority, :integer, default: 1, public?: true
    attribute :assigned_to, :string, public?: true
  end

  code_interface do
    define :create
    define :triage
    define :assign
    define :escalate
    define :resolve
    define :close
    define :reopen
  end
end
