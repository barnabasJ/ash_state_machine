# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshStateMachine.ParallelStatesTest do
  use ExUnit.Case

  describe "parallel_region entity" do
    test "compiles without error when parallel_regions defined" do
      defmodule TestRegionMachine do
        @moduledoc false
        use Ash.Resource,
          domain: nil,
          extensions: [AshStateMachine]

        state_machine do
          initial_states([:pending])
          default_initial_state(:pending)

          transitions do
            transition(:complete, from: :pending, to: :complete)
          end
        end

        actions do
          default_accept(:*)
          defaults([:read, :create])

          update :complete do
            change(transition_state(:complete))
          end
        end

        attributes do
          uuid_primary_key(:id)
          attribute :parent_id, :uuid, public?: true
        end
      end

      defmodule TestParallelResource do
        @moduledoc false
        use Ash.Resource,
          domain: nil,
          extensions: [AshStateMachine]

        state_machine do
          initial_states([:pending])
          default_initial_state(:pending)

          transitions do
            transition(:start, from: :pending, to: :active)
          end

          parallel_regions do
            region(:test_region, TestRegionMachine, activate_on: :active)
          end
        end

        actions do
          default_accept(:*)
          defaults([:read, :create])

          update :start do
            change(transition_state(:active))
          end
        end

        attributes do
          uuid_primary_key(:id)
        end
      end

      # Verify the resource compiled successfully
      assert TestParallelResource.__info__(:module) == TestParallelResource
    end
  end

  describe "parallel region verification" do
    import ExUnit.CaptureIO

    test "warns when region resource doesn't use AshStateMachine" do
      # First define a non-state-machine resource
      defmodule NonStateMachineResource do
        @moduledoc false
        use Ash.Resource,
          domain: nil

        actions do
          default_accept(:*)
          defaults([:read, :create])
        end

        attributes do
          uuid_primary_key(:id)
          attribute :parent_id, :uuid, public?: true
        end
      end

      # This should produce an error at compile time (logged to stderr)
      result =
        capture_io(:stderr, fn ->
          defmodule InvalidParallelResource do
            @moduledoc false
            use Ash.Resource,
              domain: nil,
              extensions: [AshStateMachine]

            state_machine do
              initial_states([:pending])
              default_initial_state(:pending)

              transitions do
                transition(:start, from: :pending, to: :active)
              end

              parallel_regions do
                region(:invalid, NonStateMachineResource, activate_on: :active)
              end
            end

            actions do
              default_accept(:*)
              defaults([:read, :create])

              update :start do
                change(transition_state(:active))
              end
            end

            attributes do
              uuid_primary_key(:id)
            end
          end
        end)

      assert result =~ ~r/must use AshStateMachine/i
    end
  end

  describe "parallel region relationships" do
    test "parent has has_one relationship to each region (when parent_id attribute exists)" do
      defmodule RelRegionMachine do
        @moduledoc false
        use Ash.Resource,
          domain: nil,
          extensions: [AshStateMachine]

        state_machine do
          initial_states([:pending])
          default_initial_state(:pending)

          transitions do
            transition(:complete, from: :pending, to: :complete)
          end
        end

        actions do
          default_accept(:*)
          defaults([:read, :create])

          update :complete do
            change(transition_state(:complete))
          end
        end

        attributes do
          uuid_primary_key(:id)
          # This attribute allows the has_one relationship to work
          attribute :parent_id, :uuid, public?: true
        end
      end

      defmodule RelParentResource do
        @moduledoc false
        use Ash.Resource,
          domain: nil,
          extensions: [AshStateMachine]

        state_machine do
          initial_states([:pending])
          default_initial_state(:pending)

          transitions do
            transition(:start, from: :pending, to: :active)
          end

          parallel_regions do
            region(:payment, RelRegionMachine, activate_on: :active)
            region(:inventory, RelRegionMachine, activate_on: :active)
          end
        end

        actions do
          default_accept(:*)
          defaults([:read, :create])

          update :start do
            change(transition_state(:active))
          end
        end

        attributes do
          uuid_primary_key(:id)
        end
      end

      # Check that parent has relationships to each region
      relationships = Ash.Resource.Info.relationships(RelParentResource)
      payment_rel = Enum.find(relationships, &(&1.name == :payment))
      inventory_rel = Enum.find(relationships, &(&1.name == :inventory))

      assert payment_rel != nil, "Expected :payment relationship to exist"
      assert payment_rel.type == :has_one
      assert payment_rel.destination == RelRegionMachine

      assert inventory_rel != nil, "Expected :inventory relationship to exist"
      assert inventory_rel.type == :has_one
      assert inventory_rel.destination == RelRegionMachine
    end
  end

  describe "Info module" do
    test "state_machine_parallel_regions/1 returns regions" do
      defmodule InfoTestRegionMachine do
        @moduledoc false
        use Ash.Resource,
          domain: nil,
          extensions: [AshStateMachine]

        state_machine do
          initial_states([:pending])
          default_initial_state(:pending)

          transitions do
            transition(:complete, from: :pending, to: :complete)
          end
        end

        actions do
          default_accept(:*)
          defaults([:read, :create])

          update :complete do
            change(transition_state(:complete))
          end
        end

        attributes do
          uuid_primary_key(:id)
          attribute :parent_id, :uuid, public?: true
        end
      end

      defmodule InfoTestParallelResource do
        @moduledoc false
        use Ash.Resource,
          domain: nil,
          extensions: [AshStateMachine]

        state_machine do
          initial_states([:pending])
          default_initial_state(:pending)

          transitions do
            transition(:start, from: :pending, to: :active)
          end

          parallel_regions do
            region(:payment, InfoTestRegionMachine, activate_on: :active)
            region(:inventory, InfoTestRegionMachine, activate_on: :active)
          end
        end

        actions do
          default_accept(:*)
          defaults([:read, :create])

          update :start do
            change(transition_state(:active))
          end
        end

        attributes do
          uuid_primary_key(:id)
        end
      end

      regions = AshStateMachine.Info.state_machine_parallel_regions(InfoTestParallelResource)
      assert is_list(regions)
      assert length(regions) == 2

      region_names = Enum.map(regions, & &1.name)
      assert :payment in region_names
      assert :inventory in region_names
    end

    test "region completion_strategy is per-region" do
      defmodule StrategyTestRegionMachine do
        @moduledoc false
        use Ash.Resource,
          domain: nil,
          extensions: [AshStateMachine]

        state_machine do
          initial_states([:pending])
          default_initial_state(:pending)

          transitions do
            transition(:complete, from: :pending, to: :complete)
          end
        end

        actions do
          default_accept(:*)
          defaults([:read, :create])

          update :complete do
            change(transition_state(:complete))
          end
        end

        attributes do
          uuid_primary_key(:id)
          attribute :parent_id, :uuid, public?: true
        end
      end

      defmodule StrategyTestParallelResource do
        @moduledoc false
        use Ash.Resource,
          domain: nil,
          extensions: [AshStateMachine]

        state_machine do
          initial_states([:pending])
          default_initial_state(:pending)

          transitions do
            transition(:start, from: :pending, to: :active)
          end

          parallel_regions do
            region(:required, StrategyTestRegionMachine,
              activate_on: :active,
              completion_strategy: :require_all
            )

            region(:optional, StrategyTestRegionMachine,
              activate_on: :active,
              completion_strategy: :allow_partial
            )
          end
        end

        actions do
          default_accept(:*)
          defaults([:read, :create])

          update :start do
            change(transition_state(:active))
          end
        end

        attributes do
          uuid_primary_key(:id)
        end
      end

      regions = AshStateMachine.Info.state_machine_parallel_regions(StrategyTestParallelResource)
      required_region = Enum.find(regions, &(&1.name == :required))
      optional_region = Enum.find(regions, &(&1.name == :optional))

      assert required_region.completion_strategy == :require_all
      assert optional_region.completion_strategy == :allow_partial
    end

    test "state_machine_parallel_regions_for_state/2 filters by activation state" do
      defmodule ActivateTestRegionMachine do
        @moduledoc false
        use Ash.Resource,
          domain: nil,
          extensions: [AshStateMachine]

        state_machine do
          initial_states([:pending])
          default_initial_state(:pending)

          transitions do
            transition(:complete, from: :pending, to: :complete)
          end
        end

        actions do
          default_accept(:*)
          defaults([:read, :create])

          update :complete do
            change(transition_state(:complete))
          end
        end

        attributes do
          uuid_primary_key(:id)
          attribute :parent_id, :uuid, public?: true
        end
      end

      defmodule ActivateTestParallelResource do
        @moduledoc false
        use Ash.Resource,
          domain: nil,
          extensions: [AshStateMachine]

        state_machine do
          initial_states([:pending])
          default_initial_state(:pending)

          transitions do
            transition(:start, from: :pending, to: :processing)
            transition(:ship, from: :processing, to: :shipping)
          end

          parallel_regions do
            region(:payment, ActivateTestRegionMachine, activate_on: :processing)
            region(:inventory, ActivateTestRegionMachine, activate_on: :processing)
            region(:tracking, ActivateTestRegionMachine, activate_on: :shipping)
          end
        end

        actions do
          default_accept(:*)
          defaults([:read, :create])

          update :start do
            change(transition_state(:processing))
          end

          update :ship do
            change(transition_state(:shipping))
          end
        end

        attributes do
          uuid_primary_key(:id)
        end
      end

      processing_regions =
        AshStateMachine.Info.state_machine_parallel_regions_for_state(
          ActivateTestParallelResource,
          :processing
        )

      shipping_regions =
        AshStateMachine.Info.state_machine_parallel_regions_for_state(
          ActivateTestParallelResource,
          :shipping
        )

      pending_regions =
        AshStateMachine.Info.state_machine_parallel_regions_for_state(
          ActivateTestParallelResource,
          :pending
        )

      assert length(processing_regions) == 2
      assert Enum.map(processing_regions, & &1.name) |> Enum.sort() == [:inventory, :payment]

      assert length(shipping_regions) == 1
      assert hd(shipping_regions).name == :tracking

      assert length(pending_regions) == 0
    end
  end
end
