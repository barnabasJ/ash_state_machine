# State Machine Research: Synthesis and Recommendations for ash_state_machine

## Executive Summary

This document synthesizes comprehensive research on state machines spanning 70
years of theory and practice—from Mealy and Moore's foundational work in the
1950s through Harel's revolutionary statecharts in 1987, to modern
implementations like XState, SCXML, and UML 2.5. The research identifies key
advanced features that could significantly enhance `ash_state_machine` while
maintaining its integration with the Ash framework.

**Key Findings:**

- **Historical Foundation**: State machines evolved from simple finite automata
  to sophisticated hierarchical statecharts to address state explosion problems
- **Modern Consensus**: Industry has standardized around hierarchical states,
  parallel regions, history states, and explicit entry/exit actions
- **Proven Value**: These features provide exponential complexity reduction
  (Harel's "triple exponential reduction") in real-world systems
- **Elixir Ecosystem Gap**: Most Elixir state machine libraries lack advanced
  statechart features, presenting an opportunity for ash_state_machine

---

## 1. Current State of ash_state_machine

### Strengths

✅ **Clean DSL Integration**

- Leverages Spark DSL for declarative state machine definitions
- Seamless integration with Ash resources, actions, and changesets
- Compile-time validation through transformers and verifiers

✅ **Solid Foundation**

- Wildcard support (`:*`) for flexible transitions
- Initial state management with defaults
- Policy integration via `ValidNextState` check
- Atomic (database-level) validation support

✅ **Well-Tested**

- Comprehensive test suite covering core functionality
- Clear test patterns and edge case coverage

✅ **Production-Ready**

- Used in real projects (LogSeq MCP sync, AshJobs, etc.)
- Minimal dependencies, stable API

### Current Limitations

❌ **No Hierarchical States**

- Single flat state attribute
- Can't model parent-child state relationships
- No state nesting or composition

❌ **No Parallel States**

- Single state machine per resource
- Can't model independent concurrent concerns
- Requires multiple resources for parallel workflows

❌ **No History States**

- No built-in mechanism to remember previous states
- Manual history tracking required

❌ **Limited Action Hooks**

- No explicit entry/exit actions
- Must use generic Ash changes with manual state detection

❌ **No State Timeouts**

- No automatic timeout transitions
- Application must handle time-based state changes

❌ **No Advanced Transition Features**

- No explicit guard conditions (can use policies/validations)
- No internal transitions (all transitions exit/re-enter)
- No junction/choice pseudostates

---

## 2. Advanced Features: Analysis and Recommendations

### Feature 1: Hierarchical States (High Priority)

#### What It Provides

**Problem Solved**: State explosion from combinatorial growth

**Example**: An order processing system with payment and fulfillment substates:

```
Order States (without hierarchy):
- pending
- payment_validating
- payment_processing
- payment_completed
- payment_failed
- fulfillment_picking
- fulfillment_packing
- fulfillment_shipping
- completed
- cancelled

= 10 states with redundant transition logic
```

```
Order States (with hierarchy):
- pending
- processing
  ├─ payment
  │  ├─ validating
  │  ├─ processing
  │  └─ completed
  └─ fulfillment
     ├─ picking
     ├─ packing
     └─ shipping
- completed
- cancelled

= 4 top-level states + substates with shared transitions
```

#### Benefits for ash_state_machine

1. **Complexity Reduction**: Common transitions (e.g., cancel from any
   processing substate) defined once
2. **Better Organization**: Related states grouped together
3. **Code Reuse**: Parent-level entry/exit actions apply to all children
4. **Clearer Intent**: State hierarchy reflects business domain structure

#### Implementation Approaches

**Option A: State Path Notation (Recommended - Lowest Effort)**

Use dot-separated strings to represent hierarchical states:

```elixir
defmodule MyApp.Order do
  use Ash.Resource,
    extensions: [AshStateMachine]

  state_machine do
    initial_states ["pending"]

    transitions do
      # Enter hierarchy
      transition :start_processing,
        from: "pending",
        to: "processing.payment.validating"

      # Navigate within hierarchy
      transition :validate_payment,
        from: "processing.payment.validating",
        to: "processing.payment.processing"

      # Parent-level transition (wildcard for all substates)
      transition :cancel,
        from: "processing.*",  # Any processing substate
        to: "cancelled"
    end
  end

  # Helper functions
  def in_state?(record, parent_state) do
    String.starts_with?(record.state, "#{parent_state}.")
  end

  def current_parent_state(record) do
    record.state |> String.split(".") |> List.first()
  end
end
```

**Pros**:

- Works with existing string/atom state attributes
- Backward compatible
- Simple pattern matching for parent states
- Can use wildcards for parent-level transitions

**Cons**:

- String parsing overhead
- No compile-time validation of state paths
- Manual hierarchy management

**Option B: Composite State Attribute**

Use embedded schemas to represent hierarchy:

```elixir
defmodule MyApp.HierarchicalState do
  use Ash.Resource

  embedded_resource do
    attribute :parent, :atom
    attribute :child, :atom
    attribute :grandchild, :atom
  end
end

defmodule MyApp.Order do
  use Ash.Resource,
    extensions: [AshStateMachine]

  attributes do
    attribute :state, MyApp.HierarchicalState
  end
end
```

**Pros**:

- Structured data
- Type safety
- Full hierarchy in one attribute

**Cons**:

- Major changes to transition_state logic
- Complex query patterns
- Breaking change for existing users

**Option C: Multiple Resources with Relationships**

Parent and child state machines as separate resources:

```elixir
defmodule MyApp.Order do
  use Ash.Resource, extensions: [AshStateMachine]

  relationships do
    has_one :payment_flow, MyApp.PaymentFlow
    has_one :fulfillment_flow, MyApp.FulfillmentFlow
  end

  state_machine do
    state_attribute :parent_state
    initial_states [:pending]

    transitions do
      transition :start_processing, from: :pending, to: :processing
    end
  end
end

defmodule MyApp.PaymentFlow do
  use Ash.Resource, extensions: [AshStateMachine]

  belongs_to :order, MyApp.Order

  state_machine do
    initial_states [:validating]
    transitions do
      transition :process, from: :validating, to: :processing
    end
  end
end
```

**Pros**:

- Each level is a full AshStateMachine
- Leverages Ash relationships
- Queryable independently

**Cons**:

- Multiple database records
- Coordination complexity
- Not a "true" hierarchical state machine

#### Recommendation

**Start with Option A (State Path Notation)**:

1. Extend the DSL to optionally support hierarchical states via configuration
2. Add helpers for working with hierarchical states
3. Document patterns for hierarchical state design
4. Later consider Option B for true hierarchical state support

**Proposed DSL Extension**:

```elixir
state_machine do
  hierarchical true
  state_separator "."  # default

  initial_states ["pending"]

  # Define state hierarchy
  states do
    state :pending

    state :processing do
      state :payment do
        state :validating
        state :processing
        state :completed
      end

      state :fulfillment do
        state :picking
        state :packing
        state :shipping
      end
    end

    state :completed
    state :cancelled
  end

  transitions do
    # Hierarchical transitions
    transition :start, from: "pending", to: "processing.payment.validating"
    transition :cancel, from: "processing.*", to: "cancelled"
  end
end
```

---

### Feature 2: Parallel States (Medium Priority)

#### What It Provides

**Problem Solved**: Independent concurrent concerns without state explosion

**Example**: Multi-step document upload form

- Front document: idle → uploading → uploaded → error
- Back document: idle → uploading → uploaded → error
- Form submission: enabled only when both uploaded

Without parallel states: 4 × 4 = 16 combined states With parallel states: 4 + 4
= 8 independent states

#### Benefits for ash_state_machine

1. **Prevents Combinatorial Explosion**: Model independent concerns separately
2. **Clearer Semantics**: Each region represents one independent aspect
3. **Easier Coordination**: Check combined state for overall readiness
4. **Better Testing**: Test each region independently

#### Implementation Approaches

**Option A: Multiple State Attributes (Recommended)**

```elixir
defmodule MyApp.DocumentUpload do
  use Ash.Resource,
    extensions: [AshStateMachine]

  attributes do
    attribute :front_state, :atom
    attribute :back_state, :atom
  end

  # Multiple state machine blocks (would require DSL extension)
  state_machine :front_upload do
    state_attribute :front_state
    initial_states [:idle]

    transitions do
      transition :upload, from: :idle, to: :uploading
      transition :success, from: :uploading, to: :uploaded
      transition :error, from: :uploading, to: :error
    end
  end

  state_machine :back_upload do
    state_attribute :back_state
    initial_states [:idle]

    transitions do
      transition :upload, from: :idle, to: :uploading
      transition :success, from: :uploading, to: :uploaded
      transition :error, from: :uploading, to: :error
    end
  end

  # Coordination logic
  def ready_for_submission?(record) do
    record.front_state == :uploaded and record.back_state == :uploaded
  end
end
```

**Pros**:

- Each region is independent
- Easy to query and test
- Simple database schema

**Cons**:

- Requires supporting multiple `state_machine` blocks per resource
- Coordination logic needed for cross-region constraints

**Option B: Separate Related Resources**

```elixir
defmodule MyApp.FormSubmission do
  use Ash.Resource

  relationships do
    has_one :front_upload, MyApp.FrontUpload
    has_one :back_upload, MyApp.BackUpload
  end

  aggregates do
    count :uploaded_documents, [:front_upload, :back_upload] do
      filter expr(state == :uploaded)
    end
  end

  def ready_for_submission?(record) do
    record = Ash.load!(record, [:front_upload, :back_upload])
    record.front_upload.state == :uploaded and
    record.back_upload.state == :uploaded
  end
end

defmodule MyApp.FrontUpload do
  use Ash.Resource, extensions: [AshStateMachine]
  belongs_to :form_submission, MyApp.FormSubmission

  state_machine do
    # ... full state machine ...
  end
end
```

**Pros**:

- Each region is a full AshStateMachine
- Works with current implementation
- Leverages Ash relationships and aggregates

**Cons**:

- Multiple database records
- More complex queries

#### Recommendation

**Use Option B (Separate Resources) with current implementation**:

- Document the pattern for modeling parallel concerns
- Provide examples of coordination logic
- Consider Option A as a future enhancement when multiple state machines per
  resource are needed

---

### Feature 3: History States (Medium Priority)

#### What It Provides

**Problem Solved**: Resuming state after interruption

**Example**: Application with settings menu

- User navigates: Main → Settings → Display → Audio
- User exits to: Away
- User returns: Should resume at Audio (where they were)

#### Benefits for ash_state_machine

1. **Better UX**: Users resume where they left off
2. **Pause/Resume Patterns**: Natural for long-running workflows
3. **Context Preservation**: Maintain navigation state across sessions

#### Implementation Approaches

**Option A: Manual History Tracking (Current Workaround)**

```elixir
defmodule MyApp.Application do
  use Ash.Resource, extensions: [AshStateMachine]

  attributes do
    attribute :state, :string
    attribute :previous_state, :string
    attribute :state_history, {:array, :string}, default: []
  end

  changes do
    # Save history before transitioning
    change fn changeset, _context ->
      if changing_state?(changeset) do
        current = changeset.data.state
        history = [current | (changeset.data.state_history || [])]

        changeset
        |> force_change_attribute(:previous_state, current)
        |> force_change_attribute(:state_history, history)
      else
        changeset
      end
    end
  end

  # Custom action for history restoration
  actions do
    update :return_with_history do
      change fn changeset, _context ->
        last_state = changeset.data.previous_state || "main"
        transition_state(changeset, last_state)
      end
    end
  end
end
```

**Pros**:

- Works with current implementation
- Full control over history management
- Can implement shallow or deep history

**Cons**:

- Manual implementation in every resource
- History can grow unbounded
- Not a standard feature

**Option B: Built-in History Support (Future Enhancement)**

```elixir
state_machine do
  enable_history true
  history_depth :shallow  # or :deep

  initial_states ["main"]

  transitions do
    transition :exit, from: "*", to: "away"

    # Special history transition
    transition :return, from: "away", to: :history
  end
end
```

Implementation would automatically track and restore previous state.

#### Recommendation

**Document Option A pattern**:

- Provide code examples for manual history tracking
- Show both shallow and deep history patterns
- Consider Option B as a future DSL enhancement

---

### Feature 4: Entry/Exit Actions (High Priority)

#### What It Provides

**Problem Solved**: Guaranteed initialization and cleanup for states

**Example**: Processing state needs timer and notifications

- Entry: Start timer, send "processing started" notification
- Exit: Stop timer, record duration, send "processing stopped"

Without entry/exit actions: Duplicate this logic on every transition into/out of
processing

#### Benefits for ash_state_machine

1. **DRY Principle**: Define actions once per state, not per transition
2. **Safety**: Guaranteed execution regardless of transition path
3. **Clarity**: Obvious what happens when entering/exiting a state

#### Current Workaround

Use Ash changes with manual state detection:

```elixir
changes do
  change fn changeset, _context ->
    old_state = changeset.data.state
    new_state = get_change(changeset, :state)

    # Entry action for :processing
    changeset = if new_state == :processing do
      changeset
      |> force_change_attribute(:processing_started_at, DateTime.utc_now())
      |> after_action(fn _cs, record ->
        send_notification(record, "Processing started")
        {:ok, record}
      end)
    else
      changeset
    end

    # Exit action for :processing
    if old_state == :processing and new_state != :processing do
      changeset
      |> force_change_attribute(:processing_completed_at, DateTime.utc_now())
      |> after_action(fn _cs, record ->
        cleanup_resources(record)
        {:ok, record}
      end)
    else
      changeset
    end
  end
end
```

**Cons**: Verbose, manual state tracking, not declarative

#### Proposed Enhancement

**DSL Extension for Entry/Exit Actions**:

```elixir
state_machine do
  initial_states [:pending]

  # Define states with actions
  states do
    state :pending do
      on_entry [:log_pending, :set_timestamp]
      on_exit [:cleanup_pending]
    end

    state :processing do
      on_entry [:start_timer, :notify_started]
      on_exit [:stop_timer, :record_duration]
    end

    state :completed do
      on_entry [:mark_completed, :send_notification]
    end
  end

  transitions do
    transition :start, from: :pending, to: :processing
    transition :complete, from: :processing, to: :completed
  end
end

# Define action functions
defp start_timer(changeset, _state) do
  force_change_attribute(changeset, :started_at, DateTime.utc_now())
end

defp notify_started(changeset, _state) do
  after_action(changeset, fn _cs, record ->
    Notifications.send(record, "Processing started")
    {:ok, record}
  end)
end
```

#### Recommendation

**High priority enhancement**:

1. Extend DSL to support state definitions with entry/exit actions
2. Implement in transformer to inject these as Ash changes
3. Ensure proper execution order (exit → transition → entry)

---

### Feature 5: Guard Conditions (Medium Priority)

#### What It Provides

**Problem Solved**: Conditional transitions based on runtime state

**Example**: Order approval

- Can approve if: total > 0 AND payment_method present
- Otherwise: Reject

#### Current Workaround

Use Ash policies or validations:

```elixir
# Using policies
policies do
  policy action(:approve) do
    authorize_if expr(total > 0 and payment_method != nil)
  end
end

# Or using validations
validations do
  validate changing(:state) do
    validate fn changeset, _context ->
      if transitioning_to?(changeset, :approved) do
        # Check conditions
        if valid_for_approval?(changeset) do
          :ok
        else
          {:error, "Cannot approve: conditions not met"}
        end
      else
        :ok
      end
    end
  end
end
```

#### Proposed Enhancement

**Add guard support to transitions**:

```elixir
state_machine do
  transitions do
    transition :approve,
      from: :pending,
      to: :approved,
      guards: [
        {__MODULE__, :total_valid?},
        {__MODULE__, :payment_method_present?}
      ]
  end
end

def total_valid?(record, _changeset) do
  record.total > 0
end

def payment_method_present?(record, _changeset) do
  not is_nil(record.payment_method)
end
```

#### Recommendation

**Medium priority enhancement**:

- Add `guards` option to transition schema
- Evaluate guards before allowing transition
- Provide clear error messages when guards fail

---

### Feature 6: State Timeouts (Low Priority)

#### What It Provides

**Problem Solved**: Automatic transitions after time delays

**Example**: Session timeout

- After 30 minutes in "active" state → transition to "expired"

#### Implementation Approach

This is complex in a database-backed system. Options:

1. **Application-level**: Use a background job scheduler (Oban)
2. **Database-level**: PostgreSQL triggers with pg_cron
3. **Process-level**: GenServer with timers (not suitable for distributed
   systems)

#### Recommendation

**Low priority - document pattern with Oban**:

```elixir
defmodule MyApp.SessionTimeoutWorker do
  use Oban.Worker

  @impl Oban.Worker
  def perform(%{args: %{"session_id" => session_id}}) do
    session = MyApp.Session.get!(session_id)

    if session.state == :active do
      MyApp.Session.expire!(session)
    end

    :ok
  end
end

# When entering :active state
changes do
  change fn changeset, _context ->
    if new_state(changeset) == :active do
      after_action(changeset, fn _cs, record ->
        # Schedule timeout
        %{session_id: record.id}
        |> SessionTimeoutWorker.new(schedule_in: {30, :minutes})
        |> Oban.insert()

        {:ok, record}
      end)
    else
      changeset
    end
  end
end
```

---

## 3. Implementation Roadmap

### Phase 1: Foundation (High Priority, Low Effort)

**Goal**: Add declarative entry/exit actions and improve documentation

**Tasks**:

1. Extend DSL to support state definitions with entry/exit actions
2. Implement transformer to convert entry/exit actions to Ash changes
3. Add guard conditions to transitions
4. Document hierarchical state patterns (using string notation)
5. Document parallel state patterns (using separate resources)
6. Add comprehensive examples to documentation

**Estimated Effort**: 2-3 weeks **Impact**: High - addresses most common use
cases

### Phase 2: Hierarchical States (High Priority, Medium Effort)

**Goal**: Native support for hierarchical states

**Tasks**:

1. Extend DSL with `states` section for defining hierarchy
2. Support state path notation (dot-separated strings)
3. Enhance wildcard matching for parent-level transitions
4. Add helper functions for working with hierarchical states
5. Update transformers to validate hierarchical state paths
6. Add comprehensive tests for hierarchical transitions
7. Create migration guide for existing users

**Estimated Effort**: 4-6 weeks **Impact**: Very High - enables complex workflow
modeling

### Phase 3: History and Advanced Features (Medium Priority, Medium Effort)

**Goal**: Built-in history state support and internal transitions

**Tasks**:

1. Add `enable_history` configuration option
2. Implement automatic history tracking in transformers
3. Add special `:history` transition target
4. Support both shallow and deep history modes
5. Add internal transitions (don't exit/re-enter state)
6. Enhance visualization (mermaid diagrams with hierarchy)

**Estimated Effort**: 3-4 weeks **Impact**: Medium - valuable for specific use
cases

### Phase 4: Parallel States (Low Priority, High Effort)

**Goal**: Multiple state machines per resource

**Tasks**:

1. Extend DSL to support multiple `state_machine` blocks
2. Each block specifies its own `state_attribute`
3. Update transformers to handle multiple state machines
4. Add coordination helpers for checking combined state
5. Update Info module for querying specific state machines
6. Comprehensive testing for parallel state interactions

**Estimated Effort**: 6-8 weeks **Impact**: Medium - useful for specific
scenarios, can be worked around with multiple resources

---

## 4. Comparison with Other Libraries

### XState (JavaScript/TypeScript)

**Strengths**:

- Full statechart implementation (hierarchy, parallel, history)
- Visual editor and tooling (Stately.ai)
- Actor model integration
- Large ecosystem and community

**Lessons for ash_state_machine**:

- Declarative DSL is crucial for usability
- Visualization tools greatly improve understanding
- Entry/exit actions are heavily used in practice
- Guard conditions are essential for real-world apps

### gen_statem (Erlang/OTP)

**Strengths**:

- Battle-tested in production systems
- Process-based (good for long-running state machines)
- Callback-based API
- Excellent for network protocols and servers

**Lessons for ash_state_machine**:

- State machines work well in BEAM ecosystem
- Integration with supervision trees is valuable
- Timeout handling is important for reactive systems

**Key Difference**: gen_statem is process-based, ash_state_machine is data-based
(database-backed)

### Spring State Machine (Java)

**Strengths**:

- Enterprise-grade features
- Comprehensive guard and action support
- Deferred events
- Integration with Spring ecosystem

**Lessons for ash_state_machine**:

- Guard conditions are table stakes
- Entry/exit actions reduce boilerplate significantly
- Good error messages are critical

### Existing Elixir Libraries

**ecto_state_machine**: Simple FSM for Ecto, no advanced features
**gen_state_machine**: GenServer-based, not database-backed **machinery**: Basic
state machine with callbacks, unmaintained

**Gap**: No Elixir library provides full statechart features with database
backing

**Opportunity**: ash_state_machine is uniquely positioned to be the premier
database-backed statechart library in Elixir

---

## 5. Design Principles and Best Practices

### Principles from Research

1. **Declarative Over Imperative**: DSL should express intent, not
   implementation
2. **Compile-Time Validation**: Catch errors before runtime
3. **Integration Not Isolation**: Leverage Ash ecosystem (policies, validations,
   changes)
4. **Backward Compatibility**: Don't break existing users
5. **Opt-In Complexity**: Advanced features should be optional

### Recommended Patterns

#### Pattern 1: Hierarchical States for Shared Behavior

```elixir
state_machine do
  hierarchical true

  states do
    state :pending

    # Common processing behaviors
    state :processing do
      on_entry [:lock_resource, :start_monitoring]
      on_exit [:unlock_resource, :stop_monitoring]

      # Substates inherit parent behavior
      state :validating
      state :executing
      state :finalizing
    end

    state :completed
  end

  transitions do
    # All processing substates can be cancelled
    transition :cancel, from: "processing.*", to: :cancelled
  end
end
```

#### Pattern 2: Parallel States for Independent Concerns

```elixir
# Use separate resources for truly independent state machines
defmodule Order do
  relationships do
    has_one :payment_flow, PaymentFlow
    has_one :fulfillment_flow, FulfillmentFlow
  end

  def can_complete?(order) do
    order = Ash.load!(order, [:payment_flow, :fulfillment_flow])
    order.payment_flow.state == :completed and
    order.fulfillment_flow.state == :ready
  end
end
```

#### Pattern 3: History for Navigation

```elixir
# Save history when exiting major states
changes do
  change fn changeset, _context ->
    if exiting_important_state?(changeset) do
      force_change_attribute(changeset, :previous_state, changeset.data.state)
    else
      changeset
    end
  end
end

# Restore with custom action
actions do
  update :return_to_previous do
    change fn changeset, _context ->
      previous = changeset.data.previous_state || initial_state()
      transition_state(changeset, previous)
    end
  end
end
```

#### Pattern 4: Entry/Exit Actions for Lifecycle

```elixir
# Proposed DSL
states do
  state :processing do
    on_entry [
      :record_start_time,
      :allocate_resources,
      :send_started_notification
    ]
    on_exit [
      :record_end_time,
      :release_resources,
      :send_completed_notification
    ]
  end
end
```

### Anti-Patterns to Avoid

❌ **Giant Flat State Machines**: Use hierarchy to organize ❌ **State
Explosion**: Use parallel states for independent concerns ❌ **Duplicated
Transition Logic**: Use parent-level transitions or entry/exit actions ❌
**Manual State Tracking Everywhere**: Let the framework handle state management
❌ **Mixing Business Logic with State Logic**: Keep state transitions focused on
state

---

## 6. Integration with Ash Ecosystem

### Leveraging Existing Ash Features

**Policies for Authorization**:

```elixir
policies do
  policy action(:approve) do
    # Guard condition via policy
    authorize_if expr(total > 0)
  end
end
```

**Validations for State Constraints**:

```elixir
validations do
  validate changing(:state) do
    # Ensure prerequisites are met
    validate fn changeset, _context ->
      if transitioning_to_approved?(changeset) do
        check_prerequisites(changeset)
      else
        :ok
      end
    end
  end
end
```

**Aggregates for Coordination**:

```elixir
aggregates do
  count :completed_subtasks, :subtasks do
    filter expr(state == :completed)
  end
end

# Use in guard
def can_complete?(record) do
  record.completed_subtasks == record.total_subtasks
end
```

**Reactor for Complex Workflows**:

```elixir
defmodule OrderWorkflow do
  use Ash.Reactor

  reactor do
    create_step :create_order, Order, inputs: %{state: :pending}
    update_step :start_processing, Order do
      record result(:create_order)
      inputs %{state: :processing}
    end
  end
end
```

### New Integration Opportunities

**AshJobs Integration**:

- State machine transitions trigger background jobs
- Jobs can advance state machine states
- Automatic state machine generation from workflows

**AshGraphQL/AshJsonApi**:

- Expose state transitions as mutations
- Query possible next states for UI
- Generate OpenAPI docs with state machine info

**LiveView Integration**:

- Real-time state updates
- UI components that reflect current state
- Visual state machine display

---

## 7. Testing Strategies

### Testing Hierarchical States

```elixir
describe "hierarchical state transitions" do
  test "parent-level transition works from any substate" do
    for substate <- ["processing.payment", "processing.fulfillment"] do
      order = create_order!(state: substate)
      {:ok, order} = Order.cancel!(order)
      assert order.state == "cancelled"
    end
  end

  test "entering parent state enters initial substate" do
    order = create_order!(state: "pending")
    {:ok, order} = Order.start_processing!(order)
    assert order.state == "processing.payment.validating"
  end
end
```

### Testing Parallel States

```elixir
describe "parallel state coordination" do
  test "can update one region without affecting another" do
    form = create_form!()
    {:ok, form} = Form.upload_front!(form)

    assert form.front_state == :uploaded
    assert form.back_state == :idle
  end

  test "form ready only when all regions complete" do
    form = create_form!()
    refute Form.ready?(form)

    {:ok, form} = Form.upload_front!(form)
    refute Form.ready?(form)

    {:ok, form} = Form.upload_back!(form)
    assert Form.ready?(form)
  end
end
```

### Property-Based Testing

```elixir
property "state machine invariants hold for any transition sequence" do
  forall transitions <- list(valid_transition()) do
    order = create_order!()
    final_order = apply_transitions(order, transitions)

    # Invariants
    assert final_order.state in all_valid_states()

    if final_order.state == "completed" do
      assert final_order.completed_at != nil
    end
  end
end
```

---

## 8. Migration Path for Existing Users

### Ensuring Backward Compatibility

**Principle**: All new features are opt-in

**Strategy**:

1. Existing state machines work unchanged
2. New features require explicit configuration
3. Deprecation warnings for any breaking changes
4. Migration guides with code examples

### Example Migration: Adding Entry/Exit Actions

**Before (current)**:

```elixir
state_machine do
  initial_states [:pending]

  transitions do
    transition :start, from: :pending, to: :processing
  end
end

changes do
  change fn changeset, _context ->
    if new_state(changeset) == :processing do
      # Entry action logic here
    end
  end
end
```

**After (with new DSL)**:

```elixir
state_machine do
  initial_states [:pending]

  states do
    state :processing do
      on_entry [:start_processing_timer]
    end
  end

  transitions do
    transition :start, from: :pending, to: :processing
  end
end

defp start_processing_timer(changeset, _state) do
  force_change_attribute(changeset, :started_at, DateTime.utc_now())
end
```

Both work, new DSL is cleaner and more maintainable.

---

## 9. Documentation Needs

### User Guides

1. **Getting Started**: Basic state machine setup
2. **Hierarchical States**: When and how to use
3. **Parallel States**: Patterns for multiple resources
4. **Entry/Exit Actions**: Lifecycle management
5. **Guards and Conditions**: Conditional transitions
6. **History States**: Pause and resume patterns
7. **Testing**: Comprehensive testing strategies
8. **Migration**: Upgrading existing state machines

### API Documentation

1. Enhanced module docs with statechart concepts
2. Inline examples for every DSL option
3. Common patterns and anti-patterns
4. Performance considerations
5. Database schema best practices

### Visual Documentation

1. Mermaid diagram generation (already exists)
2. Interactive state machine viewer (future)
3. Transition matrix visualization
4. State coverage reports for testing

---

## 10. Conclusion and Next Steps

### Key Recommendations

**Immediate (Phase 1)**:

1. ✅ Add entry/exit actions to DSL
2. ✅ Add guard conditions to transitions
3. ✅ Document hierarchical state patterns
4. ✅ Document parallel state patterns
5. ✅ Improve examples and guides

**Near-Term (Phase 2)**:

1. ✅ Implement native hierarchical state support
2. ✅ Enhance wildcard matching for hierarchy
3. ✅ Add state path helper functions
4. ✅ Comprehensive testing for hierarchical states

**Long-Term (Phases 3-4)**:

1. ⏸ Built-in history state support
2. ⏸ Multiple state machines per resource (parallel states)
3. ⏸ Visual state machine editor
4. ⏸ Integration with AshJobs workflows

### Success Metrics

- **Adoption**: Increased usage in Ash ecosystem projects
- **Complexity Reduction**: Fewer states needed for complex workflows
- **Code Quality**: Less duplicated transition logic
- **Developer Experience**: Faster implementation of state-based features
- **Community**: Contributions and extensions from users

### Final Thoughts

The research demonstrates that **hierarchical states and entry/exit actions
provide the highest value for the lowest implementation cost**. These features
alone would position `ash_state_machine` as one of the most sophisticated
database-backed state machine libraries in any language ecosystem.

The path forward is clear:

1. Start with declarative entry/exit actions (high value, low risk)
2. Add hierarchical state support (transformative feature)
3. Document patterns for parallel states (works with current implementation)
4. Consider advanced features (history, internal transitions) as community needs
   emerge

With these enhancements, `ash_state_machine` will be uniquely positioned as
**the premier choice for complex, production-ready state machines in Elixir**,
combining the theoretical rigor of Harel's statecharts with the practical
elegance of the Ash framework.

---

## Appendix A: Glossary

- **Statechart**: Extension of FSM with hierarchy, concurrency, and
  communication (Harel 1987)
- **Compound State**: State containing substates (hierarchical state)
- **Parallel State**: State with multiple orthogonal regions active
  simultaneously
- **History State**: Pseudostate that restores previous substate configuration
- **Entry Action**: Action executed when entering a state
- **Exit Action**: Action executed when leaving a state
- **Guard Condition**: Boolean condition that must be true for transition to
  occur
- **Run-to-Completion**: Event processing completes before next event is handled
- **State Explosion**: Exponential growth in states from combinatorial
  possibilities

## Appendix B: References

See individual research reports for comprehensive citations:

- Historical Research Report (70+ sources)
- Specifications Research Report (50+ sources)
- Advanced Features Research Report (80+ sources)
- Codebase Analysis Report (detailed code walkthrough)

**Key Papers**:

- Harel, D. (1987). "Statecharts: A Visual Formalism for Complex Systems"
- W3C SCXML Specification (2015)
- UML 2.5 State Machine Specification

**Key Implementations**:

- XState (JavaScript): https://xstate.js.org
- SCXML: https://www.w3.org/TR/scxml/
- Quantum Programming (C/C++): https://www.state-machine.com

**Elixir Ecosystem**:

- Ash Framework: https://ash-hq.org
- AshStateMachine: https://github.com/ash-project/ash_state_machine
