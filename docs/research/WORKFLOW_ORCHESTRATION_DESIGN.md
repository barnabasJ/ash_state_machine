# Workflow Orchestration Design: Parallel States + Oban Integration

**Date:** 2025-12-06 **Status:** Research Synthesis - In Progress **Goal:**
Enable workflows with Oban on top of ash_state_machine with fan-out/fan-in
parallel job execution

---

## Executive Summary

This document synthesizes research on workflow orchestration patterns to enable
**parallel state machines** and **hierarchical substates** in ash_state_machine,
specifically for orchestrating **parallel Oban jobs** with fan-out/fan-in
patterns.

### Key Findings

1. **AshJobs Already Provides a Working Model** - Combines ash_state_machine +
   ash_oban using transformers to auto-generate state machines from workflow DSL
2. **Oban Pro Workflows Enable DAG-Based Orchestration** - Native support for
   dependencies, parallel execution, and dynamic workflow expansion
3. **Parallel States Map to Concurrent Job Execution** - Orthogonal regions from
   statechart theory align with parallel job patterns
4. **Transformer Pattern is Key** - Compile-time DSL generation reduces
   boilerplate and ensures consistency

### Research Status

✅ **Completed:**

- Oban fundamentals and patterns
- Oban Pro advanced features
- AshJobs codebase architecture
- Parallel state machine theory

⏳ **Pending:**

- Hierarchical state workflows
- Fan-out/fan-in job patterns
- State machine + job queue integration patterns
- Real-world workflow examples

---

## Part 1: Current State Analysis

### What ash_state_machine Provides Today

```elixir
state_machine do
  initial_states [:pending]
  default_initial_state :pending
  state_attribute :state

  transitions do
    transition :start, from: :pending, to: :processing
    transition :complete, from: :processing, to: :completed
    transition :fail, from: :processing, to: :failed
  end
end
```

**Capabilities:**

- Single state attribute tracking
- Explicit state transitions with validation
- Wildcard support (`:*` for any state/action)
- Integration with Ash changesets

**Limitations for Workflows:**

- ❌ No parallel states (orthogonal regions)
- ❌ No hierarchical states (substates)
- ❌ No automatic job scheduling
- ❌ No fan-out/fan-in coordination
- ❌ No entry/exit actions
- ❌ Manual workflow step management

### What AshJobs Provides Today

AshJobs demonstrates how to combine ash_state_machine + ash_oban:

```elixir
workflow do
  step :load_order do
    action :load_order_data
    on_success :validate_inventory
    on_error :handle_load_error
    queue :order_processing
    timeout_seconds 30
  end

  step :validate_inventory do
    action :check_stock
    on_success :create_shipment
    on_error :handle_inventory_error
    queue :inventory_processing
  end

  step :create_shipment do
    action :create_shipment_record
    on_success :completed
    queue :shipping
  end
end
```

**What It Does:**

1. **Auto-generates state machine DSL** - One state per step
2. **Auto-generates Oban triggers** - Automatic job scheduling for each step
3. **Injects routing logic** - `AshJobs.Change` module handles state transitions
4. **Reduces boilerplate by ~75%** - Workflow DSL is much more concise

**Architecture:**

```
User writes:     workflow { step :foo }
                        ↓
Transformer 1:   Generates error handler actions
Transformer 2:   Injects AshJobs.Change into all step actions
Transformer 3:   Auto-generates state_machine DSL
Transformer 4:   Auto-generates ash_oban trigger DSL
                        ↓
Result:          Full state machine + Oban integration
```

**Limitations for Parallel Workflows:**

- ❌ Sequential steps only (no fan-out)
- ❌ No parallel step execution
- ❌ No fan-in coordination (waiting for multiple jobs)
- ❌ No hierarchical workflow composition

---

## Part 2: Oban Capabilities for Workflow Orchestration

### Oban Open Source

**Core Features for Workflows:**

1. **Queue-Based Concurrency**

```elixir
config :my_app, Oban,
  queues: [
    default: 10,           # 10 concurrent jobs
    order_processing: 5,
    inventory: 20,         # Higher concurrency for I/O-bound
    shipping: 3
  ]
```

2. **Job Dependencies (Simple Fan-In)**

```elixir
# Job 1
{:ok, job1} = insert_job(%{type: "fetch_data"})

# Job 2 waits for Job 1
{:ok, job2} = insert_job(%{type: "process_data", deps: [job1.id]})
```

3. **Fan-Out Pattern (Manual)**

```elixir
# Parent job spawns children
def perform(%Job{args: %{"order_ids" => ids}}) do
  for order_id <- ids do
    %{order_id: order_id}
    |> ProcessOrderWorker.new()
    |> Oban.insert()
  end

  :ok
end
```

**Limitations:**

- Manual fan-in coordination
- No built-in DAG visualization
- No dynamic workflow modification
- Limited batch processing

### Oban Pro

**Advanced Workflow Features:**

1. **Workflow DSL with DAG Support**

```elixir
Workflow.new()
|> Workflow.add(:load_data, LoadWorker, %{source: "api"})
|> Workflow.add(:transform_a, TransformWorker, %{type: "a"}, deps: [:load_data])
|> Workflow.add(:transform_b, TransformWorker, %{type: "b"}, deps: [:load_data])
|> Workflow.add(:combine, CombineWorker, %{}, deps: [:transform_a, :transform_b])
|> Oban.insert_all()
```

**Visualization:**

```
    load_data
       / \
      /   \
transform_a transform_b
      \   /
       \ /
     combine
```

2. **Batches (Map-Reduce Pattern)**

```elixir
batch = Batch.new(%{})

# Map phase - fan out
for item <- items do
  Batch.add(batch, ProcessWorker, %{item: item})
end

# Callbacks - fan in
batch = Batch.on_complete(batch, AggregateWorker, %{})
batch = Batch.on_exhaustion(batch, CleanupWorker, %{})

Batch.insert(batch)
```

3. **Grafting (Dynamic Workflow Expansion)**

```elixir
# Runtime workflow modification
def perform(%Job{} = job) do
  new_jobs =
    Workflow.new()
    |> Workflow.add(:step_a, WorkerA, %{})
    |> Workflow.add(:step_b, WorkerB, %{})

  # Dynamically add jobs to existing workflow
  Workflow.graft(job, new_jobs)
end
```

4. **Performance Improvements**

- **20x faster** job processing (2000 jobs/sec vs 100 jobs/sec)
- Global rate limiting
- Smart polling
- Bulk operations

**Pro Enables:**

- ✅ Declarative parallel execution
- ✅ Automatic fan-in coordination
- ✅ Visual DAG representation
- ✅ Dynamic workflow modification at runtime
- ✅ Production-grade performance

---

## Part 3: Parallel State Machine Patterns

### Statechart Theory: Orthogonal Regions

**Harel Statecharts (1987) Definition:**

> "Orthogonal components are independent state machines that execute
> concurrently within a parent state."

**Example from Research:**

```
[Order Processing]
├─ [Payment State]
│  ├─ awaiting_payment
│  ├─ payment_processing
│  └─ payment_completed
│
└─ [Inventory State]
   ├─ inventory_reserved
   ├─ inventory_picking
   └─ inventory_packed
```

**Both regions progress independently:**

- Payment can be "payment_processing" while Inventory is "inventory_picking"
- Parent state completes only when BOTH regions reach terminal states
- Fork semantics: Entering parent state activates BOTH regions
- Join semantics: Exiting parent state requires BOTH regions to complete

### Mapping to Parallel Jobs

**State Machine View:**

```elixir
parallel_state :process_order do
  region :payment do
    state :awaiting_payment
    state :payment_processing
    state :payment_completed
  end

  region :inventory do
    state :inventory_reserved
    state :inventory_picking
    state :inventory_packed
  end

  # Completes when both regions reach terminal states
  on_complete :order_ready_to_ship
end
```

**Oban Pro Workflow Equivalent:**

```elixir
Workflow.new()
# Fork: Both start simultaneously
|> Workflow.add(:process_payment, PaymentWorker, %{})
|> Workflow.add(:pick_inventory, InventoryWorker, %{})
# Join: Wait for both to complete
|> Workflow.add(:ship_order, ShippingWorker, %{},
     deps: [:process_payment, :pick_inventory])
|> Oban.insert_all()
```

**Key Insight:** Orthogonal regions provide the **logical model**, while Oban
jobs provide the **execution model**.

---

## Part 4: Design Approaches for Parallel States + Oban

### Approach 1: Extend ash_state_machine with Parallel States

**Add parallel state support to the core DSL:**

```elixir
state_machine do
  parallel_state :process_order do
    # Define orthogonal regions
    region :payment, attribute: :payment_state do
      states [:pending, :processing, :completed, :failed]
      initial_state :pending

      transitions do
        transition :start_payment, from: :pending, to: :processing
        transition :complete_payment, from: :processing, to: :completed
      end
    end

    region :inventory, attribute: :inventory_state do
      states [:reserved, :picking, :packed, :shipped]
      initial_state :reserved

      transitions do
        transition :start_picking, from: :reserved, to: :picking
        transition :pack, from: :picking, to: :packed
      end
    end

    # Completion condition
    on_all_complete :order_completed
  end
end
```

**Database Schema:**

```elixir
attributes do
  attribute :state, :atom, constraints: [one_of: [:pending, :process_order, :completed]]
  attribute :payment_state, :atom, constraints: [one_of: [:pending, :processing, :completed]]
  attribute :inventory_state, :atom, constraints: [one_of: [:reserved, :picking, :packed]]
end
```

**Oban Integration:**

```elixir
# When entering parallel_state :process_order
# Automatically spawn jobs for each region

defmodule MyApp.Changes.EnterParallelState do
  def change(changeset, opts) do
    if transitioning_to_parallel_state?(changeset) do
      # Spawn parallel jobs
      changeset
      |> after_action(fn _changeset, record ->
        spawn_region_jobs(record, opts[:regions])
        {:ok, record}
      end)
    else
      changeset
    end
  end

  defp spawn_region_jobs(record, regions) do
    for region <- regions do
      %{
        resource_id: record.id,
        region: region.name,
        initial_action: region.initial_action
      }
      |> MyApp.RegionWorker.new(queue: region.queue)
      |> Oban.insert()
    end
  end
end
```

**Pros:**

- ✅ Unified state machine model in DSL
- ✅ Multiple state attributes supported
- ✅ Logical model matches execution model
- ✅ Standard statechart semantics

**Cons:**

- ❌ Complex DSL additions
- ❌ Multiple attributes to track
- ❌ Requires significant core changes
- ❌ Migration path for existing users

---

### Approach 2: Workflow DSL with Parallel Steps (AshJobs Pattern)

**Extend AshJobs-style workflow DSL:**

```elixir
workflow do
  step :create_order do
    action :create_order_record
    on_success :process_order
  end

  # Parallel steps
  parallel_step :process_order do
    step :process_payment do
      action :charge_payment
      queue :payment_processing
      timeout_seconds 30
    end

    step :pick_inventory do
      action :reserve_and_pick
      queue :warehouse_operations
      timeout_seconds 120
    end

    # Wait for both to complete
    on_complete :ship_order
  end

  step :ship_order do
    action :create_shipment
    on_success :completed
  end
end
```

**Generated State Machine:**

```elixir
# Auto-generated by transformer
state_machine do
  initial_states [:create_order]

  transitions do
    transition :create_order_record,
      from: :create_order,
      to: :process_order

    # Parallel state entry spawns both jobs
    transition :enter_parallel,
      from: :process_order,
      to: :process_order_active

    # When both jobs complete
    transition :create_shipment,
      from: :process_order_active,
      to: :ship_order
  end
end
```

**Database Schema:**

```elixir
# Main order resource
attributes do
  attribute :state, :atom
  attribute :payment_job_id, :integer
  attribute :inventory_job_id, :integer
  attribute :parallel_jobs_pending, :integer, default: 0
end

# Or separate parallel_executions table
# for tracking parallel job completion
```

**Implementation with Oban Pro Workflows:**

```elixir
# Generated by transformer
defmodule MyApp.Changes.EnterProcessOrder do
  def change(changeset, _opts) do
    changeset
    |> after_action(fn _changeset, record ->
      # Use Oban Pro Workflow for parallel execution
      workflow =
        Workflow.new()
        |> Workflow.add(:payment, ProcessPaymentWorker,
             %{order_id: record.id},
             queue: :payment_processing)
        |> Workflow.add(:inventory, PickInventoryWorker,
             %{order_id: record.id},
             queue: :warehouse_operations)
        |> Workflow.add(:callback, ParallelCompleteWorker,
             %{order_id: record.id, next_step: :ship_order},
             deps: [:payment, :inventory])

      Oban.insert_all(workflow)

      {:ok, record}
    end)
  end
end
```

**Pros:**

- ✅ Familiar workflow DSL pattern
- ✅ Leverages Oban Pro Workflows for execution
- ✅ Single state attribute (simpler schema)
- ✅ Clear separation: DSL = logical, Oban = execution
- ✅ Builds on proven AshJobs pattern

**Cons:**

- ❌ Not "pure" statechart parallel states
- ❌ Parallel execution is implicit, not visible in state machine
- ❌ Requires Oban Pro for best experience

---

### Approach 3: Hybrid - Multiple State Machine Resources

**Use separate resources for parallel concerns:**

```elixir
# Main order state machine
defmodule Order do
  state_machine do
    transitions do
      transition :start_processing, from: :pending, to: :processing
      transition :complete, from: :processing, to: :completed
    end
  end

  actions do
    update :start_processing do
      change fn changeset, _context ->
        order = changeset.data

        # Create parallel state machine instances
        {:ok, _payment} = Payment.create(%{order_id: order.id, state: :pending})
        {:ok, _inventory} = Inventory.create(%{order_id: order.id, state: :reserved})

        changeset
      end
      change transition_state(:processing)
    end
  end
end

# Payment state machine (parallel region 1)
defmodule Payment do
  state_machine do
    transitions do
      transition :process, from: :pending, to: :processing
      transition :complete, from: :processing, to: :completed
    end
  end

  actions do
    update :complete do
      change after_action(fn _changeset, payment ->
        # Check if sibling region is also done
        inventory = Inventory.get_by_order(payment.order_id)

        if inventory.state == :packed do
          # Both regions complete - advance parent
          Order.transition!(payment.order_id, :complete)
        end

        {:ok, payment}
      end)
    end
  end
end

# Inventory state machine (parallel region 2)
defmodule Inventory do
  state_machine do
    transitions do
      transition :pick, from: :reserved, to: :picking
      transition :pack, from: :picking, to: :packed
    end
  end

  actions do
    update :pack do
      change after_action(fn _changeset, inventory ->
        # Check if sibling region is also done
        payment = Payment.get_by_order(inventory.order_id)

        if payment.state == :completed do
          # Both regions complete - advance parent
          Order.transition!(inventory.order_id, :complete)
        end

        {:ok, inventory}
      end)
    end
  end
end
```

**Oban Integration:**

```elixir
# Each resource can have its own Oban triggers
defmodule Payment do
  use AshOban

  oban do
    trigger process_payment do
      action :process
      where expr(state == :pending)
      scheduler_queue :payment_processing
    end
  end
end

defmodule Inventory do
  use AshOban

  oban do
    trigger pick_inventory do
      action :pick
      where expr(state == :reserved)
      scheduler_queue :warehouse_operations
    end
  end
end
```

**Pros:**

- ✅ Works with current ash_state_machine
- ✅ Clear separation of concerns
- ✅ Each region is independently testable
- ✅ No core library changes needed
- ✅ Leverages existing patterns

**Cons:**

- ❌ Manual coordination logic
- ❌ No declarative parallel state syntax
- ❌ Race conditions in completion checking
- ❌ More database queries

---

## Part 5: Recommended Approach

### **Approach 2: Workflow DSL with Parallel Steps**

**Rationale:**

1. **Builds on Proven Pattern** - AshJobs demonstrates transformers work well
2. **Leverages Oban Pro** - Use the right tool for job orchestration
3. **Simpler Implementation** - Doesn't require parallel state theory in core
4. **Better Performance** - Oban Pro optimized for parallel execution
5. **Clear Separation** - State machine = logical model, Oban = execution

### Implementation Roadmap

#### Phase 1: Basic Parallel Steps (2-3 weeks)

**Goal:** Support simple fan-out/fan-in in workflow DSL

```elixir
workflow do
  parallel_step :process_order do
    step :payment do
      action :process_payment
      queue :payment
    end

    step :inventory do
      action :pick_items
      queue :warehouse
    end

    on_complete :ship_order
  end
end
```

**Tasks:**

1. Extend workflow DSL entity to support `parallel_step`
2. Create `ParallelStep` entity with `steps` and `on_complete`
3. Update BuildWorkflow transformer to detect parallel steps
4. Generate Oban Pro Workflow DAG for parallel execution
5. Create completion callback worker
6. Add tests for parallel execution

**Database Schema Changes:**

```elixir
# Track parallel execution state
attributes do
  attribute :state, :atom
  attribute :parallel_execution_id, :uuid  # Links to Oban workflow
  attribute :pending_parallel_jobs, {:array, :string}
end
```

#### Phase 2: Hierarchical States (4-6 weeks)

**Goal:** Support substatemachines for complex workflows

```elixir
workflow do
  step :order_processing do
    action :start_processing

    # Nested workflow
    substeps do
      step :validate_payment_method
      step :authorize_payment
      step :capture_payment
    end

    on_success :fulfillment
  end
end
```

**Tasks:**

1. Design hierarchical state DSL
2. Update transformers to handle nested steps
3. Generate hierarchical state machine transitions
4. Support entry/exit actions for state hierarchies
5. Add history state support
6. Comprehensive testing

#### Phase 3: Advanced Patterns (3-4 weeks)

**Goal:** Support dynamic workflows and complex patterns

Features:

- **Dynamic fan-out** - Runtime determination of parallel jobs
- **Conditional execution** - Guard conditions on steps
- **Timeouts and retries** - Workflow-level failure handling
- **Human-in-the-loop** - Manual approval steps

```elixir
workflow do
  step :split_batch do
    action :determine_batches
    # Dynamic fan-out based on runtime data
    fan_out :process_batch, count: :dynamic
  end

  step :await_approval do
    action :send_approval_request
    # Pause until manual action
    trigger false
    on_manual_approval :continue_processing
  end
end
```

---

## Part 6: Technical Design Details

### Parallel Step Entity

```elixir
defmodule AshStateMachine.Dsl.Entities.ParallelStep do
  @moduledoc """
  Defines a parallel step that spawns multiple concurrent jobs.

  A parallel step contains multiple child steps that execute concurrently.
  The parallel step completes only when all child steps complete successfully.

  ## Options

  - `:name` (atom, required) - Unique identifier
  - `:steps` (list of Step, required) - Child steps to execute in parallel
  - `:on_complete` (atom, required) - Next step when all children complete
  - `:on_error` (atom) - Error handler if any child fails
  - `:timeout_seconds` (integer) - Overall timeout for parallel execution
  - `:strategy` (:all | :any | {:n, integer}) - Completion strategy

  ## Examples

      parallel_step :process_order do
        step :payment do
          action :charge_card
        end

        step :inventory do
          action :reserve_items
        end

        on_complete :ship_order
        timeout_seconds 300
      end

      # Require only N completions
      parallel_step :fetch_data do
        step :source_a, action: :fetch_a
        step :source_b, action: :fetch_b
        step :source_c, action: :fetch_c

        strategy {:n, 2}  # Proceed when any 2 complete
        on_complete :process_data
      end
  """

  @type strategy :: :all | :any | {:n, pos_integer()}

  @type t :: %__MODULE__{
    name: atom(),
    steps: [Step.t()],
    on_complete: atom(),
    on_error: atom() | nil,
    timeout_seconds: integer() | nil,
    strategy: strategy()
  }

  defstruct [
    :name,
    :steps,
    :on_complete,
    :on_error,
    :timeout_seconds,
    :__spark_metadata__,
    strategy: :all
  ]

  def schema do
    [
      name: [
        type: :atom,
        required: true,
        doc: "Unique identifier for this parallel step"
      ],
      steps: [
        type: {:list, {:struct, Step}},
        required: true,
        doc: "Child steps to execute in parallel"
      ],
      on_complete: [
        type: :atom,
        required: true,
        doc: "Next step when parallel execution completes"
      ],
      on_error: [
        type: :atom,
        required: false,
        doc: "Error handler if any child step fails"
      ],
      timeout_seconds: [
        type: :pos_integer,
        required: false,
        doc: "Overall timeout for parallel execution"
      ],
      strategy: [
        type: {:one_of, [:all, :any, {:tuple, [:n, :pos_integer]}]},
        required: false,
        default: :all,
        doc: "Completion strategy - :all (all must complete), :any (first completion), {:n, count}"
      ]
    ]
  end
end
```

### Transformer: Generate Oban Pro Workflows

```elixir
defmodule AshStateMachine.Transformers.GenerateObanWorkflows do
  @moduledoc """
  Generates Oban Pro Workflow integration for parallel steps.

  For each parallel_step in the workflow DSL, this transformer:
  1. Creates an entry action that spawns the Oban Workflow
  2. Generates workers for each parallel child step
  3. Creates a completion callback worker
  4. Adds state transitions for parallel execution
  """

  use Spark.Dsl.Transformer

  def transform(dsl_state) do
    parallel_steps = get_parallel_steps(dsl_state)

    if parallel_steps && length(parallel_steps) > 0 do
      dsl_state =
        Enum.reduce(parallel_steps, dsl_state, fn parallel_step, acc ->
          acc
          |> generate_entry_action(parallel_step)
          |> generate_workers(parallel_step)
          |> generate_completion_callback(parallel_step)
          |> add_parallel_state_transitions(parallel_step)
        end)

      {:ok, dsl_state}
    else
      {:ok, dsl_state}
    end
  end

  defp generate_entry_action(dsl_state, parallel_step) do
    # Create action that spawns Oban Pro Workflow
    action_name = :"enter_#{parallel_step.name}"

    worker_code = quote do
      defmodule unquote(worker_module_name(parallel_step)) do
        use Oban.Pro.Workers.Workflow

        @impl Oban.Worker
        def process(%Job{args: args}) do
          # Build workflow with parallel jobs
          workflow =
            Workflow.new()
            |> unquote(add_parallel_jobs(parallel_step))
            |> Workflow.add(
              :callback,
              unquote(callback_worker_name(parallel_step)),
              %{resource_id: args["resource_id"]},
              deps: unquote(deps_list(parallel_step))
            )

          Oban.insert_all(workflow)
          :ok
        end
      end
    end

    # Inject this worker into the resource's module
    # and create an action that enqueues it

    dsl_state
    # ... transformer logic to add action and worker
  end

  defp add_parallel_jobs(parallel_step) do
    for step <- parallel_step.steps do
      quote do
        Workflow.add(
          unquote(step.name),
          unquote(worker_for_step(step)),
          %{resource_id: args["resource_id"]},
          queue: unquote(step.queue || :default)
        )
      end
    end
  end

  defp generate_completion_callback(dsl_state, parallel_step) do
    # Create callback worker that transitions to on_complete step
    callback_code = quote do
      defmodule unquote(callback_worker_name(parallel_step)) do
        use Oban.Worker

        @impl Oban.Worker
        def perform(%Job{args: %{"resource_id" => id}}) do
          # All parallel jobs completed successfully
          # Transition to next step
          resource = MyApp.Repo.get!(unquote(resource_module()), id)

          MyApp.transition_to_next_step(
            resource,
            unquote(parallel_step.on_complete)
          )

          :ok
        end
      end
    end

    dsl_state
    # ... add callback worker
  end
end
```

### Generated Oban Pro Workflow Example

**User writes:**

```elixir
workflow do
  parallel_step :process_order do
    step :payment, action: :charge, queue: :payment
    step :inventory, action: :reserve, queue: :warehouse
    on_complete :ship_order
  end
end
```

**Transformer generates:**

```elixir
# Worker that spawns parallel execution
defmodule MyApp.Order.ProcessOrderWorkflow do
  use Oban.Pro.Workers.Workflow

  def process(%Job{args: %{"order_id" => id}}) do
    workflow =
      Workflow.new()
      |> Workflow.add(:payment, MyApp.Order.PaymentWorker,
           %{order_id: id}, queue: :payment)
      |> Workflow.add(:inventory, MyApp.Order.InventoryWorker,
           %{order_id: id}, queue: :warehouse)
      |> Workflow.add(:callback, MyApp.Order.ProcessOrderCallback,
           %{order_id: id}, deps: [:payment, :inventory])

    Oban.insert_all(workflow)
    :ok
  end
end

# Callback when both complete
defmodule MyApp.Order.ProcessOrderCallback do
  use Oban.Worker

  def perform(%Job{args: %{"order_id" => id}}) do
    order = MyApp.Order.get!(id)

    # Transition to ship_order step
    MyApp.Order.ship_order!(order)

    :ok
  end
end
```

---

## Part 7: Open Questions and Further Research

### Questions to Resolve

1. **Oban Pro Licensing** - What are the implications of depending on Oban Pro?

   - Can we support both OSS Oban and Pro?
   - Graceful degradation if Pro not available?

2. **Error Handling in Parallel Steps** - How to handle partial failures?

   - If 2 of 3 parallel jobs succeed, what happens?
   - Compensation logic (saga pattern)?
   - Retry strategies per child step?

3. **Dynamic Fan-Out** - How to determine parallel job count at runtime?

   ```elixir
   parallel_step :process_items do
     # Spawn N jobs based on runtime data
     for_each :items, action: :process_item
     on_complete :aggregate_results
   end
   ```

4. **State Persistence** - How to track parallel execution state?

   - Store in main resource?
   - Separate parallel_executions table?
   - Rely on Oban's job state?

5. **Testing Parallel Workflows** - How to test concurrent execution?
   - Inline job execution for tests?
   - Oban.Testing helpers?
   - Simulating timing issues?

### Areas Needing More Research

From pending research agents:

1. **Hierarchical State Workflows**

   - How to model nested workflows declaratively?
   - Entry/exit actions for hierarchical states?
   - History state support?

2. **Fan-Out/Fan-In Patterns**

   - Map-reduce patterns
   - Scatter-gather
   - Aggregation strategies
   - Partial result handling

3. **Real-World Workflow Examples**
   - E-commerce order fulfillment
   - Multi-step approval processes
   - Data pipeline orchestration
   - How do production systems handle failures?

---

## Part 8: Next Steps

### Immediate Actions

1. **✅ Complete remaining research** - Wait for 6 pending agents to finish
2. **Synthesize fan-out/fan-in findings** - Add to this document
3. **Design decision: Oban Pro dependency** - Discuss with maintainers
4. **Create detailed implementation plan** - Phase 1 task breakdown

### Validation Questions for User

Before proceeding with implementation:

1. **Is Oban Pro dependency acceptable?** Or must it work with OSS Oban?
2. **Priority: Parallel steps vs Hierarchical states?** Which to implement
   first?
3. **Use case validation** - Does the proposed DSL match your needs?
   ```elixir
   parallel_step :process_order do
     step :payment, action: :charge
     step :inventory, action: :reserve
     on_complete :ship
   end
   ```
4. **Error handling strategy** - How should partial failures work?

### Documentation Needed

1. User guide for parallel workflows
2. Migration guide from sequential to parallel
3. Performance tuning guide
4. Testing guide for workflows
5. Troubleshooting common issues

---

## Appendices

### Appendix A: AshJobs Transformer Pipeline

**File:** `/home/joba/sandbox/ash_jobs/lib/ash_jobs.ex`

```elixir
transformers [
  AshJobs.Transformers.GenerateErrorActions,
  AshJobs.Transformers.BuildWorkflow,
  AshJobs.Transformers.IntegrateStateMachine,
  AshJobs.Transformers.IntegrateOban
]
```

**Execution Order:**

1. `GenerateErrorActions` - Creates error handler actions
2. `BuildWorkflow` - Injects `AshJobs.Change` into all step actions
3. `IntegrateStateMachine` - Auto-generates state_machine DSL from steps
4. `IntegrateOban` - Auto-generates ash_oban triggers for scheduling

### Appendix B: Parallel State Examples from Literature

**XState (JavaScript):**

```javascript
const machine = createMachine({
  type: "parallel",
  states: {
    upload: {
      initial: "idle",
      states: {
        idle: { on: { START: "uploading" } },
        uploading: { on: { DONE: "success" } },
        success: { type: "final" },
      },
    },
    download: {
      initial: "idle",
      states: {
        idle: { on: { START: "downloading" } },
        downloading: { on: { DONE: "success" } },
        success: { type: "final" },
      },
    },
  },
  onDone: "completed",
});
```

**SCXML (W3C Specification):**

```xml
<parallel id="processOrder">
  <state id="payment">
    <initial>
      <transition target="pendingPayment"/>
    </initial>
    <state id="pendingPayment">
      <transition event="charge" target="processing"/>
    </state>
    <state id="processing">
      <transition event="success" target="completed"/>
    </state>
    <final id="completed"/>
  </state>

  <state id="inventory">
    <initial>
      <transition target="reserved"/>
    </initial>
    <state id="reserved">
      <transition event="pick" target="picking"/>
    </state>
    <state id="picking">
      <transition event="pack" target="packed"/>
    </state>
    <final id="packed"/>
  </state>

  <transition event="done.state.processOrder" target="shipping"/>
</parallel>
```

### Appendix C: Research Sources

**Completed Research:**

- Oban documentation (https://hexdocs.pm/oban)
- Oban Pro documentation (https://getoban.pro/docs)
- AshJobs codebase (`~/sandbox/ash_jobs`)
- Parallel state patterns (Harel statecharts, SCXML, XState)

**Pending Research:**

- Hierarchical state workflows
- Fan-out/fan-in job patterns
- State machine + job queue integration
- Real-world workflow examples

---

**Document Status:** In Progress - Awaiting completion of remaining research
**Last Updated:** 2025-12-06 **Next Review:** After all research agents complete
