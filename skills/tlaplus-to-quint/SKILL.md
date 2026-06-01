---
name: tlaplus-to-quint
description: >
  Generate a Quint specification from an existing TLA+ spec. Analyzes spec to understand its purpose, maintains characteristics of TLA+ spec, writes an
  executable Quint spec following best practices, and proposes invariants and witnesses. Use when
  the user wants to translate TLA+ into Quint.
---

# Generate a Quint Specification from TLA+ spec

Create a Quint specification from an existing TLA+ spec  by maintaining its names, structure, etc.
Use the quint-lang skill for writing and interacting.

## Philosophy

TLA+ spec have a precise semantics that should be maintained. Most of the time, TLA+ specs can be translated one-to-one.
However, Quint offers modern syntax that is easier to read. So we want a readable spec where the mapping between TLA+ and Quint is obvious.

### Maintain
- names (of variables, functions, operators)
- infer types of TLA+. If in doubt ask the user for guidance
- invariants. Translate every TLA+ invariant operator (`Inv`, `TypeOK`, `VotesSafe`, etc.) as a `val` in Quint, preserving its name, conjunct order, and inline comments that cite the TLA+ formula. Do not add invariants that have no counterpart in the TLA+ spec.
- modularity. If a TLA+ spec uses CONSTANT, separate TLA+ files that instantiate those do the same in Quint. If TLA+ uses ASSUME to constrain constants, translate it as a `run` test in the **same (parametric) module as the `const`** — not in the instantiation module.
  ```quint
  run quorumAssumptionTest = {
    all {
      Quorum.forall(Q => Q.subseteq(Acceptor)),
      Quorum.forall(Q1 => Quorum.forall(Q2 => Q1.intersect(Q2) != Set())),
    }
  }
  ```
  Run it via ``quint test`` with `main_module=<InstanceModule>`. The test passes when all conditions hold; it fails (and reports which step failed) otherwise.
- **Abstract TLA+ sets** (`CONSTANT Value, Acceptor`) become `const` with a **descriptive lowercase type variable** (e.g. `acceptorType`, `valueType`). Use distinct variables when the sets have independent element types. Any type that mentions them must be made **parametric**: `type Vote[v] = { bal: int, value: v }`. The `var` and function signatures use the module-level type variables directly. The instantiation module infers concrete types from the const values — no explicit type arguments needed:
  ```quint
  const Acceptor : Set[acceptorType]
  const Value    : Set[valueType]
  const Quorum   : Set[Set[acceptorType]]
  type Vote[v]          = { bal : int, value : v }
  type AcceptorState[v] = { votes : Set[Vote[v]], maxBal : int }
  var acceptors : acceptorType -> AcceptorState[valueType]
  // function sigs can omit the type param when Quint can infer it:
  // (state : AcceptorState, acc : acceptorType, v : valueType, ...)

  // Instance: types inferred as acceptorType=int, valueType=int
  import Voting(Acceptor = Set(1,2,3), Value = Set(0,1), Quorum = ...).*
  ```

- **TLA+ sentinel constants** (`CONSTANT any, none` with `any \notin Values \union {none}`) should be translated as explicit variants of a **shared sum type** defined in a separate module — not as an abstract `const`. Define the type in its own file (e.g. `PaxosValues.qnt`) imported by all modules that need it:
  ```quint
  // PaxosValues.qnt
  module PaxosValues {
    type AllValues[v] = Any | NoVal | Val(v)
    //   Val(v) — a real protocol value
    //   Any    — TLA+ `any` sentinel
    //   NoVal  — TLA+ `none` sentinel
  }
  ```
  The `paxosAssumeTest` can then faithfully check both exclusions:
  ```quint
  not(Values.contains(Any)),   // any \notin Values \union {none}
  not(Values.contains(NoVal)), // none \notin Values \union {any}
  ```
  The type **must** live in a separate module (see cycle trap in pitfalls table).

### Change
- For distributed and concurrent systems introduce local states. In TLA+ local variables are often multiple maps from processIDs to values of the variables, while in Quint we prefer to encode a type LocalState that captures local variables, and store the system state as a map from processIDs to LocalState
- Use the functional layer, and a **truly thin action layer**: all guards and state computation belong in `pure def`s; actions are single assignments that call the pure def and set the next state. When a TLA+ guard that would *disable* an action is instead absorbed into a pure def's `if-else` (returning the old state on failure), this introduces stuttering — document it on the action with a note and a hint for how to remove it:
  ```quint
  // Note: applyFoo returns st unchanged when <guard> fails — stuttering vs TLA+.
  // To remove stuttering add: <guard>,
  action foo(acc : acceptorID, bal : int) : bool = all {
    acceptors' = acceptors.set(acc, applyFoo(acceptors, acc, bal)),
  }
  ```

- **If the TLA+ spec uses a message soup (`msgs` variable, `Send(m)` helper, or any `\cup {m}` pattern on a message set), use Choreo** (`../quint-lang/guidelines/choreo`). Raise this in Phase 2 design before writing any code, and ask the user to confirm the node/role decomposition (e.g. which processes send/receive which message types, whether to introduce an explicit leader). The TLA+ soup is monotone (messages never deleted) — decide whether Choreo inboxes should consume messages or leave them in place.
- **Choreo `listen_*` / `send_*` naming**: `listen_X` is named after what it watches for (the triggering condition or incoming message type); `send_X` is named after the message type it produces (= the TLA+ operator name). E.g., TLA+ `Phase2b(a,b,v)` is triggered by a Phase2a message → `listen_phase2a` / `send_phase2b`. For the proposer's initial step where there is no incoming message, use a descriptive name like `listen_start` or `listen_phase1b_quorum`. The `main_listener` then reads as a direct transliteration of the TLA+ `Next` definition.
- **Build and verify incrementally** — the REPL runs after every addition, never after everything

- **TLA+ `EXTENDS` → `import M(...) as m` + `export m`**: Quint has no `EXTENDS` keyword. The closest equivalent is a namespaced import where the extending module re-declares the shared `const`s, passes them through, and re-exports the namespace:
  ```quint
  // FastPaxos.qnt — mirrors TLA+ EXTENDS Paxos
  const Replicas   : Set[acceptorType]   // re-declare shared consts
  const Ballots    : Set[int]
  // ...

  import Paxos(
    Replicas    = Replicas,              // pass through to base module
    Ballots     = Ballots,
    // ...
  ) as paxos from "Paxos"
  export paxos                           // re-export so analysis modules can call paxos::f
  ```
  The analysis module then calls `paxos::listen_p2a_value`, `paxos::upon_classic_decide`, etc. without duplication.

  **Constraint — higher-order const bindings**: a `paxos::f` function can be passed to `choreo::cue` ONLY if its body does **not** reference module-level `const`s. If it does, the Quint runtime loses the const binding when `f` is used as a higher-order argument. Fix: rewrite the body to use only the type structure instead. Example: `Values.contains(r.value)` → `r.value != Any and r.value != NoVal` (equivalent when `Values` only contains `Val(v)` elements, which `paxosAssumeTest` guarantees).

  **Constraint — cross-module `val` invariants**: referencing `paxos::TypeOKInvariant` (a `val`) from the extending module also fails at runtime with "Uninitialized const", even without higher-order calls. The fix is different from the higher-order case: extract the invariant body into a `pure def` that takes the consts as explicit parameters, then call it from both the base `val` and the extending module's invariant.

  ```quint
  // Paxos.qnt — base module
  pure def checkPaxosTypeOK(
    values:        Set[AllValues],
    ballots:       Set[int],
    decision:      AllValues,
    replicaStates: Set[StateFields]   // pass s.system.get(a).state for each replica
  ): bool =
    (values.contains(decision) or decision == NoVal)
    and replicaStates.forall(sf =>
      match sf {
        | AcceptorState(acc) =>
            ballots.contains(acc.maxBallot)
            and ballots.contains(acc.maxVBallot)
            and (values.contains(acc.maxValue) or acc.maxValue == NoVal)
        | CoordState(_) => false
      }
    )

  val PaxosTypeOK: bool =
    checkPaxosTypeOK(Values, Ballots, coordState.decision,
                     Replicas.map(a => s.system.get(a).state))

  // FastPaxos.qnt — extending module
  // paxos::checkPaxosTypeOK works because it takes consts as explicit parameters.
  // paxos::PaxosTypeOK would fail — val references do not propagate const bindings.
  val FastTypeOK: bool =
    paxos::checkPaxosTypeOK(Values, Ballots, coordState.decision,
                            Replicas.map(a => s.system.get(a).state))
    and (Values.contains(coordState.cValue) or coordState.cValue == NoVal)
  ```

  The key insight: `pure def` arguments are evaluated at the call site, so `Values` and `Ballots` refer to the caller's (FastPaxos's) consts, which are properly bound. A `val` is evaluated in its defining module's const environment, which is not propagated across the import boundary.

  **When the operator genuinely differs** between base and extending module (e.g. `ClassicDecide` iterates `ClassicBallots` in FastPaxos but `Ballots` in Paxos), define the function locally in the extending module. This is semantically correct, not a workaround.

- **File length check — ask before combining `EXTENDS` modules**: When the TLA+ source uses `EXTENDS AnotherFile`, check the total line count of both files. If keeping them combined would make the Quint file noticeably longer than its TLA+ counterpart, present the user with a choice:
  - **One file**: simpler imports for the analysis module, but potentially long.
  - **Two files mirroring TLA+**: each Quint file stays close in length to its TLA+ source; base module content is duplicated (~15–20 lines) since Quint parametric modules cannot be cross-imported cleanly.
  Ask the user which they prefer before writing any code. A Quint file should not be substantially longer than the TLA+ spec it translates.

The key difference from TLA+: Quint specs are **executable from the first line**. You don't write the whole spec and then check it. You add a type, typecheck. Add a pure function, test it in the REPL. Add an action, fire it. Design decisions are validated immediately.

## Workflow Overview

```
┌─────────────────────────────────────────────────────────────────┐
│ Phase 1: Understand the TLA+ Code                               │
│   → What problem does it solve?                                 │
│   → What are the key operations and their purposes?             │
│   → What state is being managed? (what is local/global)         │
│   → What are the concurrency / failure / time assumptions?      │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ Phase 2: Design the Model                                       │
│   → Separate concerns: state machine / logic / properties       │
│   → Decide variable grouping                                    │
│   → Choose types for state and messages                         │
│   → Iterate with user — get explicit approval before proceeding │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ Phase 3: Write the Quint Specification                          │
│   → Scaffold types + vars (typecheck after each addition)       │
│   → Write pure function stubs (typecheck)                       │
│   → Fill in pure function logic (REPL-test each one)            │
│   → Write init + thin actions (REPL: fire each action)          │
│   → Write step                                                  │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ Phase 4: Properties and README                                  │
│   → Translate TLA+ invariants faithfully                        │
│   → Infer witnesses (ask user), simulate with quint run         │
│   → Write example runs / happy path(ask user),                  │
│   → put runs and witnesses in analysis quint file               │
│   → perform tests, simulate with quint run                      │
│   → Write README.md next to the .qnt files                      │
└─────────────────────────────────────────────────────────────────┘
```

---

## Phase 1: Understand the Code

### Step 1.1: Identify the Problem Domain

Read the code and answer in English:

1. **What is the overall purpose?** (e.g., "distributed leader election", "token transfer protocol", "two-phase commit")
2. **What entities exist?** (e.g., nodes, validators, clients, coordinators)
3. **What resources are shared or contested?** (e.g., leader slot, token balances, lock ownership)

### Step 1.1b: Analyze TLA+ `EXTENDS` imports

Before translating any spec that uses `EXTENDS AnotherFile`, read `AnotherFile` and list
**precisely** which operators/definitions the extending spec actually uses. This determines
the Quint module structure. Example:

| Used from Paxos | How used in FastPaxos |
|---|---|
| `PaxosAccepted` | `ClassicAccepted == UNCHANGED<<cValue>> /\ PaxosAccepted` |
| `PaxosInit` | `FastInit == PaxosInit /\ cValue = none` |
| `PaxosTypeOK` | `FastTypeOK == PaxosTypeOK /\ cValue \in Values \union {none}` |
| `Ballots`, `Quorums`, `Replicas`, `Values` | shared constants, inherited |

Operators **not** used (e.g. Phase1a/1b, Phase2a, PaxosNext) can be dropped from scope.
This analysis drives the module structure decision before any code is written.

### Step 1.1c: Flag TLA+ `CHOOSE` operators

Before proceeding, scan the TLA+ spec for any use of the `CHOOSE` operator (e.g. `CHOOSE x \in S : P(x)`). Quint has no direct `CHOOSE` equivalent. For **each** occurrence:

1. Quote the TLA+ expression to the user.
2. Explain what it does in context (e.g. picks an arbitrary element satisfying a predicate, defines a canonical representative, etc.).
3. Ask the user how to handle it. Common options:
   - **Nondeterministic choice** — replace with `nondet x = S.filter(e => P(e)).oneOf()` in an action (only valid if inside an action context).
   - **Deterministic selection** — replace with a deterministic helper (e.g. `S.filter(P).fold(...)`) if the choice is semantically irrelevant.
   - **Constant / abstract value** — introduce a `const` or `pure val` if the chosen value is fixed for a run.
4. **Do not translate any `CHOOSE` occurrence until the user has approved an approach for it.**

### Step 1.2: Analyze the variables in the state machine

1. **What is local state?** read and written only by one entity (e.g., round number, decision value). Often encoded as map from entity to variable
2. **What is global state?** written and read by more entities (shared variables, message soup)
3. **What is the type of the variables?**
3. **Is there state not fitting in Points 1 and 2?** Ask user for advice

| Variable | Type | Purpose | Scope |
| --- | --- | --- | --- |
| `varName` | int / enum / record | What it tracks | Global / per-node |


### Step 1.3: Analyze the actions in the state machine

1. **Init**
2. **What are the actions that constitute Next?** Separate entity actions from environment actions. What are effects on local state and global state

### Step 1.4: Extract System Model Assumptions

Before writing any code, identify the protocol's assumptions. They become `const` declarations and `assume` axioms.

| Concern | Questions to answer |
| --- | --- |
| **Communication** | Reliable or lossy? Ordered or unordered? Broadcast or point-to-point? |
| **Failures** | Crash-stop? Crash-recovery? Byzantine? What fraction `f` of `n`? |
| **Time** | Synchronous? Asynchronous? Partial synchrony? Are timeouts modelled? |
| **Participants** | Fixed membership or dynamic? How many processes? |


## Phase 2: Design the Model

### Step 2.1: Separate Concerns

Partition what you found in Phase 1 into three buckets:

- **State machine** — variables, initialization, transitions (becomes `var`, `init`, actions)
- **Functional logic** — pure computations: quorum checks, message filtering, state updates (becomes `pure def`)
- **Properties** — what must always hold, what must be reachable (becomes `val` invariants + witnesses)

Do not mix these layers.

### Step 2.2: Decide Variable Grouping

For each set of variables, ask: **do these form a cohesive logical/semantic entity?**

**Group into a record when:**
- They represent one process's local state (e.g. `log`, `votedFor`, `currentTerm` for one Raft node)
- There are N instances — use `NodeId -> LocalState`
- Invariants relate multiple fields of the same entity

**Keep flat when:**
- Variables represent distinct concerns that change independently
- There is one instance (single actor) — grouping adds no clarity
- Variables have different owners

```quint
// Source: per-node state (Raft)
// → grouped — N nodes, always accessed together
type NodeState = { log: List[Entry], votedFor: Option[int], currentTerm: int }
var nodes: int -> NodeState

// Source: global environment
// → flat — single instance, distinct concerns
var messages: Set[Message]
var leader:   Option[int]
```


### Step 2.3: Propose the Type Sketch and Get Approval

Write only the types and `var` declarations. No functions, no actions yet. Show it to the user:

```quint
module Raft {
  type Entry    = { term: int, value: str }
  type NodeState = { log: List[Entry], votedFor: Option[int], currentTerm: int }
  type Message  =
    | VoteRequest({ term: int, candidateId: int })
    | VoteResponse({ term: int, voterId: int, granted: bool })

  pure val N: int = 3
  const NODES: Set[int] = 1.to(N)

  var nodes:    int -> NodeState
  var messages: Set[Message]
}
```

Run ``quint typecheck`` — it must pass. Then **stop and present this to the user**. Do not proceed until you have explicit approval on the types and grouping.

---

## Phase 3: Write the Quint Specification

Follow the conventions in the quint-lang skill guidelines.


## Phase 4: Properties

### Step 4.1: Translate TLA+ invariants faithfully

Find every TLA+ invariant operator (`INVARIANT` clause, or operators named `Inv`, `TypeOK`, `Safety`, etc.). For each one:

- Write a `val` with the **same name** and the **same conjunct order**.
- Precede each conjunct with a comment quoting or paraphrasing the TLA+ formula, e.g.:
  ```quint
  // TypeOK: ∀ a ∈ Acceptor : maxBal[a] ∈ Ballot ∪ {-1}
  Acceptor.forall(a => ...)
  and
  // ∀ m ∈ msgs : m.type="1b" => maxBal[m.acc] ≥ m.bal
  soup.forall(msg => ...)
  ```
- Do **not** add conjuncts, split into helper `val`s, or introduce safety properties beyond what the TLA+ spec defines.

### Step 4.2: Witnesses — infer and ask the user

Witnesses have **no TLA+ counterpart**. They are reachability checks added specifically for Quint simulation. Before writing any:

1. List the major actions in the spec (from `Next`).
2. Present the list to the user and ask which reachability properties they want to verify.
3. Write only the witnesses the user approves.

Every witness `val` **must** carry this comment:
```quint
// Witness: not in TLA+, inferred for reachability checking
```

Example:
```quint
// Witness: not in TLA+, inferred for reachability checking
// Reachable if VIOLATED: a Phase1a message has been sent
val can1aSent: bool =
  not(soup.exists(msg => match msg { | Phase1a(_) => true | _ => false }))
```

Check witnesses before invariants. A satisfied witness means an action is dead — fix that before spending time on safety.

### Step 4.3: Simulate

Run invariant + witnesses with ``quint run`` (`witnesses`, `invariants`, `main_module`). Pass the **analysis module name** (e.g. `PaxosAnalysis`) as `main_module` — not the spec module — because the concrete `init` and `step` live there:

Use tool args equivalent to:
- `spec_path=quint-specs/SpecName.qnt`
- `main_module=NameAnalysis`
- `invariants=[inv]`
- `witnesses=[canAction1, canAction2, ...]`
- `max_samples=1000`
- `max_steps=100`

After the simulation passes, write the `README.md` as described in the **Output** section below. Record the verbatim command and output. Add the date.

---

## Output

The deliverables for a completed translation are:

### 1. Quint specification module

The spec module is the faithful TLA+ translation. Its required contents:

- **first line must be `// -*- mode: Bluespec; -*-`** — this editor mode line must appear before any other content including the module header comment.
- everything the TLA+ contains: same names, same structure, same properties, same conjunct order.
- a pure functional layer (`pure def`) for all guards and state computation; actions are thin wrappers that call pure defs and assign next state.
- Choreo for any TLA+ message soup (see Philosophy section).
- no witnesses, runs, or concrete instances — those belong in the `NameAnalysis` module below.
- typechecks cleanly and every action fires correctly in the REPL before moving on.

### 2. NameAnalysis module (appended to the same .qnt file)

A second Quint module written at the bottom of the same `.qnt` file — no separate file is created. It contains:
- a concrete instantiation of the spec module (e.g. 3 nodes, specific constant values)
- happy-path runs that show how the protocol works (e.g. a successful leader election)
- witnesses that show reachability of key states (e.g. a node voting for a candidate, a node accepting a leader)

The module name follows the pattern `<SpecName>Analysis`, e.g. `PaxosAnalysis`. Use `--main PaxosAnalysis` (not the spec module name) when running `quint run` or `quint simulate`, because the analysis module holds the concrete `init` and `step`.

Minimal skeleton:
```quint
module PaxosAnalysis {
  import Paxos(
    Acceptor = Set(1, 2, 3),
    // ... other constants
  ).*

  // happy-path run
  run happyPathTest = { ... }

  // Witness: not in TLA+, inferred for reachability checking
  val canPhase1aSent: bool = ...
}
```

### 3. README.md (next to the .qnt file)

The README documents the translation and records simulation results. It must contain:

**Purpose** — one paragraph: Quint translation of which TLA+ spec, link to the TLA+
source, brief description of what the protocol does.

**Invariants** — for each `val` invariant: its name, the TLA+ operator it translates,
and a one-line description of what it checks. Note that invariants are taken directly
from the TLA+ spec, not invented.

**Witnesses** — table: name, what it confirms is reachable. State explicitly that
witnesses are not in the TLA+ spec and were added for simulation coverage.

**Experiments** — the executed ``quint run`` arguments and output summary (the `[ok]`
line, trace-length statistics, witness counts), plus a one-sentence interpretation.
Use combined invariant/witness tool arguments:

```
tool: `quint run`
spec_path: quint-specs/SpecName.qnt
main_module: NameAnalysis
invariants: [inv]
witnesses: [canA, canB, ...]
max_samples: 1000
max_steps: 100
```

Record the date of each run. When parameters are changed (e.g. higher `--max-steps`),
add a new dated run block rather than overwriting the old one.

---

## Tips for Effective Modelling

1. **Start with one action** — get `init` + one action + one witness working before adding more
2. **Use small node sets** — `N = 3` is enough for most safety properties; `N = 2` for initial exploration
3. **Test pure functions in isolation** — REPL with hand-crafted states catches logic bugs before wiring
4. **Message soup, not queues** — unless message ordering is what you are verifying, store all messages in a set and never delete them
5. **Name types after the protocol** — `VoteRequest`, `PreVote`, `PrepareMsg` not `Msg1`, `Msg2`
6. **Typecheck after every addition** — don't accumulate type errors. Use ``quint typecheck``. Exit code 0 = pass; non-zero = errors reported in tool output.

## Common Pitfalls

| Pitfall | Solution |
| --- | --- |
| Logic in actions | Move all computation to `pure def`; actions only call and update |
| Empty map access | Pre-populate every map with `mapBy` in `init` |
| `.with()` for record update | Use `{ ...record, field: newValue }` |
| `Map[K,V]` type syntax | Use `K -> V` |
| `pure def f() =` (empty parens) | Use `pure def f =` for parameterless defs |
| Nested pattern match | Match one level at a time; bind inner value and match separately |
| String manipulation | Strings are opaque — use sum types or records instead |
| Modelling all N threads at once | Add one actor, verify, then generalise to N |
| `val` is a keyword | Cannot use as a record field name (common in TLA+). Use `value` instead |
| `require(cond)` in actions | `require` does not exist in Quint actions. Write the condition directly as `cond,` in the `all { }` block |
| `ASSUME` → `assume` | Do not use Quint's `assume` keyword. Translate TLA+ `ASSUME` as a `run` test (see Philosophy section above) |
| `msgs` / message soup → plain `Set[Message]` | Use Choreo instead. Any TLA+ spec with a message soup must prompt a Choreo design discussion in Phase 2 before writing code |
| Parenthetical insertions with em-dashes in README or Quint comments | Do not write sentences that insert a clause between em-dashes ("X — which does Y — Z"). Use separate sentences or plain parentheses instead |
| TLA+ `EXTENDS` → duplicating all functions | Use `import M(...) as m` + `export m`. The extending module re-declares shared `const`s and passes them through. Functions with no `const` refs in their body are safely reusable as `m::f`. |
| `type T[v] = ...` in same module as `const X: Set[T]`, instantiated with `X = Set(Constructor(v))` | Quint detects a self-referential cycle: `Constructor` is defined by `T` which is defined in the module being instantiated. Fix: extract `type T[v]` to a separate shared module imported by both base and extending modules. |
| `m::f` fails at runtime with "Uninitialized const" when passed as a higher-order argument | `f` closes over a `const` from module `M`; Quint does not propagate const bindings through higher-order calls across module boundaries. Fix: rewrite `f` to avoid const references — use the type structure instead (e.g. `x != SentinelA and x != SentinelB` rather than `Values.contains(x)`). |
| `paxos::TypeOKInvariant` (a `val`) fails at runtime with "Uninitialized const" | Quint does not propagate `const` bindings when a `val` is accessed across module boundaries, even without higher-order calls. Fix: extract the invariant body into a `pure def` that takes the consts as explicit parameters, then call that `pure def` from both the base `val` and the extending module. See pattern below. |
