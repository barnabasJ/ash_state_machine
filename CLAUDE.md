# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

## Project Overview

AshStateMachine is an Elixir library that provides state machine functionality
for Ash resources. It's built using the Spark DSL framework and integrates with
the Ash framework for data modeling and APIs.

## Common Development Commands

### Testing

- `mix test` - Run all tests
- `mix test --only some_tag` - Run tests with specific tags
- `mix test test/specific_test.exs` - Run a specific test file

### Code Quality

- `mix credo --strict` - Run strict code analysis (configured in aliases)
- `mix sobelow --skip` - Run security analysis (configured in aliases)
- `mix dialyzer` - Run type checking
- `mix format` - Format code
- `mix ex_check` - Run all quality checks

### Documentation

- `mix docs` - Generate documentation (includes spark cheat sheets)
- `mix spark.cheat_sheets` - Generate DSL cheat sheets
- `mix spark.formatter` - Format Spark DSL code

## Architecture

### Core Components

1. **Main DSL Module** (`lib/ash_state_machine.ex`)

   - Defines the `state_machine` DSL section with transitions
   - Provides the `transition_state/2` function for state transitions
   - Includes helper functions like `possible_next_states/1` and
     `possible_next_states/2`

2. **Transformers** (`lib/transformers/`)

   - `SetDefaultInitialState` - Sets default initial state
   - `FillInTransitionDefaults` - Fills in default transition values
   - `AddState` - Adds state attribute to resources
   - `EnsureStateSelected` - Ensures state is properly selected
   - `AddParallelRegionRelationships` - Adds has_one relationships for parallel
     regions

3. **Verifiers** (`lib/verifiers/`)

   - `VerifyTransitionActions` - Validates transition actions exist
   - `VerifyDefaultInitialState` - Validates default initial state
   - `VerifyParallelRegions` - Validates parallel region configuration

4. **Built-in Changes** (`lib/builtin_changes/`)

   - `NextState` - Change for transitioning to next state
   - `TransitionState` - Change for explicit state transitions
   - `ActivateParallelRegions` - Creates region resources when parent activates
   - `CheckParallelCompletion` - Checks if parent should transition after region
     completes

5. **Parallel Coordinator** (`lib/parallel_coordinator.ex`)

   - Coordinates completion of parallel regions
   - Supports completion strategies: `:require_all`, `:allow_partial`,
     `{:require_n, count}`

6. **Checks** (`lib/checks/`)
   - `ValidNextState` - Validates if a state transition is allowed

### Key Concepts

- **State Attribute**: The attribute that stores the current state (default:
  `:state`)
- **Transitions**: Define allowed state changes with `from`, `to`, and `action`
  specifications
- **Wildcards**: Use `:*` to represent "any state" or "any action"
- **Initial States**: States that can be set during resource creation
- **Extra States**: States that can be referenced by wildcard transitions
- **Parallel Regions**: Multiple state machines that run concurrently within a
  parent

### Parallel Regions

Parallel regions allow multiple state machines to run concurrently within a
parent state machine. Each region is a separate Ash resource.

**DSL Configuration:**

```elixir
state_machine do
  initial_states [:pending]
  default_initial_state :pending

  transitions do
    transition :start_processing, from: :pending, to: :processing
    transition :complete, from: :processing, to: :completed
  end

  parallel_regions do
    region :payment, PaymentMachine
    region :inventory, InventoryMachine
    activate_on :processing
    completion_strategy :require_all
  end
end
```

**Activating Regions:**

```elixir
update :start_processing do
  change transition_state(:processing)
  change activate_parallel_regions()
end
```

**Checking Completion:**

```elixir
# Check if all regions meet completion criteria
case AshStateMachine.check_parallel_completion(order, Domain) do
  {:ok, :complete} -> # Ready to transition parent
  {:ok, :pending} -> # Still waiting
  {:error, :partial_failure} -> # Failed with :require_all
end

# Helper functions
AshStateMachine.all_regions_terminal?(order, Domain)
AshStateMachine.all_regions_succeeded?(order, Domain)
AshStateMachine.get_region_states(order, Domain)
```

**Completion Strategies:**

- `:require_all` - All regions must succeed (default)
- `:allow_partial` - Proceed when all reach any terminal state
- `{:require_n, count}` - Proceed when N regions succeed

**Terminal State Detection:** Terminal failure states are identified by naming
convention: `:failed`, `:error`, `:cancelled`, `:unavailable`, `:rejected`,
`:aborted`, `:timeout`

### Test Structure

- Test files are in `test/` directory
- Support files for testing are in `test/support/`
- Test helper is minimal - just starts ExUnit
- Tests use ExUnit framework

### Environment Configuration

- Mix environment controls compilation paths
- Test environment includes `test/support` in compilation paths
- Development dependencies include testing and quality tools

## Development Notes

- This is a library package, not an application
- Uses Spark DSL framework for extensibility
- Integrates with Ash framework's changeset system
- Supports both create and update operations with state transitions
- Includes comprehensive error handling for invalid transitions
