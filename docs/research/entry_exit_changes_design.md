# Entry/Exit Changes Design Document

## Overview

Entry/exit changes provide declarative lifecycle hooks for state machine states,
allowing you to automatically run changes when entering or exiting a state. This
eliminates the need for manual state-change detection and ensures lifecycle
logic is always executed consistently.

## Motivation

### Problem: Manual State Detection is Error-Prone

Currently, to run code when entering a state, you must manually detect state
transitions:

```elixir
defmodule MyApp.Order do
  use Ash.Resource, extensions: [AshStateMachine]

  state_machine do
    transitions do
      transition :start_processing, from: :pending, to: :processing
      transition :resume_processing, from: :paused, to: :processing
      transition :retry_processing, from: :failed, to: :processing
    end
  end

  changes do
    # Manual detection - must check every transition
    change fn changeset, _context ->
      old_state = changeset.data.state
      new_state = Ash.Changeset.get_attribute(changeset, :state)

      if old_state != :processing and new_state == :processing do
        # Entry logic duplicated across all transitions
        changeset
        |> force_change_attribute(:started_at, DateTime.utc_now())
        |> after_action(fn _cs, record ->
          MyApp.ProcessingMonitor.start(record.id)
          {:ok, record}
        end)
      else
        changeset
      end
    end
  end
end
```

**Problems:**

- ❌ **Verbose**: Same detection logic repeated for every state
- ❌ **Error-prone**: Easy to forget a transition path when adding new
  transitions
- ❌ **Not DRY**: Entry/exit logic scattered across multiple change blocks
- ❌ **Hard to maintain**: Changing lifecycle behavior requires finding all
  relevant checks
- ❌ **Poor readability**: Business logic mixed with plumbing code

### Solution: Declarative Entry/Exit Changes

With entry/exit changes, you declare lifecycle hooks directly on state
definitions:

```elixir
defmodule MyApp.Order do
  use Ash.Resource, extensions: [AshStateMachine]

  state_machine do
    states do
      state :processing do
        on_entry [
          MyApp.Changes.RecordStartTime,
          MyApp.Changes.StartMonitoring
        ]

        on_exit [
          MyApp.Changes.RecordEndTime,
          MyApp.Changes.StopMonitoring
        ]
      end
    end

    transitions do
      transition :start_processing, from: :pending, to: :processing
      transition :resume_processing, from: :paused, to: :processing
      transition :retry_processing, from: :failed, to: :processing
      # Entry changes run automatically for ALL transitions to :processing
    end
  end
end
```

**Benefits:**

- ✅ **Guaranteed execution**: Entry/exit changes run for every transition
  into/out of the state
- ✅ **Single source of truth**: All lifecycle logic for a state defined in one
  place
- ✅ **Declarative**: Clear intent - just looking at the state shows what
  happens
- ✅ **Maintainable**: Add transitions without touching entry/exit logic
- ✅ **Correct order**: Framework guarantees execution order (exit → transition
  → entry)

## DSL Syntax

### State Definition with Entry/Exit Changes

```elixir
state_machine do
  states do
    state :state_name do
      on_entry [
        # List of changes to run when entering this state
      ]

      on_exit [
        # List of changes to run when exiting this state
      ]
    end
  end
end
```

### Supported Change Formats

Entry/exit changes support the same formats as regular Ash action changes:

#### 1. Change Module

```elixir
state :processing do
  on_entry [MyApp.Changes.RecordStartTime]
end
```

#### 2. Change Module with Options

```elixir
state :processing do
  on_entry [
    {MyApp.Changes.RecordTimestamp, field: :processing_started_at},
    {MyApp.Changes.SendNotification, event: :started, to: :warehouse}
  ]
end
```

#### 3. MFA Tuple (Module, Function, Arguments)

```elixir
state :processing do
  on_entry [
    {MyApp.OrderLifecycle, :on_processing_start, [notify: true]}
  ]
end
```

#### 4. Anonymous Function (for simple cases)

```elixir
state :processing do
  on_entry [
    fn changeset, _context ->
      Ash.Changeset.force_change_attribute(changeset, :locked, true)
    end
  ]
end
```

### Complete Example

```elixir
defmodule MyApp.Order do
  use Ash.Resource, extensions: [AshStateMachine]

  state_machine do
    initial_states [:draft]

    states do
      state :draft

      state :pending_payment do
        on_entry [
          MyApp.Changes.GeneratePaymentLink,
          {MyApp.Changes.SetTimeout, minutes: 30},
          {MyApp.Changes.SendNotification,
            template: :payment_required,
            to: :customer
          }
        ]

        on_exit [
          MyApp.Changes.CancelPaymentTimeout
        ]
      end

      state :processing do
        on_entry [
          MyApp.Changes.LockInventory,
          {MyApp.Changes.RecordTimestamp, field: :processing_started_at},
          {MyApp.Changes.AllocateResources, pool: :warehouse},
          {MyApp.Changes.SendNotification,
            event: :processing_started,
            to: [:customer, :warehouse]
          }
        ]

        on_exit [
          MyApp.Changes.UnlockInventory,
          {MyApp.Changes.RecordTimestamp, field: :processing_completed_at},
          MyApp.Changes.ReleaseResources
        ]
      end

      state :shipped do
        on_entry [
          MyApp.Changes.GenerateTrackingNumber,
          {MyApp.Changes.SendNotification,
            template: :shipped_with_tracking,
            to: :customer
          }
        ]
      end

      state :cancelled do
        on_entry [
          MyApp.Changes.RefundPayment,
          MyApp.Changes.ReleaseInventory,
          {MyApp.Changes.SendNotification, template: :order_cancelled}
        ]
      end
    end

    transitions do
      transition :submit, from: :draft, to: :pending_payment
      transition :pay, from: :pending_payment, to: :processing
      transition :ship, from: :processing, to: :shipped
      transition :cancel, from: [:draft, :pending_payment, :processing], to: :cancelled
    end
  end
end
```

## Creating Reusable Change Modules

### Basic Change Module

```elixir
defmodule MyApp.Changes.RecordTimestamp do
  @moduledoc """
  Records a timestamp when entering or exiting a state.

  ## Options

  - `:field` - The attribute to set (required)
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, opts, _context) do
    field = Keyword.fetch!(opts, :field)
    Ash.Changeset.force_change_attribute(changeset, field, DateTime.utc_now())
  end
end

# Usage:
state :processing do
  on_entry [{MyApp.Changes.RecordTimestamp, field: :processing_started_at}]
  on_exit [{MyApp.Changes.RecordTimestamp, field: :processing_completed_at}]
end
```

### Change with Side Effects

```elixir
defmodule MyApp.Changes.SendNotification do
  @moduledoc """
  Sends a notification when entering or exiting a state.

  ## Options

  - `:event` - Event name to send (optional)
  - `:template` - Notification template to use (optional)
  - `:to` - Recipient(s) - atom or list of atoms (required)
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, opts, _context) do
    event = opts[:event]
    template = opts[:template]
    to = Keyword.fetch!(opts, :to)

    Ash.Changeset.after_action(changeset, fn _changeset, record ->
      recipients = List.wrap(to)

      Enum.each(recipients, fn recipient ->
        if template do
          MyApp.Notifier.send_template(record, template, recipient)
        else
          MyApp.Notifier.send_event(record, event, recipient)
        end
      end)

      {:ok, record}
    end)
  end
end

# Usage:
state :shipped do
  on_entry [
    {MyApp.Changes.SendNotification,
      template: :order_shipped,
      to: [:customer, :warehouse]
    }
  ]
end
```

### Change with Resource Allocation

```elixir
defmodule MyApp.Changes.AllocateResources do
  @moduledoc """
  Allocates resources from a pool when entering a state.

  ## Options

  - `:pool` - Resource pool identifier (required)
  - `:priority` - Allocation priority: `:low`, `:normal`, `:high` (default: `:normal`)
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, opts, _context) do
    pool = Keyword.fetch!(opts, :pool)
    priority = Keyword.get(opts, :priority, :normal)

    Ash.Changeset.after_action(changeset, fn _changeset, record ->
      case MyApp.ResourcePool.allocate(record.id, pool: pool, priority: priority) do
        {:ok, allocation} ->
          # Store allocation ID on the record
          updated_record = %{record | allocation_id: allocation.id}
          {:ok, updated_record}

        {:error, :pool_exhausted} ->
          {:error,
            Ash.Error.Invalid.exception(
              field: :state,
              message: "Cannot allocate resources: pool #{pool} exhausted"
            )
          }
      end
    end)
  end
end

defmodule MyApp.Changes.ReleaseResources do
  @moduledoc """
  Releases previously allocated resources when exiting a state.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, record ->
      if record.allocation_id do
        :ok = MyApp.ResourcePool.release(record.allocation_id)
      end

      {:ok, record}
    end)
  end
end

# Usage:
state :processing do
  on_entry [{MyApp.Changes.AllocateResources, pool: :gpu, priority: :high}]
  on_exit [MyApp.Changes.ReleaseResources]
end
```

### Conditional Change

```elixir
defmodule MyApp.Changes.ConditionalChange do
  @moduledoc """
  Runs a change only if a condition is met.

  ## Options

  - `:if` - Function that takes the record and returns boolean (required)
  - `:change` - Change module or {module, opts} to run if condition is true (required)
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, opts, context) do
    condition_fn = Keyword.fetch!(opts, :if)
    change_spec = Keyword.fetch!(opts, :change)

    if condition_fn.(changeset.data) do
      case change_spec do
        {module, change_opts} -> module.change(changeset, change_opts, context)
        module -> module.change(changeset, [], context)
      end
    else
      changeset
    end
  end
end

# Usage:
state :processing do
  on_entry [
    {MyApp.Changes.ConditionalChange,
      if: &(&1.priority == :high),
      change: {MyApp.Changes.AllocateResources, pool: :gpu}
    }
  ]
end
```

## Execution Order

Entry/exit changes execute in a guaranteed order during state transitions:

### Execution Sequence

```
Old State ──(transition)──> New State

1. Exit changes for old state (in order)
2. Transition actions (if any defined on the transition)
3. Entry changes for new state (in order)
```

### Example

```elixir
state_machine do
  states do
    state :pending do
      on_exit [
        MyApp.Changes.LogExit,           # Runs FIRST
        MyApp.Changes.CleanupPending      # Runs SECOND
      ]
    end

    state :processing do
      on_entry [
        MyApp.Changes.LogEntry,           # Runs FOURTH
        MyApp.Changes.StartProcessing     # Runs FIFTH
      ]
    end
  end

  transitions do
    transition :start_processing, from: :pending, to: :processing do
      # Any transition-specific changes would run THIRD (between exit and entry)
    end
  end
end
```

**Execution order for** `Order.start_processing!(order)`:

1. `MyApp.Changes.LogExit` (pending exit)
2. `MyApp.Changes.CleanupPending` (pending exit)
3. _(transition changes, if any)_
4. `MyApp.Changes.LogEntry` (processing entry)
5. `MyApp.Changes.StartProcessing` (processing entry)

### With Hierarchical States (Future)

When hierarchical states are implemented, execution order will be:

**Entering nested state**: Outermost → Innermost

```
Parent on_entry → Child on_entry → Grandchild on_entry
```

**Exiting nested state**: Innermost → Outermost

```
Grandchild on_exit → Child on_exit → Parent on_exit
```

## Testing Entry/Exit Changes

### Testing Change Modules

```elixir
defmodule MyApp.Changes.RecordTimestampTest do
  use ExUnit.Case

  alias MyApp.Changes.RecordTimestamp

  test "sets timestamp on specified field" do
    changeset =
      %MyApp.Order{}
      |> Ash.Changeset.new()

    result = RecordTimestamp.change(
      changeset,
      [field: :processing_started_at],
      %{}
    )

    assert result.attributes[:processing_started_at] != nil
    assert_in_delta(
      DateTime.diff(DateTime.utc_now(), result.attributes[:processing_started_at]),
      0,
      1
    )
  end

  test "raises if field option not provided" do
    changeset = Ash.Changeset.new(%MyApp.Order{})

    assert_raise KeyError, fn ->
      RecordTimestamp.change(changeset, [], %{})
    end
  end
end
```

### Testing State Transitions with Entry/Exit

```elixir
defmodule MyApp.OrderTest do
  use ExUnit.Case

  describe "entering processing state" do
    test "records start timestamp" do
      order = create_order!(state: :pending)

      {:ok, order} = MyApp.Order.start_processing!(order)

      assert order.state == :processing
      assert order.processing_started_at != nil
    end

    test "allocates resources" do
      order = create_order!(state: :pending)

      {:ok, order} = MyApp.Order.start_processing!(order)

      assert order.allocation_id != nil
      assert MyApp.ResourcePool.allocated?(order.allocation_id)
    end

    test "sends notification" do
      order = create_order!(state: :pending)

      {:ok, _order} = MyApp.Order.start_processing!(order)

      assert_received {:notification_sent, :processing_started}
    end

    test "all entry changes run regardless of transition path" do
      # Test different paths to :processing
      for {action, initial_state} <- [
        {:start_processing, :pending},
        {:resume_processing, :paused},
        {:retry_processing, :failed}
      ] do
        order = create_order!(state: initial_state)

        {:ok, order} = apply(MyApp.Order, action, [order])

        # All entry changes should have run
        assert order.processing_started_at != nil
        assert order.allocation_id != nil
      end
    end
  end

  describe "exiting processing state" do
    test "records end timestamp" do
      order = create_order!(state: :processing)

      {:ok, order} = MyApp.Order.ship!(order)

      assert order.state == :shipped
      assert order.processing_completed_at != nil
    end

    test "releases resources" do
      order = create_order!(state: :processing, allocation_id: "alloc-123")

      {:ok, _order} = MyApp.Order.ship!(order)

      refute MyApp.ResourcePool.allocated?("alloc-123")
    end
  end
end
```

### Property-Based Testing

```elixir
defmodule MyApp.OrderPropertyTest do
  use ExUnit.Case
  use PropCheck

  property "entry changes always run when entering a state" do
    forall state_sequence <- list(valid_state_transition()) do
      order = create_order!()
      final_order = apply_transitions(order, state_sequence)

      # Invariant: if ended in :processing, entry changes must have run
      if final_order.state == :processing do
        assert final_order.processing_started_at != nil
        assert final_order.allocation_id != nil
      end

      true
    end
  end

  property "exit changes always run when leaving a state" do
    forall state_sequence <- list(valid_state_transition()) do
      order = create_order!(state: :processing, allocation_id: "test-alloc")
      final_order = apply_transitions(order, state_sequence)

      # Invariant: if left :processing, exit changes must have run
      if final_order.state != :processing do
        assert final_order.processing_completed_at != nil
        refute MyApp.ResourcePool.allocated?("test-alloc")
      end

      true
    end
  end
end
```

## Implementation Details

### DSL Schema

The `state` entity is extended to support `on_entry` and `on_exit`:

```elixir
@state %Spark.Dsl.Entity{
  name: :state,
  args: [:name],
  schema: [
    name: [
      type: :atom,
      required: true,
      doc: "The name of the state"
    ],
    on_entry: [
      type: {:list, {:or, [
        :atom,                                    # Module
        {:tuple, [:atom, :keyword_list]},         # {Module, opts}
        {:tuple, [:atom, :atom, :list]},          # {Module, :function, [args]}
        {:fun, 2}                                 # fn changeset, context -> ... end
      ]}},
      default: [],
      doc: """
      Changes to run when entering this state.

      Supports the same formats as action changes:
      - Change module: `MyApp.Changes.DoSomething`
      - Change module with options: `{MyApp.Changes.DoSomething, option: value}`
      - MFA tuple: `{MyModule, :function, [args]}`
      - Anonymous function: `fn changeset, context -> changeset end`

      Entry changes execute in the order specified, after all exit changes
      from the previous state.
      """
    ],
    on_exit: [
      type: {:list, {:or, [
        :atom,
        {:tuple, [:atom, :keyword_list]},
        {:tuple, [:atom, :atom, :list]},
        {:fun, 2}
      ]}},
      default: [],
      doc: """
      Changes to run when exiting this state (same format as on_entry).

      Exit changes execute in the order specified, before entry changes
      for the new state.
      """
    ]
  ]
}
```

### Transformer

A transformer generates the change that runs entry/exit changes:

```elixir
defmodule AshStateMachine.Transformers.InjectEntryExitChanges do
  @moduledoc """
  Injects a change that runs entry/exit changes based on state transitions.

  This transformer adds `AshStateMachine.BuiltinChanges.RunEntryExitChanges`
  to the resource's global changes, which detects state transitions and
  executes the appropriate entry/exit changes.
  """

  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer

  def transform(dsl_state) do
    # Check if any states have entry/exit changes defined
    states = AshStateMachine.Info.state_machine_states(dsl_state)
    has_entry_exit_changes? =
      Enum.any?(states, fn state ->
        state.on_entry != [] or state.on_exit != []
      end)

    if has_entry_exit_changes? do
      # Add the built-in change
      {:ok,
        Ash.Resource.Builder.add_change(
          dsl_state,
          AshStateMachine.BuiltinChanges.RunEntryExitChanges
        )
      }
    else
      {:ok, dsl_state}
    end
  end
end
```

### Built-in Change Implementation

```elixir
defmodule AshStateMachine.BuiltinChanges.RunEntryExitChanges do
  @moduledoc """
  Executes entry/exit changes based on state transitions.

  This change is automatically injected by the transformer when states
  have entry/exit changes defined.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, context) do
    state_attribute = AshStateMachine.Info.state_machine_state_attribute!(changeset.resource)

    old_state = Map.get(changeset.data, state_attribute)
    new_state = Ash.Changeset.get_attribute(changeset, state_attribute)

    # Only run if state changed
    if old_state != new_state do
      states = AshStateMachine.Info.state_machine_states(changeset.resource)

      changeset
      |> run_exit_changes(old_state, states, context)
      |> run_entry_changes(new_state, states, context)
    else
      changeset
    end
  end

  defp run_exit_changes(changeset, nil, _states, _context), do: changeset
  defp run_exit_changes(changeset, old_state, states, context) do
    case Enum.find(states, &(&1.name == old_state)) do
      %{on_exit: exit_changes} when exit_changes != [] ->
        run_changes(changeset, exit_changes, context)

      _ ->
        changeset
    end
  end

  defp run_entry_changes(changeset, nil, _states, _context), do: changeset
  defp run_entry_changes(changeset, new_state, states, context) do
    case Enum.find(states, &(&1.name == new_state)) do
      %{on_entry: entry_changes} when entry_changes != [] ->
        run_changes(changeset, entry_changes, context)

      _ ->
        changeset
    end
  end

  defp run_changes(changeset, change_specs, context) do
    Enum.reduce(change_specs, changeset, fn change_spec, changeset ->
      run_single_change(changeset, change_spec, context)
    end)
  end

  defp run_single_change(changeset, change_spec, context) do
    case change_spec do
      # Module: MyApp.Changes.DoSomething
      module when is_atom(module) and not is_nil(module) ->
        module.change(changeset, [], context)

      # Module with options: {MyApp.Changes.DoSomething, option: value}
      {module, opts} when is_atom(module) and is_list(opts) ->
        module.change(changeset, opts, context)

      # MFA: {MyModule, :function, [args]}
      {module, function, args} when is_atom(module) and is_atom(function) ->
        apply(module, function, [changeset | args])

      # Anonymous function: fn changeset, context -> changeset end
      fun when is_function(fun, 2) ->
        fun.(changeset, context)

      other ->
        raise ArgumentError, """
        Invalid entry/exit change specification: #{inspect(other)}

        Expected one of:
        - Module atom: MyApp.Changes.DoSomething
        - {Module, opts}: {MyApp.Changes.DoSomething, opt: value}
        - {Module, :function, [args]}: {MyModule, :my_function, []}
        - Anonymous function with arity 2: fn changeset, context -> changeset end
        """
    end
  end
end
```

### Info Module Extension

```elixir
defmodule AshStateMachine.Info do
  use Spark.InfoGenerator, extension: AshStateMachine, sections: [:state_machine]

  @doc """
  Returns all state definitions with their entry/exit changes.
  """
  def state_machine_states(resource_or_dsl) do
    Spark.Dsl.Extension.get_entities(resource_or_dsl, [:state_machine, :states])
  end

  @doc """
  Returns entry changes for a specific state.
  """
  def state_entry_changes(resource_or_dsl, state_name) do
    case Enum.find(state_machine_states(resource_or_dsl), &(&1.name == state_name)) do
      %{on_entry: changes} -> changes
      nil -> []
    end
  end

  @doc """
  Returns exit changes for a specific state.
  """
  def state_exit_changes(resource_or_dsl, state_name) do
    case Enum.find(state_machine_states(resource_or_dsl), &(&1.name == state_name)) do
      %{on_exit: changes} -> changes
      nil -> []
    end
  end
end
```

## Migration Guide

### Before: Manual Detection

```elixir
defmodule MyApp.Order do
  state_machine do
    transitions do
      transition :start_processing, from: :pending, to: :processing
    end
  end

  changes do
    change fn changeset, _context ->
      old_state = changeset.data.state
      new_state = Ash.Changeset.get_attribute(changeset, :state)

      if old_state != :processing and new_state == :processing do
        changeset
        |> force_change_attribute(:started_at, DateTime.utc_now())
        |> after_action(fn _cs, record ->
          MyApp.Monitor.start(record.id)
          {:ok, record}
        end)
      else
        changeset
      end
    end
  end
end
```

### After: Entry Changes

**Step 1**: Extract logic into change module

```elixir
defmodule MyApp.Changes.OnProcessingStart do
  use Ash.Resource.Change

  def change(changeset, _opts, _context) do
    changeset
    |> Ash.Changeset.force_change_attribute(:started_at, DateTime.utc_now())
    |> Ash.Changeset.after_action(fn _cs, record ->
      MyApp.Monitor.start(record.id)
      {:ok, record}
    end)
  end
end
```

**Step 2**: Use entry change

```elixir
defmodule MyApp.Order do
  state_machine do
    states do
      state :processing do
        on_entry [MyApp.Changes.OnProcessingStart]
      end
    end

    transitions do
      transition :start_processing, from: :pending, to: :processing
    end
  end
end
```

**Step 3**: (Optional) Break into smaller, reusable changes

```elixir
defmodule MyApp.Order do
  state_machine do
    states do
      state :processing do
        on_entry [
          {MyApp.Changes.RecordTimestamp, field: :started_at},
          MyApp.Changes.StartMonitoring
        ]
      end
    end
  end
end
```

## Common Patterns

### Resource Lifecycle Management

```elixir
state :active do
  on_entry [
    MyApp.Changes.AcquireLock,
    {MyApp.Changes.AllocateResources, pool: :default}
  ]

  on_exit [
    MyApp.Changes.ReleaseResources,
    MyApp.Changes.ReleaseLock
  ]
end
```

### Notification Flow

```elixir
state :approved do
  on_entry [
    {MyApp.Changes.SendNotification, template: :approved, to: [:customer, :admin]},
    {MyApp.Changes.LogEvent, event: :approval}
  ]
end

state :rejected do
  on_entry [
    {MyApp.Changes.SendNotification, template: :rejected, to: :customer},
    {MyApp.Changes.LogEvent, event: :rejection}
  ]
end
```

### Timestamp Tracking

```elixir
state :processing do
  on_entry [{MyApp.Changes.RecordTimestamp, field: :processing_started_at}]
  on_exit [{MyApp.Changes.RecordTimestamp, field: :processing_completed_at}]
end

state :shipped do
  on_entry [{MyApp.Changes.RecordTimestamp, field: :shipped_at}]
end
```

### Cleanup and Rollback

```elixir
state :failed do
  on_entry [
    MyApp.Changes.ReleaseAllResources,
    MyApp.Changes.RollbackChanges,
    {MyApp.Changes.SendNotification, template: :failure_alert, to: :admin}
  ]
end
```

### Conditional Execution

```elixir
state :processing do
  on_entry [
    {MyApp.Changes.ConditionalChange,
      if: &(&1.priority == :high),
      change: {MyApp.Changes.AllocateResources, pool: :premium}
    },
    {MyApp.Changes.ConditionalChange,
      if: &(&1.priority == :low),
      change: {MyApp.Changes.AllocateResources, pool: :standard}
    }
  ]
end
```

## Error Handling

### Change Failures

If an entry/exit change returns an error, the entire transition is rolled back:

```elixir
defmodule MyApp.Changes.AllocateResources do
  use Ash.Resource.Change

  def change(changeset, opts, _context) do
    pool = Keyword.fetch!(opts, :pool)

    Ash.Changeset.after_action(changeset, fn _cs, record ->
      case MyApp.ResourcePool.allocate(record.id, pool: pool) do
        {:ok, allocation} ->
          {:ok, %{record | allocation_id: allocation.id}}

        {:error, :pool_exhausted} ->
          # This error will prevent the state transition
          {:error,
            Ash.Error.Invalid.exception(
              field: :state,
              message: "Cannot transition: resource pool #{pool} exhausted"
            )
          }
      end
    end)
  end
end
```

### Graceful Degradation

```elixir
defmodule MyApp.Changes.BestEffortNotification do
  use Ash.Resource.Change

  def change(changeset, opts, _context) do
    Ash.Changeset.after_action(changeset, fn _cs, record ->
      # Don't fail the transition if notification fails
      case MyApp.Notifier.send(record, opts) do
        {:ok, _} ->
          :ok
        {:error, reason} ->
          Logger.warning("Notification failed: #{inspect(reason)}")
          :ok
      end

      {:ok, record}
    end)
  end
end
```

## Best Practices

### 1. Keep Entry/Exit Changes Focused

Each change should do one thing:

✅ **Good:**

```elixir
state :processing do
  on_entry [
    MyApp.Changes.RecordStartTime,
    MyApp.Changes.AllocateResources,
    MyApp.Changes.SendNotification
  ]
end
```

❌ **Bad:**

```elixir
state :processing do
  on_entry [
    MyApp.Changes.DoEverythingOnProcessingStart  # Too much in one change
  ]
end
```

### 2. Make Changes Reusable

Use options to make changes configurable:

✅ **Good:**

```elixir
{MyApp.Changes.RecordTimestamp, field: :started_at}
{MyApp.Changes.RecordTimestamp, field: :completed_at}
```

❌ **Bad:**

```elixir
MyApp.Changes.RecordStartedAt
MyApp.Changes.RecordCompletedAt  # Duplicated code
```

### 3. Order Matters

List changes in the order they should execute:

```elixir
state :processing do
  on_entry [
    MyApp.Changes.ValidatePrerequisites,  # Check first
    MyApp.Changes.AllocateResources,      # Then allocate
    MyApp.Changes.StartProcessing         # Then start
  ]

  on_exit [
    MyApp.Changes.StopProcessing,         # Stop first
    MyApp.Changes.ReleaseResources,       # Then release
    MyApp.Changes.CleanupState            # Then cleanup
  ]
end
```

### 4. Handle Errors Appropriately

Decide whether failures should block transitions:

```elixir
# Critical: block transition if fails
on_entry [MyApp.Changes.AllocateRequiredResources]

# Best-effort: don't block transition
on_entry [MyApp.Changes.OptionalNotification]
```

### 5. Test Entry/Exit Changes Independently

```elixir
# Test the change module
test "RecordTimestamp sets the timestamp" do
  changeset = Ash.Changeset.new(%Order{})
  result = RecordTimestamp.change(changeset, [field: :started_at], %{})
  assert result.attributes[:started_at] != nil
end

# Test the full transition
test "entering processing runs all entry changes" do
  {:ok, order} = Order.start_processing!(pending_order)
  assert order.state == :processing
  assert order.started_at != nil
  assert order.allocation_id != nil
end
```

## Future Enhancements

### With Hierarchical States

When hierarchical states are implemented, entry/exit changes will work with
state hierarchy:

```elixir
state :processing do
  # Runs when entering ANY processing substate
  on_entry [MyApp.Changes.LockOrder]
  on_exit [MyApp.Changes.UnlockOrder]

  state :payment do
    # Additional payment-specific entry/exit
    on_entry [MyApp.Changes.InitializePayment]
    on_exit [MyApp.Changes.CleanupPayment]
  end

  state :fulfillment do
    # Additional fulfillment-specific entry/exit
    on_entry [MyApp.Changes.ReserveInventory]
    on_exit [MyApp.Changes.ReleaseInventory]
  end
end

# Transitioning to "processing.payment" runs:
# 1. processing.on_entry (LockOrder)
# 2. payment.on_entry (InitializePayment)
```

### Async Entry/Exit Changes

Future support for background entry/exit actions:

```elixir
state :processing do
  on_entry [
    {MyApp.Changes.SendNotification, async: true},
    MyApp.Changes.StartProcessing  # This waits for completion
  ]
end
```

## Summary

Entry/exit changes provide:

- ✅ **Guaranteed execution** for state lifecycle hooks
- ✅ **Declarative syntax** that's easy to read and maintain
- ✅ **Reusable change modules** following Ash patterns
- ✅ **Proper execution order** (exit → transition → entry)
- ✅ **Type safety** with module-based changes
- ✅ **Testability** at both unit and integration levels

This feature eliminates the need for manual state-change detection and ensures
lifecycle logic is always executed consistently across all transition paths.
