# SPDX-FileCopyrightText: 2026 ash_state_machine contributors <https://github.com/ash-project/ash_state_machine/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule DynamicLineItemMachine do
  @moduledoc false
  use Ash.Resource,
    domain: Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshStateMachine]

  state_machine do
    initial_states([:pending])
    default_initial_state(:pending)
    failure_states([:failed])

    transitions do
      transition(:start, from: :pending, to: :processing)
      transition(:succeed, from: [:pending, :processing], to: :succeeded)
      transition(:fail, from: [:pending, :processing], to: :failed)
    end
  end

  actions do
    default_accept(:*)
    defaults([:read, :destroy])

    create :create do
      accept([:parent_id, :name])
    end

    update :start do
      change(transition_state(:processing))
    end

    update :succeed do
      change(transition_state(:succeeded))
    end

    update :fail do
      change(transition_state(:failed))
    end
  end

  code_interface do
    define(:create)
    define(:start)
    define(:succeed)
    define(:fail)
  end

  ets do
    private?(true)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:parent_id, :uuid, allow_nil?: false, public?: true)
    attribute(:name, :string, allow_nil?: false, public?: true)
  end
end

defmodule DynamicParallelOrder do
  @moduledoc false
  use Ash.Resource,
    domain: Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshStateMachine]

  state_machine do
    initial_states([:pending])
    default_initial_state(:pending)

    transitions do
      transition(:start_all, from: :pending, to: :all_processing, require_atomic?: false)
      transition(:finish_all, from: :all_processing, to: :all_done, require_atomic?: false)

      transition(:start_any, from: :pending, to: :any_processing, require_atomic?: false)
      transition(:finish_any, from: :any_processing, to: :any_done, require_atomic?: false)

      transition(:start_require_two,
        from: :pending,
        to: :require_two_processing,
        require_atomic?: false
      )

      transition(:finish_require_two,
        from: :require_two_processing,
        to: :require_two_done,
        require_atomic?: false
      )

      transition(:start_require_three,
        from: :pending,
        to: :require_three_processing,
        require_atomic?: false
      )

      transition(:finish_require_three,
        from: :require_three_processing,
        to: :require_three_done,
        require_atomic?: false
      )
    end

    parallel_regions do
      parallel_region :all_processing, :all_done do
        completion_strategy(:all)
        region(:line_items, relationship: :line_items)
      end

      parallel_region :any_processing, :any_done do
        completion_strategy(:any)
        region(:line_items, relationship: :line_items)
      end

      parallel_region :require_two_processing, :require_two_done do
        completion_strategy({:require_n, 2})
        region(:line_items, relationship: :line_items)
      end

      parallel_region :require_three_processing, :require_three_done do
        completion_strategy({:require_n, 3})
        region(:line_items, relationship: :line_items)
      end
    end
  end

  relationships do
    has_many(:line_items, DynamicLineItemMachine,
      destination_attribute: :parent_id,
      public?: true
    )
  end

  actions do
    default_accept(:*)
    defaults([:read, :destroy])
  end

  code_interface do
    define(:create)
    define(:start_all)
    define(:start_any)
    define(:start_require_two)
    define(:start_require_three)
  end

  ets do
    private?(true)
  end

  attributes do
    uuid_primary_key(:id)
  end
end
