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
            transition(:handle_complete, from: :active, to: :done)
          end

          parallel_regions do
            parallel_region :active, :done do
              completion_strategy(:all)
              on_complete(:handle_complete)

              region(:test_region, TestRegionMachine)
            end
          end
        end

        actions do
          default_accept(:*)
          defaults([:read, :create])

          update :start do
            change(transition_state(:active))
          end

          update :handle_complete do
            argument(:exit_state, :atom)
            argument(:region_states, :map)
            change(transition_state(:done))
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
                transition(:handle_complete, from: :active, to: :done)
              end

              parallel_regions do
                parallel_region :active, :done do
                  completion_strategy(:all)
                  on_complete(:handle_complete)

                  region(:invalid, NonStateMachineResource)
                end
              end
            end

            actions do
              default_accept(:*)
              defaults([:read, :create])

              update :start do
                change(transition_state(:active))
              end

              update :handle_complete do
                argument(:exit_state, :atom)
                argument(:region_states, :map)
                change(transition_state(:done))
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
            transition(:handle_complete, from: :active, to: :done)
          end

          parallel_regions do
            parallel_region :active, :done do
              completion_strategy(:all)
              on_complete(:handle_complete)

              region(:payment, RelRegionMachine)
              region(:inventory, RelRegionMachine)
            end
          end
        end

        actions do
          default_accept(:*)
          defaults([:read, :create])

          update :start do
            change(transition_state(:active))
          end

          update :handle_complete do
            argument(:exit_state, :atom)
            argument(:region_states, :map)
            change(transition_state(:done))
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
    test "state_machine_parallel_regions/1 returns parallel region groups" do
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
            transition(:handle_complete, from: :active, to: :done)
          end

          parallel_regions do
            parallel_region :active, :done do
              completion_strategy(:all)
              on_complete(:handle_complete)

              region(:payment, InfoTestRegionMachine)
              region(:inventory, InfoTestRegionMachine)
            end
          end
        end

        actions do
          default_accept(:*)
          defaults([:read, :create])

          update :start do
            change(transition_state(:active))
          end

          update :handle_complete do
            argument(:exit_state, :atom)
            argument(:region_states, :map)
            change(transition_state(:done))
          end
        end

        attributes do
          uuid_primary_key(:id)
        end
      end

      parallel_regions =
        AshStateMachine.Info.state_machine_parallel_regions(InfoTestParallelResource)

      assert is_list(parallel_regions)
      assert length(parallel_regions) == 1

      parallel_region = hd(parallel_regions)
      assert parallel_region.enter_state == :active
      assert parallel_region.exit_state == :done
      assert parallel_region.completion_strategy == :all
      assert length(parallel_region.regions) == 2

      region_names = Enum.map(parallel_region.regions, & &1.name)
      assert :payment in region_names
      assert :inventory in region_names
    end

    test "completion_strategy is per-group" do
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
            transition(:handle_complete, from: :active, to: :done)
          end

          parallel_regions do
            parallel_region :active, :done do
              completion_strategy({:require_n, 1})
              on_complete(:handle_complete)

              region(:required, StrategyTestRegionMachine)
              region(:optional, StrategyTestRegionMachine)
            end
          end
        end

        actions do
          default_accept(:*)
          defaults([:read, :create])

          update :start do
            change(transition_state(:active))
          end

          update :handle_complete do
            argument(:exit_state, :atom)
            argument(:region_states, :map)
            change(transition_state(:done))
          end
        end

        attributes do
          uuid_primary_key(:id)
        end
      end

      parallel_regions =
        AshStateMachine.Info.state_machine_parallel_regions(StrategyTestParallelResource)

      parallel_region = hd(parallel_regions)
      assert parallel_region.completion_strategy == {:require_n, 1}
    end

    test "state_machine_regions_for_state/2 returns regions for enter_state" do
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
            transition(:handle_processing_complete, from: :processing, to: :done)
            transition(:handle_shipping_complete, from: :shipping, to: :delivered)
          end

          parallel_regions do
            parallel_region :processing, :done do
              completion_strategy(:all)
              on_complete(:handle_processing_complete)

              region(:payment, ActivateTestRegionMachine)
              region(:inventory, ActivateTestRegionMachine)
            end

            parallel_region :shipping, :delivered do
              completion_strategy(:all)
              on_complete(:handle_shipping_complete)

              region(:tracking, ActivateTestRegionMachine)
            end
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

          update :handle_processing_complete do
            argument(:exit_state, :atom)
            argument(:region_states, :map)
            change(transition_state(:done))
          end

          update :handle_shipping_complete do
            argument(:exit_state, :atom)
            argument(:region_states, :map)
            change(transition_state(:delivered))
          end
        end

        attributes do
          uuid_primary_key(:id)
        end
      end

      processing_regions =
        AshStateMachine.Info.state_machine_regions_for_state(
          ActivateTestParallelResource,
          :processing
        )

      shipping_regions =
        AshStateMachine.Info.state_machine_regions_for_state(
          ActivateTestParallelResource,
          :shipping
        )

      pending_regions =
        AshStateMachine.Info.state_machine_regions_for_state(
          ActivateTestParallelResource,
          :pending
        )

      assert length(processing_regions) == 2
      assert Enum.map(processing_regions, & &1.name) |> Enum.sort() == [:inventory, :payment]

      assert length(shipping_regions) == 1
      assert hd(shipping_regions).name == :tracking

      assert length(pending_regions) == 0
    end

    test "state_machine_parallel_region_for_state/2 returns the parallel region group" do
      defmodule GroupTestRegionMachine do
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

      defmodule GroupTestParallelResource do
        @moduledoc false
        use Ash.Resource,
          domain: nil,
          extensions: [AshStateMachine]

        state_machine do
          initial_states([:pending])
          default_initial_state(:pending)

          transitions do
            transition(:start, from: :pending, to: :active)
            transition(:handle_complete, from: :active, to: :done)
          end

          parallel_regions do
            parallel_region :active, :done do
              completion_strategy(:any)
              on_complete(:handle_complete)

              region(:worker_a, GroupTestRegionMachine)
              region(:worker_b, GroupTestRegionMachine)
            end
          end
        end

        actions do
          default_accept(:*)
          defaults([:read, :create])

          update :start do
            change(transition_state(:active))
          end

          update :handle_complete do
            argument(:exit_state, :atom)
            argument(:region_states, :map)
            change(transition_state(:done))
          end
        end

        attributes do
          uuid_primary_key(:id)
        end
      end

      parallel_region =
        AshStateMachine.Info.state_machine_parallel_region_for_state(
          GroupTestParallelResource,
          :active
        )

      assert parallel_region != nil
      assert parallel_region.enter_state == :active
      assert parallel_region.exit_state == :done
      assert parallel_region.completion_strategy == :any
      assert parallel_region.on_complete == :handle_complete

      # No parallel region for :pending state
      assert AshStateMachine.Info.state_machine_parallel_region_for_state(
               GroupTestParallelResource,
               :pending
             ) == nil
    end
  end
end
