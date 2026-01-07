# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AutoTransitionMachine do
  @moduledoc """
  Test resource demonstrating auto-generated actions from transitions.

  This resource only defines transitions - no actions block needed!
  The InjectStateTransitions transformer will generate the actions.
  """
  use Ash.Resource,
    domain: Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshStateMachine]

  state_machine do
    initial_states [:pending]
    default_initial_state :pending

    transitions do
      transition(:approve, from: :pending, to: :approved)
      transition(:reject, from: :pending, to: :rejected)
      transition(:archive, from: [:approved, :rejected], to: :archived)
    end
  end

  actions do
    default_accept :*
    defaults [:read, :create]
    # Note: No update actions defined - they will be auto-generated!
  end

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
  end

  code_interface do
    define :create
    define :approve
    define :reject
    define :archive
  end
end
