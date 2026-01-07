# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AutoInjectMachine do
  @moduledoc """
  Test resource demonstrating auto-injection into existing actions.

  This resource defines actions without transition_state changes.
  The InjectStateTransitions transformer will inject the transitions.
  """
  use Ash.Resource,
    domain: Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshStateMachine]

  state_machine do
    initial_states [:pending]
    default_initial_state :pending

    transitions do
      transition(:start, from: :pending, to: :running)
      transition(:complete, from: :running, to: :completed)
      transition(:fail, from: :running, to: :failed)
    end
  end

  actions do
    default_accept :*
    defaults [:read, :create]

    # Actions defined without transition_state - will be auto-injected
    update :start do
      # Custom logic can go here, transition will be auto-added
      argument :started_by, :string
    end

    update :complete do
      argument :completed_at, :utc_datetime_usec
    end

    update :fail do
      argument :reason, :string
    end
  end

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
  end

  code_interface do
    define :create
    define :start, args: [:started_by]
    define :complete, args: [:completed_at]
    define :fail, args: [:reason]
  end
end
