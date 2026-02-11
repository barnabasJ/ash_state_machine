# Parallel States Research Summary (2025-12-15)

## Overview

Found comprehensive state machine research completed on **2025-12-06** covering
70 years of state machine theory and practice. The research was stored in LogSeq
at `projects/ash_state_machine/research/2025-12-state-machine-research` with 6
specialized sub-pages.

---

## 1. State Machine Theory Research (Mealy, Moore, Harel)

### Historical Evolution

#### 1955: Mealy Machines (George H. Mealy)

- **Paper**: "A Method for Synthesizing Sequential Circuits" (Bell System
  Technical Journal)
- **Key Feature**: Output depends on **current state AND input**
- **Impact**: Foundation for state-dependent systems

#### 1956: Moore Machines (Edward F. Moore)

- **Paper**: "Gedanken-experiments on Sequential Machines" (Automata Studies)
- **Key Feature**: Output depends **only on current state**
- **Impact**: Simpler model, widely used in digital circuits

#### 1987: Harel Statecharts (David Harel)

- **Revolutionary Paper**: "Statecharts: A Visual Formalism for Complex Systems"
  (Science of Computer Programming, 1987)
- **URL**: http://www.wisdom.weizmann.ac.il/~harel/papers/Statecharts.pdf
- **Key Innovation**: Solved the state explosion problem with "triple
  exponential reduction" in complexity

**New Features Introduced by Harel:**

- **Hierarchy**: Nested states (parent-child relationships)
- **Concurrency**: Parallel regions (orthogonal states)
- **History**: Deep/shallow history states
- **Broadcast**: Inter-level communication

**Impact**: Transformed state machines from academic curiosity to practical
engineering tool

### The State Explosion Problem

**Without Hierarchy** - Order processing example:

- payment_validating
- payment_processing
- payment_completed
- payment_failed
- fulfillment_picking
- fulfillment_packing
- fulfillment_shipping
- cancelled
- **Result**: 10+ flat states, redundant transition logic

**With Hierarchy** (Harel's Solution):

```
processing
  ├─ payment
  │  ├─ validating
  │  ├─ processing
  │  └─ completed
  └─ fulfillment
     ├─ picking
     ├─ packing
     └─ shipping
```

- **Result**: 4 top-level states + substates, shared transitions from parent
  levels
- **Complexity Reduction**: "Triple exponential" - instead of 2^n states, you
  get log(n) hierarchical levels

---

## 2. W3C SCXML and UML 2.5 Specification Notes

### W3C SCXML (State Chart XML)

- **URL**: https://www.w3.org/TR/scxml/
- **Version**: 1.0 (2015)
- **Status**: W3C Recommendation
- **Description**: Standard for executable state machines

**Features:**

- Hierarchical states
- Parallel states
- History states
- Datamodel integration
- Event processing

### UML 2.5 State Machine Specification

- **URL**: https://www.omg.org/spec/UML/2.5/
- **Organization**: Object Management Group (OMG)
- **Description**: Standard notation for state machines in UML
- **Based On**: Harel statecharts

**Extensions:**

- Protocol state machines
- Behavioral state machines
- Composite states
- Submachine states

### Industry Consensus: Standard Features

Modern state machine libraries converge on these features:

1. **Hierarchical States (Compound States)**

   - Parent-child state relationships
   - Shared transitions at parent level
   - Entry/exit actions inherited by children

2. **Parallel States (Orthogonal Regions)**

   - Multiple independent state machines
   - Coordination through combined state queries
   - Prevents combinatorial state explosion

3. **History States**

   - Shallow History: Remember direct child state
   - Deep History: Remember entire substate hierarchy
   - Use case: Pause/resume workflows

4. **Entry/Exit Actions**

   - Entry: Guaranteed execution when entering state
   - Exit: Guaranteed cleanup when leaving state
   - Benefit: DRY principle - define once per state

5. **Guard Conditions**

   - Boolean predicates that must be true for transition
   - Runtime conditional logic
   - Enable/disable transitions dynamically

6. **Internal Transitions**
   - Handle events without exiting/re-entering state
   - Don't trigger entry/exit actions
   - Optimization for self-transitions

---

## 3. XState and Library Comparison Notes

### XState (JavaScript/TypeScript)

- **URL**: https://xstate.js.org
- **Repository**: https://github.com/statelyai/xstate
- **Maintainer**: Stately.ai

**Features:**

- Full statechart implementation
- Visual editor (Stately.ai)
- Actor model integration
- TypeScript support
- Large ecosystem

**Lessons Learned:**

- Declarative DSL crucial for usability
- Visualization tools improve understanding
- Entry/exit actions heavily used
- Guard conditions essential

### gen_statem (Erlang/OTP)

- **URL**: https://www.erlang.org/doc/man/gen_statem.html
- **Language**: Erlang
- **Status**: Battle-tested in production

**Features:**

- Process-based state machines
- Callback-based API
- Timeout handling
- Supervision tree integration

**Lessons Learned:**

- State machines work well in BEAM
- Process-based vs data-based trade-offs
- Timeout handling important for reactive systems

### Spring State Machine (Java)

- **URL**: https://spring.io/projects/spring-statemachine
- **Language**: Java

**Features:**

- Enterprise-grade features
- Guard and action support
- Deferred events
- Spring ecosystem integration

**Lessons Learned:**

- Guard conditions are table stakes
- Entry/exit actions reduce boilerplate
- Good error messages critical

### Quantum Programming (C/C++)

- **URL**: https://www.state-machine.com
- **Use Case**: Embedded systems

**Features:**

- Hierarchical state machines
- Active objects
- Real-time constraints

**Lessons Learned:**

- Hierarchical states essential for embedded
- Performance matters in constrained environments

### Elixir Ecosystem Analysis

**Existing Libraries:**

1. **ecto_state_machine**

   - Repository: https://github.com/asiniy/ecto_state_machine
   - Status: Maintained
   - Features: Simple FSM for Ecto, no advanced features

2. **gen_state_machine**

   - Repository: https://github.com/ericentin/gen_state_machine
   - Status: Maintained
   - Features: GenServer-based, not database-backed

3. **machinery**
   - Repository: https://github.com/joaomdmoura/machinery
   - Status: Unmaintained
   - Features: Basic callbacks, limited adoption

**The Gap:** No Elixir library provides:

- ✗ Hierarchical states with database backing
- ✗ Declarative entry/exit actions
- ✗ History state support
- ✗ Full statechart features

Most libraries offer:

- ✓ Basic finite state machines
- ✓ Simple transitions
- ✓ Callback hooks

---

## 4. Implementation Roadmap Findings

### The Opportunity for ash_state_machine

**Current Strengths:**

- ✓ Clean DSL integration via Spark
- ✓ Ash framework integration (policies, validations, changesets)
- ✓ Database-backed (persistent state)
- ✓ Compile-time validation
- ✓ Production-ready
- ✓ Well-tested

**Unique Positioning:** ash_state_machine can become:

- The **premier database-backed statechart library** in Elixir
- The **only** Elixir library with full Harel statechart features
- The **best** integration of state machines with modern Elixir frameworks

**Competitive Advantages:**

- **Ash Ecosystem**: Leverage policies, validations, aggregates, relationships
- **Database-Backed**: Persistent state, queryable, transactional
- **Type Safety**: Compile-time validation via transformers
- **Declarative**: Clean DSL, not callback spaghetti

### 4-Phase Implementation Plan (15-21 weeks total)

#### Phase 1: Foundation (2-3 weeks)

**Goal**: Add declarative entry/exit actions and improve documentation

**Tasks:**

- Extend DSL to support state definitions with `on_entry` and `on_exit` actions
- Implement transformer to convert entry/exit actions to Ash changes
- Add guard conditions to transitions with `guards` option
- Document hierarchical state patterns using string notation
- Document parallel state patterns using separate resources
- Add comprehensive examples to documentation

**Deliverables:**

- Entry/exit actions working in DSL
- Guard conditions functional
- Pattern documentation complete
- Migration guide for users

**Impact**: High - addresses most common use cases

#### Phase 2: Hierarchical States (4-6 weeks)

**Goal**: Native support for hierarchical states

**Tasks:**

- Extend DSL with nested `states` section for defining hierarchy
- Support state path notation (dot-separated strings like
  `"processing.payment.validating"`)
- Enhance wildcard matching for parent-level transitions (`"processing.*"`)
- Add helper functions: `in_state?/2`, `current_parent_state/1`, `state_path/1`
- Update transformers to validate hierarchical state paths
- Add comprehensive tests for hierarchical transitions
- Create migration guide for existing users
- Update documentation with hierarchy best practices

**Deliverables:**

- Hierarchical state DSL working
- Wildcard matching for parent states
- Helper functions for hierarchy navigation
- Comprehensive test coverage
- User migration guide

**Impact**: Very High - enables complex workflow modeling with exponential
complexity reduction

#### Phase 3: History & Advanced Features (3-4 weeks)

**Goal**: Built-in history state support and internal transitions

**Tasks:**

- Add `enable_history` configuration option to DSL
- Implement automatic history tracking in transformers
- Add special `:history` transition target
- Support both shallow and deep history modes
- Add internal transitions (don't exit/re-enter state)
- Enhance visualization (mermaid diagrams with hierarchy)
- Document history patterns and use cases

**Deliverables:**

- History state support functional
- Internal transitions working
- Enhanced visualizations
- Pattern documentation

**Impact**: Medium - valuable for specific use cases (navigation, pause/resume)

#### Phase 4: Parallel States (6-8 weeks)

**Goal**: Multiple state machines per resource

**Tasks:**

- Extend DSL to support multiple `state_machine` blocks per resource
- Each block specifies its own `state_attribute`
- Update transformers to handle multiple state machines
- Add coordination helpers for checking combined state
- Update Info module for querying specific state machines
- Comprehensive testing for parallel state interactions
- Documentation for parallel state patterns
- Performance testing with multiple machines

**Deliverables:**

- Multiple state machines per resource
- Coordination helpers
- Pattern documentation
- Performance benchmarks

**Impact**: Medium - useful for specific scenarios, can be worked around with
multiple resources

### Recommended Sequence

1. Phase 1 (Foundation) - **Must do first**
2. Phase 2 (Hierarchical) - **High priority**
3. Phase 3 (History) - **Medium priority**
4. Phase 4 (Parallel) - **Future consideration**

### Milestone Goals

- **3 months**: Phases 1-2 complete (entry/exit + hierarchy)
- **5 months**: Phase 3 complete (history states)
- **Future**: Phase 4 based on community demand

### Success Metrics

- **Adoption**: Increased usage in Ash ecosystem projects
- **Complexity Reduction**: Fewer states needed for complex workflows
- **Code Quality**: Less duplicated transition logic
- **Developer Experience**: Faster implementation of state-based features
- **Community**: Contributions and extensions from users

---

## Research Validation

**70 years of research** confirms:

- Hierarchical states are essential for complex systems
- Entry/exit actions reduce code duplication significantly
- Guard conditions are "table stakes" for production use
- Parallel states prevent combinatorial explosion

**Industry adoption** proves:

- XState, SCXML, UML 2.5 all standardized on these features
- Spring State Machine, gen_statem implement them
- Quantum Programming (embedded systems) relies on them

**Mathematical proof** (Harel 1987):

- Hierarchical decomposition provides exponential complexity reduction
- Formal semantics enable verification and testing

---

## Source Documents

All research stored in LogSeq at:

- Main: `projects/ash_state_machine/research/2025-12-state-machine-research`
- Key Findings: `projects/ash_state_machine/research/key-findings`
- References: `projects/ash_state_machine/research/references`
- Implementation Roadmap:
  `projects/ash_state_machine/research/implementation-roadmap`
- Technical Insights: `projects/ash_state_machine/research/technical-insights`
- Code Examples: `projects/ash_state_machine/research/code-examples`

Original markdown:
`/home/joba/sandbox/ash_state_machine/docs/research/STATE_MACHINE_RESEARCH_SYNTHESIS.md`
(1,411 lines)

---

## Conclusion

The research demonstrates that ash_state_machine has a significant opportunity
to become the premier database-backed statechart library in Elixir by
implementing industry-standard features (hierarchical states, entry/exit
actions, history states) that are currently missing from the Elixir ecosystem.
The phased implementation plan provides a clear roadmap with realistic timelines
and measurable success criteria.
