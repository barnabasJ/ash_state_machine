# Phase 1: Parallel States - Detailed Task Breakdown

**Date:** 2025-12-06 **Timeline:** 3-4 weeks **Goal:** Enable parallel regions
with nested resources in ash_state_machine

---

## Sprint 1: DSL Foundation (Week 1)

### Task 1.1: Create ParallelRegion Entity

**File:** `lib/dsl/entities/parallel_region.ex`

**Description:** Define the Spark DSL entity for representing a parallel region.

**Acceptance Criteria:**

- [ ] Entity struct with all required fields
- [ ] Schema validation for all options
- [ ] Type specs for all fields
- [ ] Documentation with examples

**Implementation:**

```elixir
defmodule AshStateMachine.Dsl.Entities.ParallelRegion do
  @moduledoc """
  Defines a parallel region that executes concurrently with other regions.

  A parallel region is a separate Ash resource with its own state machine
  that executes in parallel with sibling regions.

  ## Options

  - `:name` (atom, required) - Unique identifier for this region
  - `:resource` (module, required) - Ash resource module for this region
  - `:relationship` (atom, required) - Relationship name on parent resource
  - `:terminal_success_states` (list of atoms, required) - States indicating successful completion
  - `:terminal_failure_states` (list of atoms, optional) - States indicating failure
  - `:queue` (atom, optional) - Oban queue for this region's jobs
  - `:timeout_seconds` (integer, optional) - Timeout for region execution

  ## Examples

      region :payment do
        resource MyApp.PaymentStep
        relationship :payment_steps
        terminal_success_states [:completed]
        terminal_failure_states [:failed, :cancelled]
        queue :payment_processing
      end
  """

  @type t :: %__MODULE__{
          name: atom(),
          resource: module(),
          relationship: atom(),
          terminal_success_states: [atom()],
          terminal_failure_states: [atom()],
          queue: atom() | nil,
          timeout_seconds: pos_integer() | nil
        }

  defstruct [
    :name,
    :resource,
    :relationship,
    :terminal_success_states,
    :terminal_failure_states,
    :queue,
    :timeout_seconds,
    :__spark_metadata__
  ]

  def schema do
    [
      name: [
        type: :atom,
        required: true,
        doc: "Unique identifier for this parallel region"
      ],
      resource: [
        type: :atom,
        required: true,
        doc: "Ash resource module for this region's state machine"
      ],
      relationship: [
        type: :atom,
        required: true,
        doc: "Name of the has_many relationship on the parent resource"
      ],
      terminal_success_states: [
        type: {:list, :atom},
        required: true,
        doc: "States indicating this region has completed successfully"
      ],
      terminal_failure_states: [
        type: {:list, :atom},
        required: false,
        default: [],
        doc: "States indicating this region has failed"
      ],
      queue: [
        type: :atom,
        required: false,
        doc: "Oban queue for jobs in this region"
      ],
      timeout_seconds: [
        type: :pos_integer,
        required: false,
        doc: "Timeout in seconds for this region's execution"
      ]
    ]
  end

  def args, do: [:name]
  def target, do: __MODULE__
end
```

**Tests:** `test/dsl/entities/parallel_region_test.exs`

```elixir
defmodule AshStateMachine.Dsl.Entities.ParallelRegionTest do
  use ExUnit.Case

  alias AshStateMachine.Dsl.Entities.ParallelRegion

  describe "schema validation" do
    test "requires name, resource, relationship, and terminal_success_states" do
      assert {:error, _} = build_region([])
      assert {:error, _} = build_region(name: :payment)
      assert {:error, _} = build_region(name: :payment, resource: MyApp.Payment)

      assert {:ok, region} =
               build_region(
                 name: :payment,
                 resource: MyApp.Payment,
                 relationship: :payment_steps,
                 terminal_success_states: [:completed]
               )

      assert region.name == :payment
      assert region.resource == MyApp.Payment
      assert region.terminal_failure_states == []
    end

    test "accepts optional fields" do
      assert {:ok, region} =
               build_region(
                 name: :payment,
                 resource: MyApp.Payment,
                 relationship: :payment_steps,
                 terminal_success_states: [:completed],
                 terminal_failure_states: [:failed],
                 queue: :payment_queue,
                 timeout_seconds: 300
               )

      assert region.terminal_failure_states == [:failed]
      assert region.queue == :payment_queue
      assert region.timeout_seconds == 300
    end
  end

  defp build_region(opts) do
    Spark.Dsl.Transformer.build_entity(
      AshStateMachine,
      [:state_machine, :parallel_regions],
      :region,
      opts
    )
  end
end
```

**Estimated Time:** 4 hours

---

### Task 1.2: Create ParallelRegions Section

**File:** `lib/dsl/sections/parallel_regions.ex`

**Description:** Define the DSL section that contains parallel region
definitions.

**Acceptance Criteria:**

- [ ] Section schema with all options
- [ ] Support for multiple region entities
- [ ] Completion strategy configuration
- [ ] on_complete and on_failure callbacks

**Implementation:**

```elixir
defmodule AshStateMachine.Dsl.Sections.ParallelRegions do
  @moduledoc """
  Defines parallel regions for a state machine.

  Parallel regions are independent state machines that execute concurrently.
  The parent state machine coordinates completion based on the configured strategy.

  ## Options

  - `:completion_strategy` - How to determine when parallel execution completes
    - `:require_all` (default) - All regions must succeed
    - `:allow_partial` - Proceed when all reach terminal states (success or failure)
    - `{:require_n, count}` - Proceed when N regions succeed

  - `:on_complete` (atom, required) - Action to call when strategy is satisfied
  - `:on_failure` (atom, optional) - Action to call when strategy fails

  ## Examples

      parallel_regions do
        region :payment do
          resource MyApp.PaymentStep
          relationship :payment_steps
          terminal_success_states [:completed]
        end

        region :inventory do
          resource MyApp.InventoryStep
          relationship :inventory_steps
          terminal_success_states [:packed]
        end

        completion_strategy :require_all
        on_complete :advance_to_shipping
        on_failure :advance_to_failed
      end
  """

  use Spark.Dsl.Section,
    top_level?: false

  @type completion_strategy :: :require_all | :allow_partial | {:require_n, pos_integer()}

  def schema do
    [
      completion_strategy: [
        type: {:or, [:atom, {:tuple, [:atom, :pos_integer]}]},
        required: false,
        default: :require_all,
        doc: """
        Strategy for determining when parallel regions complete.
        - `:require_all` - All regions must reach success states
        - `:allow_partial` - Proceed when all reach any terminal state
        - `{:require_n, count}` - Proceed when N regions succeed
        """
      ],
      on_complete: [
        type: :atom,
        required: true,
        doc: "Action to transition to when completion strategy is satisfied"
      ],
      on_failure: [
        type: :atom,
        required: false,
        doc: "Action to transition to when completion strategy fails"
      ]
    ]
  end

  def entities do
    [
      region: AshStateMachine.Dsl.Entities.ParallelRegion
    ]
  end
end
```

**Tests:** `test/dsl/sections/parallel_regions_test.exs`

**Estimated Time:** 3 hours

---

### Task 1.3: Integrate ParallelRegions into StateMachine Section

**File:** `lib/ash_state_machine.ex`

**Description:** Add parallel_regions as a nested section within state_machine.

**Acceptance Criteria:**

- [ ] parallel_regions section available in state_machine DSL
- [ ] Can define multiple parallel regions
- [ ] DSL compiles without errors
- [ ] Cheat sheet documentation generated

**Implementation:**

```elixir
# In lib/ash_state_machine.ex

sections do
  # ... existing sections ...

  section :state_machine do
    # ... existing options ...

    sections do
      # ... transitions section ...

      section :parallel_regions,
        AshStateMachine.Dsl.Sections.ParallelRegions
    end
  end
end
```

**Tests:** Integration test with full DSL definition

**Estimated Time:** 2 hours

---

### Task 1.4: Create Test Support Resource

**File:** `test/support/resources/order.ex`

**Description:** Create example Order resource for testing parallel regions.

**Acceptance Criteria:**

- [ ] Order resource with state machine
- [ ] PaymentStep and InventoryStep region resources
- [ ] Relationships defined
- [ ] Can be used in integration tests

**Implementation:**

```elixir
defmodule AshStateMachine.Test.Order do
  use Ash.Resource,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshStateMachine]

  attributes do
    uuid_primary_key :id

    attribute :state, :atom do
      constraints one_of: [:pending, :processing, :completed, :failed]
      default :pending
      allow_nil? false
    end

    attribute :total, :decimal
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :payment_steps, AshStateMachine.Test.PaymentStep
    has_many :inventory_steps, AshStateMachine.Test.InventoryStep
  end

  state_machine do
    initial_states [:pending]
    default_initial_state :pending
    state_attribute :state

    parallel_regions do
      region :payment do
        resource AshStateMachine.Test.PaymentStep
        relationship :payment_steps
        terminal_success_states [:completed]
        terminal_failure_states [:failed]
      end

      region :inventory do
        resource AshStateMachine.Test.InventoryStep
        relationship :inventory_steps
        terminal_success_states [:packed]
        terminal_failure_states [:failed]
      end

      completion_strategy :require_all
      on_complete :advance_to_completed
      on_failure :advance_to_failed
    end

    transitions do
      transition :start_processing, from: :pending, to: :processing
      transition :advance_to_completed, from: :processing, to: :completed
      transition :advance_to_failed, from: :processing, to: :failed
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:total]
    end

    update :start_processing do
      change transition_state(:processing)
    end

    update :advance_to_completed do
      change transition_state(:completed)
    end

    update :advance_to_failed do
      change transition_state(:failed)
    end
  end

  code_interface do
    define_for AshStateMachine.Test.Api
    define :create
    define :start_processing
  end
end
```

**Also create:** `PaymentStep.ex` and `InventoryStep.ex`

**Estimated Time:** 4 hours

---

## Sprint 2: Coordination Logic (Week 2)

### Task 2.1: Implement ParallelCoordinator Module

**File:** `lib/parallel_coordinator.ex`

**Description:** Core logic for checking parallel region completion.

**Acceptance Criteria:**

- [ ] check_completion/3 function with all strategies
- [ ] Handles concurrent updates safely
- [ ] Comprehensive error handling
- [ ] Telemetry events emitted

**Implementation:**

```elixir
defmodule AshStateMachine.ParallelCoordinator do
  @moduledoc """
  Coordinates completion of parallel region resources.

  Checks if parallel regions meet the configured completion strategy
  and determines when the parent resource should transition.
  """

  require Logger

  @type strategy :: :require_all | :allow_partial | {:require_n, pos_integer()}
  @type completion_result :: {:ok, :complete} | {:ok, :pending} | {:error, term()}

  @doc """
  Checks if parallel regions meet completion criteria.

  ## Parameters
  - `parent` - The parent resource instance
  - `region_definitions` - List of ParallelRegion entities from DSL
  - `strategy` - Completion strategy

  ## Returns
  - `{:ok, :complete}` - Ready to transition parent
  - `{:ok, :pending}` - Still waiting for regions
  - `{:error, reason}` - Failed permanently

  ## Examples

      iex> check_completion(order, regions, :require_all)
      {:ok, :complete}

      iex> check_completion(order, regions, {:require_n, 2})
      {:ok, :pending}
  """
  @spec check_completion(Ash.Resource.record(), [map()], strategy()) :: completion_result()
  def check_completion(parent, region_definitions, strategy) do
    :telemetry.span(
      [:ash_state_machine, :parallel_coordination, :check],
      %{parent_id: parent.id, strategy: strategy},
      fn ->
        result = do_check_completion(parent, region_definitions, strategy)
        {result, %{result: result}}
      end
    )
  end

  defp do_check_completion(parent, region_definitions, strategy) do
    region_states = fetch_region_states(parent, region_definitions)

    case strategy do
      :require_all ->
        check_require_all(region_states, region_definitions)

      :allow_partial ->
        check_allow_partial(region_states, region_definitions)

      {:require_n, n} ->
        check_require_n(region_states, region_definitions, n)
    end
  end

  defp check_require_all(region_states, region_definitions) do
    completed = count_successful(region_states, region_definitions)
    failed = count_failed(region_states, region_definitions)
    total = length(region_states)

    cond do
      completed == total and total > 0 ->
        {:ok, :complete}

      failed > 0 ->
        {:error, :region_failed}

      total == 0 ->
        {:error, :no_regions}

      true ->
        {:ok, :pending}
    end
  end

  defp check_allow_partial(region_states, region_definitions) do
    all_terminal = Enum.all?(region_states, fn state ->
      terminal_state?(state, find_region_def(region_definitions, state))
    end)

    if all_terminal and length(region_states) > 0 do
      {:ok, :complete}
    else
      {:ok, :pending}
    end
  end

  defp check_require_n(region_states, region_definitions, n) do
    completed = count_successful(region_states, region_definitions)
    failed = count_failed(region_states, region_definitions)
    total = length(region_states)

    cond do
      completed >= n ->
        {:ok, :complete}

      # Not enough regions can succeed
      total - failed < n ->
        {:error, :insufficient_completions}

      total < n ->
        {:error, :not_enough_regions}

      true ->
        {:ok, :pending}
    end
  end

  defp fetch_region_states(parent, region_definitions) do
    Enum.flat_map(region_definitions, fn region ->
      case Ash.load(parent, region.relationship) do
        {:ok, loaded} ->
          Map.get(loaded, region.relationship, [])

        {:error, error} ->
          Logger.error("Failed to load region #{region.name}: #{inspect(error)}")
          []
      end
    end)
  end

  defp count_successful(region_states, region_definitions) do
    Enum.count(region_states, fn state ->
      region_def = find_region_def(region_definitions, state)
      terminal_success?(state, region_def)
    end)
  end

  defp count_failed(region_states, region_definitions) do
    Enum.count(region_states, fn state ->
      region_def = find_region_def(region_definitions, state)
      terminal_failure?(state, region_def)
    end)
  end

  defp terminal_success?(region_state, region_def) do
    region_state.state in region_def.terminal_success_states
  end

  defp terminal_failure?(region_state, region_def) do
    region_state.state in (region_def.terminal_failure_states || [])
  end

  defp terminal_state?(region_state, region_def) do
    terminal_success?(region_state, region_def) or
      terminal_failure?(region_state, region_def)
  end

  defp find_region_def(region_definitions, region_state) do
    # Match by relationship - the region_state came from that relationship
    # This is a simplification - might need more robust matching
    Enum.find(region_definitions, fn def ->
      # We'd need to store metadata on region_state to match it to def
      # For now, assume order matches
      true
    end)
  end
end
```

**Tests:** `test/parallel_coordinator_test.exs`

```elixir
defmodule AshStateMachine.ParallelCoordinatorTest do
  use ExUnit.Case

  alias AshStateMachine.ParallelCoordinator

  describe "check_completion/3 with :require_all" do
    test "returns :complete when all regions in success state" do
      parent = %{id: 1}

      region_defs = [
        %{name: :payment, terminal_success_states: [:completed]},
        %{name: :inventory, terminal_success_states: [:packed]}
      ]

      # Mock region states - both completed
      # ... setup test data ...

      assert {:ok, :complete} =
               ParallelCoordinator.check_completion(parent, region_defs, :require_all)
    end

    test "returns :pending when some regions incomplete" do
      # ... test pending state ...
    end

    test "returns :error when any region failed" do
      # ... test failure case ...
    end
  end

  describe "check_completion/3 with :allow_partial" do
    # ... tests for allow_partial ...
  end

  describe "check_completion/3 with {:require_n, n}" do
    # ... tests for require_n ...
  end
end
```

**Estimated Time:** 8 hours

---

### Task 2.2: Create CheckParallelCompletion Change

**File:** `lib/changes/check_parallel_completion.ex`

**Description:** Ash change module that checks parallel completion after region
state updates.

**Acceptance Criteria:**

- [ ] Runs after region transitions to terminal state
- [ ] Calls ParallelCoordinator.check_completion/3
- [ ] Transitions parent if strategy satisfied
- [ ] Handles errors gracefully
- [ ] Only runs for resources that are parallel regions

**Implementation:**

```elixir
defmodule AshStateMachine.Changes.CheckParallelCompletion do
  @moduledoc """
  Checks if parent resource should transition after a parallel region completes.

  This change is automatically injected into parallel region resources
  by the InjectParallelCompletion transformer.

  When a region transitions to a terminal state, this change:
  1. Loads the parent resource
  2. Checks if completion strategy is satisfied
  3. Transitions parent if ready
  """

  use Ash.Resource.Change

  def change(changeset, _opts, context) do
    # Only run if transitioning to terminal state
    if transitioning_to_terminal?(changeset, context) do
      changeset
      |> Ash.Changeset.after_action(fn _changeset, region_record ->
        check_and_transition_parent(region_record, context)
        {:ok, region_record}
      end)
    else
      changeset
    end
  end

  defp transitioning_to_terminal?(changeset, context) do
    # Get parallel region metadata from context
    # Check if new state is in terminal_success_states or terminal_failure_states
    # ... implementation ...
    true
  end

  defp check_and_transition_parent(region_record, context) do
    with {:ok, parent} <- load_parent(region_record, context),
         {:ok, region_defs} <- get_region_definitions(parent),
         {:ok, strategy} <- get_completion_strategy(parent),
         {:ok, :complete} <-
           AshStateMachine.ParallelCoordinator.check_completion(
             parent,
             region_defs,
             strategy
           ),
         {:ok, on_complete_action} <- get_on_complete_action(parent) do
      # Transition parent
      transition_parent(parent, on_complete_action)
    else
      {:ok, :pending} ->
        # Still waiting for other regions
        :ok

      {:error, reason} ->
        # Handle failure
        handle_completion_failure(region_record, reason, context)
    end
  end

  defp load_parent(region_record, context) do
    # Load parent via belongs_to relationship
    # ... implementation ...
  end

  defp get_region_definitions(parent) do
    # Get parallel_regions from parent's DSL
    # ... implementation ...
  end

  defp get_completion_strategy(parent) do
    # Get completion_strategy from DSL
    # ... implementation ...
  end

  defp get_on_complete_action(parent) do
    # Get on_complete from DSL
    # ... implementation ...
  end

  defp transition_parent(parent, action_name) do
    # Call the on_complete action
    parent
    |> Ash.Changeset.for_update(action_name)
    |> Ash.update()
  end

  defp handle_completion_failure(region_record, reason, context) do
    # Call on_failure action if defined
    # ... implementation ...
  end
end
```

**Tests:** `test/changes/check_parallel_completion_test.exs`

**Estimated Time:** 8 hours

---

## Sprint 3: Transformer (Week 3)

### Task 3.1: Create InjectParallelCompletion Transformer

**File:** `lib/transformers/inject_parallel_completion.ex`

**Description:** Automatically inject CheckParallelCompletion change into region
resources.

**Acceptance Criteria:**

- [ ] Detects which resources are parallel regions
- [ ] Injects change into actions that transition to terminal states
- [ ] Runs in correct transformer order
- [ ] Preserves user-defined changes

**Implementation:**

```elixir
defmodule AshStateMachine.Transformers.InjectParallelCompletion do
  @moduledoc """
  Automatically injects CheckParallelCompletion change into parallel region resources.

  This transformer runs on resources that are referenced as parallel regions
  in a parent resource's state_machine.parallel_regions section.

  It adds the CheckParallelCompletion change to all update actions that
  transition to terminal states (success or failure).
  """

  use Spark.Dsl.Transformer

  def after?(_), do: false

  def before?(AshStateMachine.Transformers.FillInTransitionDefaults), do: true
  def before?(_), do: false

  def transform(dsl_state) do
    # Check if this resource is referenced as a parallel region
    # by any other resource in the system

    if is_parallel_region?(dsl_state) do
      inject_completion_check(dsl_state)
    else
      {:ok, dsl_state}
    end
  end

  defp is_parallel_region?(dsl_state) do
    # This is tricky - we need to check if ANY other resource
    # references this one in their parallel_regions section

    # Approach: Store metadata on the resource module
    # Or: Check all loaded resources (expensive)
    # Or: Require explicit opt-in via an option

    # For now, check if resource has a specific option set
    Spark.Dsl.Transformer.get_option(
      dsl_state,
      [:state_machine],
      :parallel_region_mode
    ) == true
  end

  defp inject_completion_check(dsl_state) do
    # Get all update actions
    actions = Ash.Resource.Info.actions(dsl_state)
    update_actions = Enum.filter(actions, &(&1.type == :update))

    # For each action, check if it transitions to terminal state
    Enum.reduce(update_actions, dsl_state, fn action, acc_state ->
      if transitions_to_terminal?(action, dsl_state) do
        add_completion_check_to_action(acc_state, action.name)
      else
        acc_state
      end
    end)
  end

  defp transitions_to_terminal?(action, dsl_state) do
    # Check transitions for this action
    # See if any transition leads to a terminal state
    # ... implementation ...
    true
  end

  defp add_completion_check_to_action(dsl_state, action_name) do
    # Build change entity
    {:ok, change_struct} =
      Ash.Resource.Builder.build_change(
        {AshStateMachine.Changes.CheckParallelCompletion, []},
        on: [:update],
        only_when_valid?: false,
        description: "Check parallel completion"
      )

    # Add to action
    actions = Ash.Resource.Info.actions(dsl_state)
    action = Enum.find(actions, &(&1.name == action_name))

    updated_action = %{action | changes: action.changes ++ [change_struct]}

    dsl_state
    |> remove_action(action_name)
    |> Spark.Dsl.Transformer.add_entity([:actions], updated_action)
  end

  defp remove_action(dsl_state, action_name) do
    Spark.Dsl.Transformer.remove_entity(dsl_state, [:actions], fn action ->
      action.name == action_name
    end)
  end
end
```

**Tests:** `test/transformers/inject_parallel_completion_test.exs`

**Estimated Time:** 10 hours

---

### Task 3.2: Create ValidateParallelRegions Verifier

**File:** `lib/verifiers/verify_parallel_regions.ex`

**Description:** Validate parallel_regions configuration at compile time.

**Acceptance Criteria:**

- [ ] Verifies relationships exist
- [ ] Verifies terminal states are valid
- [ ] Verifies referenced resources exist
- [ ] Clear error messages

**Implementation:**

```elixir
defmodule AshStateMachine.Verifiers.VerifyParallelRegions do
  @moduledoc """
  Verifies parallel_regions configuration.

  Checks:
  - All referenced resources exist and use AshStateMachine
  - All referenced relationships exist on the parent resource
  - Terminal states are valid states in the region resource
  - on_complete and on_failure actions exist
  """

  use Spark.Dsl.Verifier

  def verify(dsl_state) do
    # Get parallel_regions section
    case get_parallel_regions(dsl_state) do
      nil ->
        :ok

      parallel_regions ->
        verify_parallel_regions(dsl_state, parallel_regions)
    end
  end

  defp verify_parallel_regions(dsl_state, parallel_regions) do
    region_entities = Spark.Dsl.Extension.get_entities(dsl_state, [:state_machine, :parallel_regions])

    with :ok <- verify_relationships_exist(dsl_state, region_entities),
         :ok <- verify_resources_exist(region_entities),
         :ok <- verify_terminal_states(region_entities),
         :ok <- verify_completion_actions(dsl_state, parallel_regions) do
      :ok
    end
  end

  defp verify_relationships_exist(dsl_state, region_entities) do
    relationships = Ash.Resource.Info.relationships(dsl_state)
    relationship_names = Enum.map(relationships, & &1.name)

    Enum.reduce_while(region_entities, :ok, fn region, _acc ->
      if region.relationship in relationship_names do
        {:cont, :ok}
      else
        {:halt,
         {:error,
          "Parallel region #{region.name} references relationship #{region.relationship} " <>
            "which does not exist on this resource"}}
      end
    end)
  end

  defp verify_resources_exist(region_entities) do
    # Verify all region resources are loadable modules
    # ... implementation ...
    :ok
  end

  defp verify_terminal_states(region_entities) do
    # Verify terminal states exist in region resources
    # ... implementation ...
    :ok
  end

  defp verify_completion_actions(dsl_state, parallel_regions) do
    # Verify on_complete and on_failure actions exist
    # ... implementation ...
    :ok
  end

  defp get_parallel_regions(dsl_state) do
    Spark.Dsl.Extension.get_opt(
      dsl_state,
      [:state_machine, :parallel_regions],
      :completion_strategy,
      nil
    )
  end
end
```

**Tests:** `test/verifiers/verify_parallel_regions_test.exs`

**Estimated Time:** 6 hours

---

## Sprint 4: Oban Integration (Week 4)

### Task 4.1: Create ObanIntegration Module

**File:** `lib/oban_integration.ex`

**Description:** Dual Oban support (Pro + OSS) for spawning parallel region
jobs.

**Acceptance Criteria:**

- [ ] Detects Oban Pro availability at runtime
- [ ] Spawns Workflow when Pro available
- [ ] Spawns individual jobs when OSS only
- [ ] Configurable queue names
- [ ] Works without Oban (graceful degradation)

**Implementation:**

```elixir
defmodule AshStateMachine.ObanIntegration do
  @moduledoc """
  Oban integration for parallel region execution.

  Supports both Oban Pro (with Workflow DAG) and OSS Oban
  (with manual job spawning) with runtime detection and
  graceful degradation.
  """

  require Logger

  @doc """
  Spawns parallel region jobs using Oban.

  Automatically detects if Oban Pro is available:
  - If Pro: Creates Workflow DAG for parallel execution
  - If OSS: Spawns individual jobs
  - If no Oban: Returns error

  ## Options
  - `:mode` - Force specific mode (:pro, :oss, or :auto)
  """
  def spawn_parallel_regions(parent, region_definitions, opts \\ []) do
    mode = Keyword.get(opts, :mode, :auto)

    case resolve_mode(mode) do
      :pro ->
        spawn_via_workflow(parent, region_definitions, opts)

      :oss ->
        spawn_via_manual_jobs(parent, region_definitions, opts)

      :none ->
        {:error, :oban_not_available}
    end
  end

  defp resolve_mode(:auto) do
    cond do
      oban_pro_available?() -> :pro
      oban_available?() -> :oss
      true -> :none
    end
  end

  defp resolve_mode(mode) when mode in [:pro, :oss, :none], do: mode

  defp oban_pro_available? do
    Code.ensure_loaded?(Oban.Pro.Workers.Workflow)
  end

  defp oban_available? do
    Code.ensure_loaded?(Oban)
  end

  defp spawn_via_workflow(parent, region_definitions, opts) do
    Logger.debug("Spawning parallel regions via Oban Pro Workflow")

    workflow =
      region_definitions
      |> Enum.reduce(Oban.Pro.Workflow.new(), fn region, wf ->
        worker_module = get_worker_module(region, opts)
        queue = region.queue || :default

        Oban.Pro.Workflow.add(
          wf,
          region.name,
          worker_module,
          %{parent_id: parent.id, parent_resource: parent.__struct__},
          queue: queue
        )
      end)

    case Oban.insert_all(workflow) do
      {:ok, jobs} ->
        :telemetry.execute(
          [:ash_state_machine, :parallel_regions, :spawned],
          %{count: length(jobs)},
          %{mode: :pro, parent_id: parent.id}
        )

        {:ok, jobs}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp spawn_via_manual_jobs(parent, region_definitions, opts) do
    Logger.debug("Spawning parallel regions via manual Oban jobs")

    jobs =
      for region <- region_definitions do
        worker_module = get_worker_module(region, opts)
        queue = region.queue || :default

        %{
          parent_id: parent.id,
          parent_resource: parent.__struct__,
          region: region.name
        }
        |> worker_module.new(queue: queue)
      end

    case Oban.insert_all(jobs) do
      {:ok, inserted} ->
        :telemetry.execute(
          [:ash_state_machine, :parallel_regions, :spawned],
          %{count: length(inserted)},
          %{mode: :oss, parent_id: parent.id}
        )

        {:ok, inserted}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_worker_module(region, opts) do
    # Allow override via opts, otherwise derive from region resource
    Keyword.get(opts, :worker_module) ||
      Module.concat([region.resource, "Worker"])
  end
end
```

**Tests:** `test/oban_integration_test.exs`

**Estimated Time:** 8 hours

---

### Task 4.2: Add Telemetry Events

**File:** `lib/telemetry.ex`

**Description:** Define telemetry events for observability.

**Acceptance Criteria:**

- [ ] Events for region spawning
- [ ] Events for completion checking
- [ ] Events for parent transitions
- [ ] Documentation of all events

**Implementation:**

```elixir
defmodule AshStateMachine.Telemetry do
  @moduledoc """
  Telemetry events emitted by AshStateMachine.

  ## Events

  ### `[:ash_state_machine, :parallel_regions, :spawned]`

  Emitted when parallel region jobs are spawned.

  Measurements:
  - `:count` - Number of regions spawned

  Metadata:
  - `:mode` - `:pro` or `:oss`
  - `:parent_id` - ID of parent resource
  - `:parent_resource` - Parent resource module

  ### `[:ash_state_machine, :parallel_coordination, :check]`

  Emitted when checking parallel completion.

  Measurements:
  - `:duration` - Time taken in native units

  Metadata:
  - `:parent_id` - ID of parent resource
  - `:strategy` - Completion strategy
  - `:result` - `:complete`, `:pending`, or `{:error, reason}`

  ### `[:ash_state_machine, :parallel_coordination, :transition]`

  Emitted when parent transitions due to parallel completion.

  Measurements:
  - `:duration` - Time taken

  Metadata:
  - `:parent_id` - Parent resource ID
  - `:action` - Action name
  - `:from_state` - Previous state
  - `:to_state` - New state
  """

  def attach do
    events = [
      [:ash_state_machine, :parallel_regions, :spawned],
      [:ash_state_machine, :parallel_coordination, :check],
      [:ash_state_machine, :parallel_coordination, :transition]
    ]

    :telemetry.attach_many(
      "ash-state-machine-handler",
      events,
      &__MODULE__.handle_event/4,
      nil
    )
  end

  def handle_event(event, measurements, metadata, _config) do
    # Default handler - logs events
    require Logger

    Logger.debug(
      "[AshStateMachine] #{inspect(event)}: #{inspect(measurements)} #{inspect(metadata)}"
    )
  end
end
```

**Tests:** `test/telemetry_test.exs`

**Estimated Time:** 4 hours

---

### Task 4.3: Create Example Application

**Directory:** `examples/order_fulfillment/`

**Description:** Complete example demonstrating parallel regions with
Order/Payment/Inventory.

**Acceptance Criteria:**

- [ ] README with setup instructions
- [ ] Working Order, PaymentStep, InventoryStep resources
- [ ] Both Oban Pro and OSS examples
- [ ] Tests demonstrating parallel execution
- [ ] Can be run locally

**Structure:**

```
examples/order_fulfillment/
├── README.md
├── mix.exs
├── config/
│   └── config.exs
├── lib/
│   ├── order_fulfillment.ex
│   ├── order_fulfillment/
│   │   ├── order.ex
│   │   ├── payment_step.ex
│   │   ├── inventory_step.ex
│   │   ├── repo.ex
│   │   └── api.ex
│   └── workers/
│       ├── payment_worker.ex
│       └── inventory_worker.ex
└── test/
    └── order_fulfillment_test.exs
```

**Estimated Time:** 12 hours

---

### Task 4.4: Write Documentation

**Files:**

- `documentation/topics/parallel-regions.md`
- Update `README.md`
- Update `CHANGELOG.md`

**Acceptance Criteria:**

- [ ] Comprehensive guide to parallel regions
- [ ] DSL reference
- [ ] Completion strategies explained
- [ ] Oban integration documented
- [ ] Migration guide from sequential
- [ ] Troubleshooting section

**Estimated Time:** 8 hours

---

## Testing Checklist

### Unit Tests

- [ ] ParallelRegion entity validation
- [ ] ParallelRegions section parsing
- [ ] ParallelCoordinator logic (all strategies)
- [ ] CheckParallelCompletion change
- [ ] InjectParallelCompletion transformer
- [ ] ValidateParallelRegions verifier
- [ ] ObanIntegration (Pro + OSS paths)
- [ ] Telemetry events

### Integration Tests

- [ ] End-to-end: Create order → spawn regions → complete → parent transitions
- [ ] Concurrent region completion
- [ ] require_all strategy
- [ ] allow_partial strategy
- [ ] require_n strategy
- [ ] Failure handling
- [ ] Race conditions

### Manual Tests

- [ ] Example app runs with Oban Pro
- [ ] Example app runs with OSS Oban
- [ ] Example app works without Oban
- [ ] Telemetry events observable
- [ ] Error messages clear

---

## Success Criteria

Phase 1 is complete when:

1. **DSL Works**

   - [ ] Can define parallel_regions in state_machine
   - [ ] All validation errors are clear
   - [ ] Cheat sheets generate correctly

2. **Coordination Works**

   - [ ] All three strategies work correctly
   - [ ] Concurrent updates handled safely
   - [ ] Parent transitions at right time

3. **Transformer Works**

   - [ ] Completion checks auto-injected
   - [ ] No manual coordination needed
   - [ ] Works with existing resources

4. **Oban Integration Works**

   - [ ] Pro Workflow spawning works
   - [ ] OSS manual spawning works
   - [ ] Graceful degradation tested

5. **Documentation Complete**

   - [ ] Guide written
   - [ ] Examples working
   - [ ] README updated
   - [ ] CHANGELOG updated

6. **Tests Pass**
   - [ ] All unit tests pass
   - [ ] All integration tests pass
   - [ ] Coverage > 90%

---

## Timeline Summary

| Week      | Sprint             | Tasks   | Hours   |
| --------- | ------------------ | ------- | ------- |
| 1         | DSL Foundation     | 1.1-1.4 | 13h     |
| 2         | Coordination Logic | 2.1-2.2 | 16h     |
| 3         | Transformer        | 3.1-3.2 | 16h     |
| 4         | Oban Integration   | 4.1-4.4 | 32h     |
| **Total** |                    |         | **77h** |

**Target:** 3-4 weeks with 1-2 developers @ ~20h/week each

---

## Dependencies

**External:**

- Ash Framework (>= 3.0)
- Spark (>= 2.0)
- Oban (>= 2.15) - optional
- Oban Pro (>= 1.0) - optional

**Internal:**

- Existing AshStateMachine core
- Transformer pipeline
- State transition logic

---

## Risks and Mitigations

**Risk 1: Concurrent Updates**

- **Impact:** Race conditions in completion checking
- **Mitigation:** Use database transactions, advisory locks if needed
- **Testing:** Property-based tests with concurrent updates

**Risk 2: Oban Pro Dependency**

- **Impact:** Users without Pro can't use parallel features
- **Mitigation:** Full OSS Oban support, clear documentation
- **Testing:** Test both paths in CI

**Risk 3: Transformer Complexity**

- **Impact:** Hard to debug, fragile
- **Mitigation:** Comprehensive tests, clear error messages
- **Testing:** Integration tests with real resources

**Risk 4: Breaking Changes**

- **Impact:** Existing users affected
- **Mitigation:** New feature, opt-in, backward compatible
- **Testing:** Existing test suite still passes

---

## Next Steps

1. **Create GitHub Issues** - One issue per task
2. **Set up project board** - Track progress
3. **Start with 1.1** - ParallelRegion entity
4. **Daily standup** - Sync on progress

**Ready to begin implementation!**
