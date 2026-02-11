# Parallel States Implementation Plan - Nested Resources Pattern

**Date:** 2025-12-06 **Status:** Implementation Planning **Architecture:**
Nested Resources with Configurable Coordination

---

## Design Decisions

Based on design review (2025-12-06):

1. **Focus on ash_state_machine FIRST** - Build core parallel states and
   substates infrastructure before extending ash_jobs
2. **Nested Resources Pattern** - Each parallel region is a separate Ash
   resource with its own state machine
3. **Configurable Error Handling** - Per-state strategies: `:require_all`,
   `:allow_partial`, `{:require_n, count}`
4. **Dual Oban Support** - Work with both Oban Pro and OSS with graceful
   degradation

---

## Architecture Overview

### Nested Resources Pattern

**Core Concept:** Use separate Ash resources for parallel regions, connected via
relationships.

```elixir
# Main resource with parent state machine
defmodule Order do
  use Ash.Resource,
    extensions: [AshStateMachine]

  attributes do
    attribute :state, :atom, constraints: [one_of: [:pending, :processing, :completed]]
    attribute :completion_strategy, :atom, default: :require_all
  end

  relationships do
    has_many :payment_steps, PaymentStep
    has_many :inventory_steps, InventoryStep
  end

  state_machine do
    initial_states [:pending]
    default_initial_state :pending

    transitions do
      transition :start_processing, from: :pending, to: :processing
      transition :complete, from: :processing, to: :completed
    end
  end

  actions do
    update :start_processing do
      # Spawn parallel region resources
      change fn changeset, _context ->
        order = changeset.data

        # Create parallel region instances
        {:ok, _payment} = PaymentStep.create(%{order_id: order.id})
        {:ok, _inventory} = InventoryStep.create(%{order_id: order.id})

        changeset
      end

      change transition_state(:processing)
    end
  end
end

# Parallel region 1: Payment state machine
defmodule PaymentStep do
  use Ash.Resource,
    extensions: [AshStateMachine, AshOban]

  attributes do
    attribute :state, :atom, constraints: [one_of: [:pending, :processing, :completed, :failed]]
  end

  relationships do
    belongs_to :order, Order
  end

  state_machine do
    initial_states [:pending]
    default_initial_state :pending

    transitions do
      transition :process, from: :pending, to: :processing
      transition :complete, from: :processing, to: :completed
      transition :fail, from: :processing, to: :failed
    end
  end

  actions do
    update :complete do
      # Notify parent when this region completes
      change after_action(fn _changeset, payment_step ->
        check_parent_completion(payment_step.order_id)
        {:ok, payment_step}
      end)

      change transition_state(:completed)
    end
  end

  oban do
    trigger process_payment do
      action :process
      where expr(state == :pending)
      scheduler_queue :payment_processing
    end
  end
end

# Parallel region 2: Inventory state machine
defmodule InventoryStep do
  use Ash.Resource,
    extensions: [AshStateMachine, AshOban]

  attributes do
    attribute :state, :atom, constraints: [one_of: [:reserved, :picking, :packed, :failed]]
  end

  relationships do
    belongs_to :order, Order
  end

  state_machine do
    initial_states [:reserved]
    default_initial_state :reserved

    transitions do
      transition :pick, from: :reserved, to: :picking
      transition :pack, from: :picking, to: :packed
      transition :fail, from: [:reserved, :picking], to: :failed
    end
  end

  actions do
    update :pack do
      # Notify parent when this region completes
      change after_action(fn _changeset, inventory_step ->
        check_parent_completion(inventory_step.order_id)
        {:ok, inventory_step}
      end)

      change transition_state(:packed)
    end
  end

  oban do
    trigger pick_inventory do
      action :pick
      where expr(state == :reserved)
      scheduler_queue :warehouse_operations
    end
  end
end
```

### Completion Coordination Logic

**Challenge:** When should the parent resource transition from `:processing` to
`:completed`?

**Solution:** Configurable completion strategies.

```elixir
defmodule AshStateMachine.ParallelCoordinator do
  @moduledoc """
  Coordinates completion of parallel region resources.

  Checks if all required parallel regions have completed based on
  the parent resource's completion strategy.
  """

  @type strategy ::
          :require_all
          | :allow_partial
          | {:require_n, pos_integer()}

  @doc """
  Checks if parallel regions meet completion criteria.

  Returns {:ok, :complete} if ready to transition parent,
  {:ok, :pending} if still waiting,
  {:error, reason} if failed permanently.
  """
  def check_completion(parent_resource, region_definitions, strategy) do
    region_states = fetch_region_states(parent_resource, region_definitions)

    case strategy do
      :require_all ->
        check_require_all(region_states)

      :allow_partial ->
        check_allow_partial(region_states)

      {:require_n, n} ->
        check_require_n(region_states, n)
    end
  end

  defp check_require_all(region_states) do
    completed = Enum.count(region_states, &terminal_success?/1)
    failed = Enum.count(region_states, &terminal_failure?/1)
    total = length(region_states)

    cond do
      completed == total ->
        {:ok, :complete}

      failed > 0 ->
        {:error, :partial_failure}

      true ->
        {:ok, :pending}
    end
  end

  defp check_allow_partial(region_states) do
    all_terminal = Enum.all?(region_states, &terminal_state?/1)

    if all_terminal do
      {:ok, :complete}
    else
      {:ok, :pending}
    end
  end

  defp check_require_n(region_states, n) do
    completed = Enum.count(region_states, &terminal_success?/1)
    failed = Enum.count(region_states, &terminal_failure?/1)
    total = length(region_states)

    cond do
      completed >= n ->
        {:ok, :complete}

      # Not enough can succeed (some failed)
      total - failed < n ->
        {:error, :insufficient_completions}

      true ->
        {:ok, :pending}
    end
  end

  defp terminal_success?(region_state) do
    # Define success terminal states per region type
    region_state.state in [:completed, :packed, :shipped, :done]
  end

  defp terminal_failure?(region_state) do
    region_state.state in [:failed, :cancelled, :error]
  end

  defp terminal_state?(region_state) do
    terminal_success?(region_state) || terminal_failure?(region_state)
  end

  defp fetch_region_states(parent_resource, region_definitions) do
    # Query all parallel region resources
    Enum.flat_map(region_definitions, fn region ->
      parent_resource
      |> Ash.load!(region.relationship)
      |> Map.get(region.relationship)
    end)
  end
end
```

---

## Phase 1: Core Infrastructure (3-4 weeks)

### Goal: Enable parallel regions with nested resources

**Deliverables:**

1. DSL for defining parallel region relationships
2. Completion coordination module
3. Configurable strategies (require_all, allow_partial, require_n)
4. Basic Oban integration (works with OSS and Pro)
5. Comprehensive tests

### Task Breakdown

#### 1.1: DSL for Parallel Regions (1 week)

**Add `parallel_regions` section to state_machine DSL:**

```elixir
state_machine do
  parallel_regions do
    region :payment do
      resource PaymentStep
      relationship :payment_steps
      terminal_success_states [:completed]
      terminal_failure_states [:failed]
    end

    region :inventory do
      resource InventoryStep
      relationship :inventory_steps
      terminal_success_states [:packed]
      terminal_failure_states [:failed, :cancelled]
    end

    # Completion strategy
    completion_strategy :require_all
    # or: :allow_partial
    # or: {:require_n, 2}

    # What to do when all regions complete
    on_complete :advance_to_completed
    # What to do when strategy fails
    on_failure :advance_to_failed
  end

  transitions do
    transition :start_processing, from: :pending, to: :processing
    transition :advance_to_completed, from: :processing, to: :completed
    transition :advance_to_failed, from: :processing, to: :failed
  end
end
```

**Files to create:**

- `lib/dsl/sections/parallel_regions.ex` - DSL section definition
- `lib/dsl/entities/parallel_region.ex` - Region entity struct

**Tasks:**

- [ ] Define `ParallelRegions` section schema
- [ ] Define `ParallelRegion` entity with schema validation
- [ ] Add `parallel_regions` to state_machine section entities
- [ ] Write unit tests for DSL parsing
- [ ] Add to Spark cheat sheets

#### 1.2: Completion Coordinator (1 week)

**Create coordination module for checking parallel region completion:**

```elixir
defmodule AshStateMachine.ParallelCoordinator do
  def check_completion(parent, regions, strategy)
  def transition_if_ready(parent, action_name)
  def on_region_state_change(region_resource)
end
```

**Files to create:**

- `lib/parallel_coordinator.ex` - Core coordination logic
- `lib/changes/check_parallel_completion.ex` - Ash change module

**Tasks:**

- [ ] Implement `check_completion/3` with all strategies
- [ ] Implement `transition_if_ready/2` helper
- [ ] Create `CheckParallelCompletion` change module
- [ ] Handle race conditions (concurrent region updates)
- [ ] Add database transactions for consistency
- [ ] Write comprehensive tests for each strategy
- [ ] Add Telemetry events for monitoring

#### 1.3: Automatic Change Injection (1 week)

**Transformer to auto-inject completion checking:**

Similar to how AshJobs injects `AshJobs.Change`, we need to inject
`AshStateMachine.Changes.CheckParallelCompletion` into region resource actions.

```elixir
defmodule AshStateMachine.Transformers.InjectParallelCompletion do
  @moduledoc """
  Automatically injects CheckParallelCompletion change into all
  actions on resources that are parallel regions.

  When a region transitions to a terminal state, this change
  checks if the parent should advance.
  """

  use Spark.Dsl.Transformer

  def transform(dsl_state) do
    # Check if this resource is a parallel region
    # (referenced by a parent resource's parallel_regions section)

    if is_parallel_region?(dsl_state) do
      inject_completion_check(dsl_state)
    else
      {:ok, dsl_state}
    end
  end

  defp inject_completion_check(dsl_state) do
    # Add CheckParallelCompletion change to all update actions
    # that transition to terminal states
    # ...
  end
end
```

**Files to create:**

- `lib/transformers/inject_parallel_completion.ex`
- `lib/transformers/validate_parallel_regions.ex`

**Tasks:**

- [ ] Create InjectParallelCompletion transformer
- [ ] Auto-detect which resources are parallel regions
- [ ] Inject change only on terminal state transitions
- [ ] Create ValidateParallelRegions verifier
- [ ] Ensure relationships exist
- [ ] Validate terminal states are defined
- [ ] Write transformer tests

#### 1.4: Oban Integration (Support Both Pro and OSS) (1 week)

**Goal:** Work with both Oban Pro and OSS with graceful degradation.

**Oban Pro Path (Preferred):**

- Use Workflow DAG for parallel execution
- Automatic dependency management
- Built-in completion coordination

**OSS Oban Path (Fallback):**

- Use manual job spawning
- Rely on CheckParallelCompletion change for coordination
- Standard Oban triggers per region

```elixir
defmodule AshStateMachine.ObanIntegration do
  def spawn_parallel_regions(parent, regions, opts \\ []) do
    if oban_pro_available?() do
      spawn_via_workflow(parent, regions, opts)
    else
      spawn_via_manual_jobs(parent, regions, opts)
    end
  end

  defp oban_pro_available? do
    Code.ensure_loaded?(Oban.Pro.Workers.Workflow)
  end

  defp spawn_via_workflow(parent, regions, _opts) do
    # Build Oban Pro Workflow
    workflow =
      regions
      |> Enum.reduce(Oban.Pro.Workflow.new(), fn region, wf ->
        Oban.Pro.Workflow.add(
          wf,
          region.name,
          region.worker_module,
          %{parent_id: parent.id},
          queue: region.queue || :default
        )
      end)
      # No deps between regions - they run in parallel
      # Completion is handled by CheckParallelCompletion change

    Oban.insert_all(workflow)
  end

  defp spawn_via_manual_jobs(parent, regions, _opts) do
    # Spawn individual jobs
    for region <- regions do
      %{
        parent_id: parent.id,
        region: region.name
      }
      |> region.worker_module.new(queue: region.queue || :default)
      |> Oban.insert()
    end

    :ok
  end
end
```

**Tasks:**

- [ ] Create ObanIntegration module with dual support
- [ ] Implement Pro Workflow spawning
- [ ] Implement OSS manual spawning
- [ ] Add runtime detection of Oban Pro availability
- [ ] Write tests for both paths
- [ ] Document differences and recommendations

---

## Phase 2: Hierarchical States (4-6 weeks)

### Goal: Support substates/nested state machines

**Concept:** A state can contain its own nested state machine.

```elixir
state_machine do
  state :processing do
    # This state has its own internal state machine
    substates do
      initial_state :validating

      state :validating
      state :charging
      state :confirming

      transitions do
        transition :charge, from: :validating, to: :charging
        transition :confirm, from: :charging, to: :confirming
      end
    end

    # Exit from processing when substate reaches terminal
    on_substate_complete :advance_to_completed
  end
end
```

**Approaches:**

1. **Additional State Attribute** - `state: :processing, substate: :charging`
2. **Nested Resource** - Separate resource for substate tracking
3. **State History Tracking** - Store state path in array:
   `[:processing, :charging]`

**To Be Determined:**

- Which approach aligns best with nested resources pattern?
- How do entry/exit actions work with hierarchical states?
- How do parallel regions + hierarchical states compose?

**This phase needs more research - pending hierarchical workflows agent.**

---

## Phase 3: Advanced Features (3-4 weeks)

### Goal: Production-ready parallel orchestration

**Features:**

1. **Dynamic Region Spawning** - Create N regions at runtime
2. **History States** - Remember last substate when re-entering
3. **Compensation Logic** - Saga pattern for rollback
4. **Monitoring & Telemetry** - Comprehensive observability
5. **Testing Utilities** - Helpers for testing parallel execution

---

## Implementation Sequencing

### Week 1-2: DSL and Coordination

**Deliverables:**

- `parallel_regions` DSL section
- `ParallelRegion` entity
- `ParallelCoordinator` module
- All three strategies working

**Success Criteria:**

- Can define parallel regions in DSL
- Manual coordination logic works
- All strategies tested (require_all, allow_partial, require_n)

### Week 3: Transformer and Auto-Injection

**Deliverables:**

- `InjectParallelCompletion` transformer
- `ValidateParallelRegions` verifier
- Automatic completion checking

**Success Criteria:**

- Completion checks auto-injected into region actions
- No manual coordination code needed in user resources
- Validation catches missing relationships

### Week 4: Oban Integration

**Deliverables:**

- Dual Oban support (Pro + OSS)
- Example applications
- Documentation

**Success Criteria:**

- Works with Oban Pro Workflows
- Works with OSS Oban triggers
- Graceful degradation tested
- Example repo demonstrating both paths

---

## Testing Strategy

### Unit Tests

1. **DSL Parsing** - Validate parallel_regions section parsing
2. **Coordinator Logic** - Test each completion strategy
3. **Transformer Behavior** - Verify change injection
4. **Verifier Checks** - Ensure validation catches errors

### Integration Tests

1. **End-to-End Parallel Execution**

   - Create parent resource
   - Spawn parallel regions
   - Complete regions in different orders
   - Verify parent transitions correctly

2. **Error Scenarios**

   - Region failure with require_all strategy
   - Partial completion with require_n strategy
   - Race conditions (concurrent region updates)

3. **Oban Integration**
   - Test with Oban Pro (if available in CI)
   - Test with OSS Oban
   - Verify job scheduling and execution

### Property-Based Tests

Use StreamData for:

- Random region completion orders
- Concurrent state transitions
- Strategy validation across many scenarios

---

## Example Application

**Order Fulfillment System:**

```elixir
defmodule MyApp.Order do
  use Ash.Resource,
    extensions: [AshStateMachine]

  attributes do
    attribute :state, :atom
    attribute :total, :decimal
  end

  relationships do
    has_many :payment_steps, MyApp.PaymentStep
    has_many :inventory_steps, MyApp.InventoryStep
  end

  state_machine do
    initial_states [:pending]

    parallel_regions do
      region :payment do
        resource MyApp.PaymentStep
        relationship :payment_steps
        terminal_success_states [:completed]
        terminal_failure_states [:failed, :cancelled]
      end

      region :inventory do
        resource MyApp.InventoryStep
        relationship :inventory_steps
        terminal_success_states [:packed]
        terminal_failure_states [:failed, :out_of_stock]
      end

      completion_strategy :require_all
      on_complete :ship
      on_failure :cancel
    end

    transitions do
      transition :start, from: :pending, to: :processing
      transition :ship, from: :processing, to: :shipping
      transition :cancel, from: :processing, to: :cancelled
    end
  end

  actions do
    create :create do
      change fn changeset, _context ->
        # Order starts in pending state
        changeset
      end
    end

    update :start do
      # Spawn parallel regions
      change fn changeset, _context ->
        order = changeset.data

        # Create payment region
        {:ok, _payment} = MyApp.PaymentStep.create(%{
          order_id: order.id,
          amount: order.total
        })

        # Create inventory region
        {:ok, _inventory} = MyApp.InventoryStep.create(%{
          order_id: order.id
        })

        changeset
      end

      change transition_state(:processing)

      # Optionally spawn Oban jobs if not using triggers
      change after_action(fn _changeset, order ->
        AshStateMachine.ObanIntegration.spawn_parallel_regions(
          order,
          [:payment, :inventory]
        )

        {:ok, order}
      end)
    end
  end
end

defmodule MyApp.PaymentStep do
  use Ash.Resource,
    extensions: [AshStateMachine, AshOban]

  attributes do
    attribute :state, :atom
    attribute :amount, :decimal
  end

  relationships do
    belongs_to :order, MyApp.Order
  end

  state_machine do
    initial_states [:pending]

    transitions do
      transition :process, from: :pending, to: :processing
      transition :complete, from: :processing, to: :completed
      transition :fail, from: :processing, to: :failed
    end
  end

  actions do
    update :process do
      change fn changeset, _context ->
        # Payment processing logic
        payment = changeset.data

        case charge_credit_card(payment.amount) do
          {:ok, _transaction} ->
            changeset
            |> Ash.Changeset.force_change_attribute(:state, :completed)

          {:error, reason} ->
            changeset
            |> Ash.Changeset.add_error(field: :state, message: reason)
        end
      end

      change transition_state(:processing)
    end

    update :complete do
      # CheckParallelCompletion auto-injected by transformer
      change transition_state(:completed)
    end
  end

  oban do
    trigger process_payment do
      action :process
      where expr(state == :pending)
      scheduler_queue :payment_processing
      max_attempts 3
    end
  end
end

defmodule MyApp.InventoryStep do
  use Ash.Resource,
    extensions: [AshStateMachine, AshOban]

  attributes do
    attribute :state, :atom
  end

  relationships do
    belongs_to :order, MyApp.Order
  end

  state_machine do
    initial_states [:reserved]

    transitions do
      transition :pick, from: :reserved, to: :picking
      transition :pack, from: :picking, to: :packed
      transition :fail, from: [:reserved, :picking], to: :failed
    end
  end

  actions do
    update :pick do
      change fn changeset, _context ->
        # Inventory picking logic
        changeset
      end

      change transition_state(:picking)
    end

    update :pack do
      # CheckParallelCompletion auto-injected by transformer
      change transition_state(:packed)
    end
  end

  oban do
    trigger pick_inventory do
      action :pick
      where expr(state == :reserved)
      scheduler_queue :warehouse_operations
    end
  end
end
```

**Usage:**

```elixir
# Create order
{:ok, order} = MyApp.Order.create(%{total: Decimal.new("99.99")})

# Start processing (spawns parallel regions)
{:ok, order} = MyApp.Order.start(order)

# Oban triggers will automatically:
# 1. Process payment (PaymentStep state: pending -> processing -> completed)
# 2. Pick inventory (InventoryStep state: reserved -> picking -> packed)

# When BOTH regions reach terminal success states:
# ParallelCoordinator detects completion
# Order transitions: processing -> shipping

# If ANY region fails with :require_all strategy:
# Order transitions: processing -> cancelled
```

---

## Open Questions

1. **Database Transactions**

   - Should coordination checks happen in a transaction?
   - How to handle concurrent region completions?
   - Use advisory locks?

2. **Telemetry Events**

   - What events should be emitted?
   - `[:ash_state_machine, :parallel_region, :spawned]`?
   - `[:ash_state_machine, :parallel_region, :completed]`?
   - `[:ash_state_machine, :parallel_coordination, :checked]`?

3. **Migration from Sequential to Parallel**

   - How do existing users adopt parallel regions?
   - Provide migration guide?
   - Backward compatibility concerns?

4. **Hierarchical + Parallel Composition**
   - Can a parallel region contain substates?
   - Can a substate contain parallel regions?
   - Nesting depth limits?

---

## Success Metrics

**Phase 1 Complete When:**

- [ ] DSL supports parallel_regions section
- [ ] All three completion strategies work
- [ ] Automatic completion checking via transformer
- [ ] Works with both Oban Pro and OSS
- [ ] Comprehensive test coverage (>90%)
- [ ] Example application demonstrating real use case
- [ ] Documentation complete

**Long-term Success:**

- Adopted by ash_jobs for workflow orchestration
- Real-world production usage
- Performance benchmarks vs manual coordination
- Community feedback positive

---

## Next Steps

**Immediate Actions:**

1. **Review this plan** - Validate approach with maintainers
2. **Create Phase 1 tasks** - Break down into GitHub issues
3. **Set up example repo** - Order fulfillment demo app
4. **Start with DSL** - Begin implementation with DSL entities

**Questions for Maintainers:**

1. Does nested resources pattern align with Ash philosophy?
2. Any concerns about transformer complexity?
3. Preferred approach for hierarchical states?
4. Should this be in core or separate package?

---

**Document Status:** Implementation Plan - Ready for Review **Last Updated:**
2025-12-06 **Next Review:** After maintainer feedback
