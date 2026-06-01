---
name: quint-from-code
description: >
  Generate a Quint specification from source code (Rust, Go, TypeScript, etc.) or from an existing
  TLA+ spec. Analyzes code to understand its purpose, abstracts implementation details, writes an
  executable Quint spec following best practices, and proposes invariants and witnesses. The spec
  becomes a persistent grounding artifact used to verify future refactors and features. Use when the
  user wants to model source code in Quint, create a formal specification from implementation, or
  verify concurrent/distributed protocols.
---

# Generate a Grounding Quint Specification from Source Code

Create a Quint specification from source code or an existing TLA+ spec. The spec is not just
output — it is a **persistent grounding artifact**: the source of truth for what the system
*is supposed to do*, used to verify all future changes against.

## Philosophy

**Specs are higher leverage than code.** A misunderstanding in a spec causes hundreds of bad lines.
A misunderstanding in a plan causes thousands. Review happens at the spec level, not just code.

Quint specs answer the SDD question set:

| SDD concern | Quint answer |
|---|---|
| Review burden | Formal + compact — 50–200 lines captures what 1000 lines of prose cannot |
| Control illusions | Formally verified, not advisory — the spec is machine-checked |
| Technical/functional ambiguity | Quint is behavioral: *what* the system does, never *how* |
| Workflow overhead | Start with one module; grow incrementally; skip research for simple changes |
| MDD trap | Spec **verifies** code, it does not generate it — code stays primary |
| RPI / context rot | Research and planning are grounded in the spec and tool runs, not an unbounded chat-to-code jump |
| Markdown-first SDD | English-only specs as the sole contract stay ambiguous; Quint provides an **executable** model and checks |
| Target audience | Engineer who owns the system; human review at spec stage (highest leverage) |

The Quint spec captures **what** the system does, not **how** it does it:

- Focus on state transitions and their observable effects
- Abstract away implementation details (memory management, error handling, serialization)
- Identify the core concurrent/distributed behavior worth verifying
- Keep the model small enough to be tractable for simulation and model checking
- **Build and verify incrementally** — typecheck after every addition; simulate after every action

The key difference from TLA+: Quint specs are **executable from the first line**. Design decisions
are validated immediately, not at the end.

---

## Workflow Overview

```
┌────────────────────────────────────────────────────────────┐
│ Phase 0: Research (compact)                                 │
│   → Catalog relevant files, ops, state                     │
│   → Output: compact research doc (not injected into spec)  │
└────────────────────────────────────────────────────────────┘
                              ↓
┌────────────────────────────────────────────────────────────┐
│ Phase 1: Understand the Code                                │
│   → What problem does it solve?                            │
│   → What are the key operations and their purposes?        │
│   → What state is being managed?                           │
│   → What are the concurrency / failure / time assumptions? │
└────────────────────────────────────────────────────────────┘
                              ↓
┌────────────────────────────────────────────────────────────┐
│ Phase 2: Design the Model                                   │
│   → Separate concerns: state machine / logic / properties  │
│   → Decide variable grouping                               │
│   → Choose types for state and messages                    │
│   → Iterate with user — get explicit approval before next  │
└────────────────────────────────────────────────────────────┘
                              ↓
┌────────────────────────────────────────────────────────────┐
│ Phase 3: Write the Quint Specification                      │
│   → Scaffold types + vars (typecheck after each addition)  │
│   → Write pure function stubs (typecheck)                  │
│   → Fill in pure function logic (simulate/test)            │
│   → Write init + thin actions (simulate/test)              │
│   → Write step                                             │
└────────────────────────────────────────────────────────────┘
                              ↓
┌────────────────────────────────────────────────────────────┐
│ Phase 4: Propose Properties                                 │
│   → Witnesses (one per major action — liveness)            │
│   → Safety invariants                                      │
│   → Simulate with quint run                                │
└────────────────────────────────────────────────────────────┘
                              ↓
┌────────────────────────────────────────────────────────────┐
│ Phase 5: Spec Handoff                                       │
│   → Summarize: what the spec covers and what it does not   │
│   → State: what changes should update the spec first       │
│   → Link: which source files the spec corresponds to       │
└────────────────────────────────────────────────────────────┘
```

---

## Phase 0: Research (Compact)

Before reading code in detail, catalog the codebase to keep the main context window lean
(target: 40–60% utilization during the design phase). Focus on:

> Explore `[path]`. Find and catalog:
> 1. The top-level entry points and their signatures
> 2. The state-carrying data structures (structs, maps, enums)
> 3. The concurrency primitives (mutexes, channels, goroutines, async tasks)
> 4. The message types and their payload shapes
> 5. Any existing tests that reveal expected behavior
>
> Output a compact summary (target: under 400 lines) — file paths, key types, key operations.
> Do not read every file. Prioritize what is most relevant to concurrent/distributed behavior.

If the initial catalog missed something critical, do a targeted follow-up read — do not read the
whole codebase from scratch.

**Skip Phase 0 for simple cases** (single file, clear entry point, no concurrency).

---

## Phase 1: Understand the Code

Using the research output, answer in English:

### Step 1.1: Identify the Problem Domain

1. **What is the overall purpose?** (e.g., "distributed leader election", "token transfer protocol")
2. **What entities exist?** (e.g., nodes, validators, clients, coordinators)
3. **What resources are shared or contested?** (e.g., leader slot, token balances, lock ownership)

### Step 1.2: Catalog Operations and Their Purpose

For each significant operation, document:

| Operation | Purpose | State it reads | State it writes | Concurrency notes |
| --- | --- | --- | --- | --- |
| `functionName` | What it does | Which vars | Which vars | Atomic? Per-node? |

**Focus on:** Public API / entry points, state-modifying operations, message send/receive points, timeout/timer triggers.

**Skip:** Getters with no side effects, logging, metrics, serialization, retry logic (unless retry is what you're verifying).

### Step 1.3: Identify State Variables

| Variable | Type | Purpose | Scope |
| --- | --- | --- | --- |
| `varName` | int / enum / record | What it tracks | Global / per-node |

**Look for:** State machine enums, per-node bookkeeping, shared global state, message buffers.

### Step 1.4: Extract System Model Assumptions

| Concern | Questions to answer |
| --- | --- |
| **Communication** | Reliable or lossy? Ordered or unordered? Broadcast or point-to-point? |
| **Failures** | Crash-stop? Crash-recovery? Byzantine? What fraction `f` of `n`? |
| **Time** | Synchronous? Asynchronous? Partial synchrony? Are timeouts modelled? |
| **Participants** | Fixed membership or dynamic? How many processes? |

---

## Phase 2: Design the Model

### Step 2.1: Separate Concerns

Partition what you found in Phase 1 into three buckets:

- **State machine** — variables, initialization, transitions (`var`, `init`, actions)
- **Functional logic** — pure computations: quorum checks, message filtering, state updates (`pure def`)
- **Properties** — what must always hold, what must be reachable (`val` invariants + witnesses)

Do not mix these layers. Logic in actions, variables in actions, and properties as actions are all
common mistakes that make specs untestable.

### Step 2.2: Decide Variable Grouping

**Group into a record when:**
- They represent one process's local state (e.g. `log`, `votedFor`, `currentTerm` for one Raft node)
- There are N instances — use `NodeId -> LocalState`
- Invariants relate multiple fields of the same entity

**Keep flat when:**
- Variables represent distinct concerns that change independently
- There is one instance (single actor) — grouping adds no clarity

### Step 2.3: Map Source Constructs to Quint

| Source | Quint |
| --- | --- |
| State enum | Sum type `\| State1 \| State2` or `str` constant |
| Struct / record | `type T = { field1: Type1, field2: Type2 }` |
| `Vec<T>` / array | `List[T]` |
| `HashSet<T>` | `Set[T]` |
| `HashMap<K, V>` | `K -> V` (map type) |
| Thread / process | Element of `NODES` set; `NodeId -> LocalState` |
| Atomic CAS | Guarded action with `require` (atomicity is implicit) |
| Message queue | `Set[Message]` (message soup — no ordering unless ordering is what you're verifying) |

### Step 2.4: Propose the Type Sketch and Get Approval

Write only the types and `var` declarations. No functions, no actions yet.

```quint
module Raft {
  type Entry    = { term: int, value: str }
  type NodeState = { log: List[Entry], votedFor: int, currentTerm: int }
  type Message  =
    | { tag: "VoteRequest",  term: int, candidateId: int }
    | { tag: "VoteResponse", term: int, voterId: int, granted: bool }

  pure val N: int = 3
  const NODES: Set[int] = 1.to(N)

  var nodes:    int -> NodeState
  var messages: Set[Message]
}
```

Run `quint typecheck` and fix all reported errors before continuing. Then **stop and present this to the user**. Do not proceed without explicit approval. This is the highest-leverage human review point.

---

## Phase 3: Write the Quint Specification

### Step 3.1: Write Pure Function Stubs

For each operation, write a `pure def` stub with correct signature and placeholder body.

```quint
pure def isQuorum(voters: Set[int]): bool =
  false  // TODO

pure def handleVoteRequest(
  state: NodeState,
  req: { term: int, candidateId: int }
): { granted: bool, newState: NodeState } =
  { granted: false, newState: state }  // TODO
```

Run `quint typecheck` and fix all reported type errors before continuing. All type errors at this stage are cheap to fix.

### Step 3.2: Fill in Pure Function Logic

Fill in one pure function at a time. After each, exercise it with `quint test` / `quint run`
or the REPL when interactive evaluation helps. If the output surprises you, the function has a bug.
Fix it before moving to the next.

### Step 3.3: Write Init and Actions

Write `init`, `unchanged_all`, and thin action wrappers. Actions call pure functions — no logic in
actions.

```quint
action init: bool = all {
  nodes' = NODES.mapBy(_ => { log: List(), votedFor: 0, currentTerm: 0 }),
  messages' = Set(),
}

action unchanged_all: bool = all {
  nodes' = nodes,
  messages' = messages,
}

action requestVote(candidateId: int): bool = {
  val s   = nodes.get(candidateId)
  val req = { tag: "VoteRequest", term: s.currentTerm + 1, candidateId: candidateId }
  all {
    nodes'    = nodes.put(candidateId, { ...s, currentTerm: s.currentTerm + 1 }),
    messages' = messages.union(Set(req)),
  }
}
```

Run `quint typecheck` and fix any errors, then validate behavior with `quint run` / `quint test`.

### Step 3.4: Write Step

```quint
action step: bool = {
  nondet node = NODES.oneOf()
  any {
    requestVote(node),
    // other actions...
  }
}
```

---

## Phase 4: Propose Properties

### Step 4.1: Witnesses First (Liveness)

One witness per major action. Written as `not(target_state)` — violation means the target was
reached (good). Satisfied witness means the action is dead — fix it before adding invariants.

```quint
// VIOLATED = ✅  vote request is reachable
// SATISFIED = ❌ spec is over-constrained — fix the action
val canRequestVoteSuccessfully: bool =
  not(messages.exists(m => m.tag == "VoteRequest"))
```

### Step 4.2: Safety Invariants

```quint
// At most one leader per term
val atMostOneLeader: bool =
  NODES.forall(n1 => NODES.forall(n2 =>
    (n1 != n2 and isLeader(n1) and isLeader(n2)) implies
    nodes.get(n1).currentTerm != nodes.get(n2).currentTerm
  ))
```

### Step 4.3: Simulate

- Check witnesses with ``quint run`` (expect witness reachability/violation semantics).
- Check safety invariants with ``quint run`` or ``quint verify`` (expect no violation).

---

## Phase 5: Spec Handoff

After the spec is verified, produce a short handoff note (embedded as comments or a separate doc):

### What this spec covers
- Which modules / protocols are modelled
- What system model assumptions are encoded (`assume` axioms, constants)
- What properties are verified

### What this spec does NOT cover
- Implementation details omitted intentionally
- Edge cases excluded from the model (and why)
- Future properties to add

### Source file correspondence
List which source files each Quint module corresponds to. When those files change, update the spec
first and re-verify before touching the code.

```
quint-specs/Raft.qnt       ↔   src/consensus/raft.rs, src/consensus/log.rs
quint-specs/Membership.qnt ↔   src/cluster/membership.go
```

### When to update the spec
- Before refactoring behavior (update spec → verify → then change code)
- Before adding a feature that changes state or invariants
- After finding a bug that reveals a gap in the properties

**Never modify the spec to match broken code. The spec is the ground truth.**
If the spec is wrong, stop and discuss with the user — that is the highest-leverage review point.

To implement changes against this spec, use the `quint-execute-spec` skill.

---

## Output Format

### 1. English Summary

```
## System Analysis

### Purpose
[One paragraph describing what the system does]

### Key Operations
- `operation1`: [purpose and state effect]

### State Variables
- `var1`: [what it tracks, global or per-node]

### System Model
- Communication: [reliable/lossy, ordered/unordered]
- Failures: [crash-stop/Byzantine, fraction f of n]
- Time: [sync/async, timeouts modelled?]
```

### 2. Quint Specification

Complete, typechecking Quint module. Write all specs under `quint-specs/`. Do not create `.qnt`
files outside `quint-specs/`.

### 3. Properties Summary

```
## Proposed Properties

### Witnesses (expect VIOLATED)
1. canOperationXSuccessfully — operation X is reachable

### Safety Invariants (expect no violation)
1. InvariantName — what it ensures

### Recommended Simulation
``quint run`` for witness reachability and quick invariant checks.
``quint verify`` for bounded exhaustive checks when needed.
```

### 4. Spec Handoff

Covers / does not cover / source file correspondence / when to update.

---

## Common Pitfalls

| Pitfall | Solution |
| --- | --- |
| Logic in actions | Move all computation to `pure def`; actions only call and update |
| Empty map access | Pre-populate every map with `mapBy` in `init` |
| `.with()` for record update | Use `{ ...record, field: newValue }` |
| `Map[K,V]` type syntax | Use `K -> V` |
| `pure def f() =` (empty parens) | Use `pure def f =` for parameterless defs |
| Nested pattern match | Match one level at a time |
| Modelling all N threads at once | Add one actor, verify, then generalise to N |
| Spec too detailed | If it doesn't affect an invariant you care about, it doesn't belong |
