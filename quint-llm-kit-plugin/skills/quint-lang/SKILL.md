---
name: quint-lang
description: >
  Expert for Quint, a modern specification language and model checker for concurrent and distributed
  systems. Covers the full Quint language, CLI toolchain, distributed protocols and
  concurrent algorithms, and formal verification. Use when: writing/debugging .qnt files,
  modeling distributed systems, verifying safety properties, analyzing invariant violations, optimizing
  state space exploration, or translating TLA+. Keywords: quint, model checking, formal verification,
  TLA+, distributed systems, concurrent systems, complex behaviours, specification language.
---
# Quint Language Reference

Quint is an executable specification language for complex systems, developed by Informal Systems. It compiles to TLA+ and supports simulation and model checking.

**Project convention:** Place all Quint specification files (`.qnt`) inside the **`quint-specs/`** folder. Create, edit, and read only paths under `quint-specs/`.

## Module structure

```quint
module MyProtocol {
  // type aliases, constants, state, actions, properties
}
```

Modules can import others:
```quint
import Voting.*              // all definitions
import Voting(quorum)        // specific definition
import Voting as V           // namespace alias
```

---

## Types

| Type | Description | Example |
|---|---|---|
| `int` | Integers | `-1, 0, 42` |
| `bool` | Booleans | `true, false` |
| `str` | Strings | `"hello"` |
| `Set[T]` | Finite set | `Set(1, 2, 3)` |
| `List[T]` | Ordered sequence | `List(1, 2, 3)` |
| `Map[K, V]` | Key-value map | `Map("a" -> 1)` |
| `(T1, T2)` | Tuple | `(1, "x")` |
| `{ f: T, g: U }` | Record | `{ x: 1, ok: true }` |
| `T \| U` | Sum (variant) | (use type alias) |

Type aliases:
```quint
type NodeId = int
type Phase = str   // "propose" | "vote" | "commit"
```

---

## Definitions

```quint
// Pure function — no state access, usable anywhere
pure def max(a: int, b: int): int = if (a > b) a else b

// State-reading definition — can read vars
val quorum: bool = votes.size() * 2 > nodes.size()

// Constant (fixed value, not a state variable)
pure val N: int = 4
val threshold: int = N / 2 + 1
```

---

## State variables

```quint
type LocalState = {
  leader: int,
  phase: str,
  votes: Set[int],
  log: List[str],
}

var localState: LocalState  // cohesive local protocol state
var peers: int -> str       // independent concern (peer metadata)
```

State variables can only be read in `val` definitions and actions; they cannot be read in `pure def`.

---

## Actions

Actions describe state transitions. They return `bool` — `true` if the action fires.

```quint
action init: bool = all {
  leader' = 0,
  phase' = "idle",
  votes' = Set(),
  log' = List(),
  state' = Map(),
}

action propose(node: int): bool = all {
  require(phase == "idle"),
  require(node > 0),
  leader' = node,
  phase' = "propose",
  votes' = votes,
  log' = log,
  state' = state,
}
```

Key rules:
- Every `var` must be assigned in every action (use `x' = x` to leave unchanged).
- `require(cond)` blocks the action if `cond` is false.
- `all { ... }` — all sub-expressions must hold (conjunction).
- `any { ... }` — at least one must hold (disjunction); the REPL picks non-deterministically.

---

## Non-determinism

```quint
action step: bool = any {
  propose(1),
  propose(2),
  vote,
  timeout,
}

// Non-deterministic choice from a set
action deliverMessage: bool = {
  nondet msg = pending.oneOf()
  all {
    require(pending.size() > 0),
    delivered' = delivered.union(Set(msg)),
    pending' = pending.exclude(Set(msg)),
    // ... other vars unchanged
  }
}
```

---

## Set operators

```quint
Set(1, 2, 3).contains(2)          // true
Set(1, 2).union(Set(2, 3))        // Set(1, 2, 3)
Set(1, 2, 3).intersect(Set(2, 3)) // Set(2, 3)
Set(1, 2, 3).exclude(Set(2))      // Set(1, 3)
Set(1, 2, 3).filter(x => x > 1)  // Set(2, 3)
Set(1, 2, 3).map(x => x * 2)     // Set(2, 4, 6)
Set(1, 2, 3).fold(0, (acc, x) => acc + x)  // 6
Set(1, 2, 3).size()               // 3
Set(1, 2, 3).forall(x => x > 0)  // true
Set(1, 2, 3).exists(x => x > 2)  // true
1.to(5)                           // Set(1, 2, 3, 4, 5)
```

---

## List operators

```quint
List(1, 2, 3).head()              // 1
List(1, 2, 3).tail()              // List(2, 3)
List(1, 2, 3).length()            // 3
List(1, 2, 3).nth(1)              // 2  (0-indexed)
List(1, 2, 3).append(4)           // List(1, 2, 3, 4)
List(1, 2).concat(List(3, 4))     // List(1, 2, 3, 4)
List(1, 2, 3).foldl(0, (acc, x) => acc + x)  // 6
List(1, 2, 3).select(x => x > 1) // List(2, 3)
```

---

## Map operators

```quint
Map("a" -> 1, "b" -> 2).get("a")        // 1
Map("a" -> 1).put("b", 2)               // Map("a" -> 1, "b" -> 2)
Map("a" -> 1, "b" -> 2).keys()          // Set("a", "b")
Map("a" -> 1, "b" -> 2).values()        // Set(1, 2) (as set)
Map("a" -> 1).mapBy(k => k + "!")       // Map("a!" -> 1)  — remap keys
Map("a" -> 1, "b" -> 2).transformValues(v => v * 10)  // Map("a" -> 10, "b" -> 20)
```

---

## Records

Records group related fields into a named type. They are the primary tool for modelling structured state in Quint.

### Type aliases for records

```quint
type NodeState = {
  phase:  str,     // "idle" | "propose" | "vote" | "commit"
  voted:  bool,
  log:    List[int],
}

type Message = {
  from:    int,
  to:      int,
  round:   int,
  payload: str,
}
```

### Creating and accessing

```quint
val n: NodeState = { phase: "idle", voted: false, log: List() }
n.phase                          // "idle"
n.voted                          // false
```

### Updating (immutable — returns a new record)

```quint
{ ...n, phase: "propose" }                          // ✅ spread syntax
{ ...n, voted: true, phase: "vote" }                // ✅ multiple fields at once

n.with("phase", "propose")                          // ❌ .with() causes compile errors
```

### Records as state — when to group variables

TLA+ specs typically flatten all state into independent top-level variables. Quint's type system lets you group them. **When fields describe one cohesive local state, make a record type and use a single state variable of that type.**

**Group into a record when:**
- They represent the local state of a single actor (e.g. one node's phase + log + vote)
- They are always passed together as function arguments
- An invariant relates multiple fields of the same conceptual entity

**Keep flat when:**
- The variables represent distinct concerns that change independently
- The component is simple and grouping adds no clarity
- The variables are intentionally in different ownership/lifecycle domains

### Example: preferred grouped local state vs. anti-pattern

**Preferred (cohesive local state):**
```quint
type LocalState = {
  id: int,
  phase: Phase,
  est1: int,
  est2: Option[int],
  round: int,
  crashed: bool,
  leader: int,
  received_messages: Set[Message],
}

var localState: LocalState
```

**Avoid for cohesive local state:**
```quint
var id: int
var phase: Phase
var est1: int
var est2: Option[int]
var round: int
var crashed: bool
var leader: int
var received_messages: Set[Message]
```

**For N actors, use a map of grouped records:**
```quint
type LocalState = { phase: str, votedFor: int, log: List[int] }

var nodes: int -> LocalState

action becomeFollower(id: int): bool = all {
  require(nodes.get(id).phase == "candidate"),
  val node = nodes.get(id),
  nodes' = nodes.put(id, {...node, phase: "follower"}),
}
```

### Nested records

```quint
type ClusterState = {
  nodes:   Map[int, NodeState],
  leader:  int,
  epoch:   int,
}

var cluster: ClusterState

// Read nested field:
cluster.nodes.get(1).phase

// Update nested field (must rebuild from the inside out):
val updated = {...cluster.nodes.get(1), phase: "leader"}
cluster' = {...cluster, nodes: cluster.nodes.put(1, updated)}
```

### Records in sets (messages, events)

```quint
var inFlight: Set[Message]

action send(src: int, dst: int, r: int, p: str): bool = all {
  inFlight' = inFlight.union(Set({ from: src, to: dst, round: r, payload: p })),
  // ...
}

// Filter by field:
inFlight.filter(m => m.to == nodeId)
inFlight.exists(m => m.round == currentRound and m.payload == "vote")
```

---

## Sum types

Sum types (variants) represent a value that can be one of several distinct cases.

```quint
type Action =
  | { tag: "Propose", value: int, proposer: int }
  | { tag: "Vote",    value: int, voter: int    }
  | { tag: "Decide",  value: int                }
```

Pattern-match with `match`:
```quint
pure def describeAction(a: Action): str =
  match a {
    | { tag: "Propose", ... } => "proposal"
    | { tag: "Vote",    ... } => "vote"
    | { tag: "Decide",  ... } => "decision"
  }
```

Use sum types when a message, event, or state can take structurally different forms — not just different values of the same type.

---

## Enum types
Enum types are a special case of sum types where each case has no additional data.

```quint
type Phase = IDLE | PROPOSE | VOTE | COMMIT
var phase: Phase

if (phase == PROPOSE) { ... }
```

---

## Variable grouping — decision guide

Before writing `var` declarations, answer these questions for each candidate group:

| Question | Group → record if... | Keep flat if... |
|---|---|---|
| Do these vars always change together? | Yes, in most actions | No, they're independent |
| Do they describe the same entity? | Same node / same message / same round | Different concerns |
| Is there one instance or N instances? | Either one or N (group if cohesive; for N use `Id -> RecordType`) | Flat only when concerns are truly independent |
| Do invariants relate them? | Invariant spans multiple fields of one entity | Invariant uses vars independently |

---

## Invariants and temporal properties

```quint
// Safety invariant — must hold in every reachable state
// @invariant
val noDuplicateLeader: bool =
  leaders.size() <= 1

// Temporal property — evaluated over traces
// @temporal
temporal eventualProgress: bool =
  eventually(committed.size() > 0)

// Temporal operators
eventually(p)      // p holds in some future state
always(p)          // p holds in all future states
p.implies(q)       // p => q
```

---

## Assume (axioms)

```quint
assume nodeCountPositive = N > 0
assume quorumMajority = 2 * quorum > N
```

---

## Conditional and let

```quint
if (x > 0) "positive" else "non-positive"

val result = {
  val doubled = x * 2
  doubled + 1
}
```


---

## REPL usage

Prefer CLI commands (`quint typecheck`, `quint run`, `quint test`, `quint verify`) for all validation and execution tasks. Open the REPL (`quint` or `quint -r spec.qnt::ModuleName`) only when you need expression-level interaction the CLI does not provide.

Type inspection:
```
>>> :type myExpression
```

---

## File layout convention

**Put all Quint specs inside the `quint-specs/` folder.** Never create or edit `.qnt` files outside this directory.

```
quint-specs/
  <protocol-name>.qnt        # main module — step, init, vars, invariants
  <protocol-name>_test.qnt   # test module — run tests and scenario witnesses (imports main)
```

When creating, editing, or reading Quint files, always use paths under `quint-specs/` (e.g. `quint-specs/MyProtocol.qnt`).

### Module responsibilities

**Main module** (`<protocol-name>.qnt`):
- Declares all state variables, `init`, actions, and safety invariants
- **`step` must live in the main module** — it is the entry point for `quint run` simulation
- The module name matches the file stem: `module myProtocol` in `myProtocol.qnt`

**Test module** (`<protocol-name>_test.qnt`):
- Imports the main module (`import myProtocol.*`)
- Contains `run` tests and scenario witnesses invoked via `quint test` or `quint run`
- Inherits `step` from the main module through the import

### Which `--main` to pass for `quint run`

`quint run` must receive the module that **owns the property** being checked:

| Property location | Correct `--main` |
|---|---|
| Invariant defined in main module | main module name |
| Witness / `run` test defined in test module | test module name (it imports `step` from main) |

The primitive's `module_name` field (set during indexing) always holds the correct value. Use it directly — do not derive from the filename.

---

## Modelling Approach

Six steps, in order. Never build more than one step without verifying the previous one — use `quint typecheck` and `quint run` / `quint test` first; use the REPL when you need interactive eval or expression-level stepping.

**1. Identify state**
What variables fully describe the system at any point in time? Define `type State` / `type LocalState` as records and prefer a single grouped state variable per cohesive unit. For N processes, use a map `NodeId -> LocalState`. Keep separate top-level vars only for genuinely independent concerns.

**2. Identify operations**
List every action the system supports. For each: name it, list its parameters, state its precondition, and describe what changes. This is design — no code yet.

**3. Write pure functions**
Implement each operation as a `pure def` taking `State` and returning `{success: bool, newState: State}`. Exercise each one with checks you can automate (`quint test` / small `run` blocks) or the REPL when you need interactive inspection. If a pure function surprises you, the spec has a bug.

**4. Wire up the state machine**
Write state variables, `init` (pre-populate every map with `mapBy`), `unchanged_all`, and thin action wrappers that call your pure functions. Validate with `quint typecheck` and `quint run` / `quint test`; use the REPL when you need to step `init` and actions interactively.

**5. Add witnesses, then invariants**
Witnesses first: one per major action, asserting the action's success state is reachable. A satisfied witness means the action is dead — fix it before moving on. Then add invariants for safety properties.

**6. Write `step` and simulate**
Compose all actions in `any { ... }`. Run `quint run --invariant` to stress-test with random walks. Read counterexample traces step by step — the state at each transition tells you exactly what went wrong.

### Abstraction level

Model the **protocol**, not the implementation. The right level is: decisions, roles, messages, and rounds. The wrong level is: network buffers, serialization formats, retry logic, timers.

Rules of thumb:

- **Omit what you're not verifying.** If you're verifying a leader election protocol, omit the application logic that runs on top of it.
- **Use symbolic IDs.** Represent nodes as `str` (`"alice"`, `"p1"`) or `int`, not structs. Keep node sets small — 3 processes is enough for most safety properties.
- **Keep value domains small.** A balance range of `0..10` explores the same safety properties as `0..1000000` at a fraction of the cost.
- **Use the message soup.** Store all sent messages in one set forever. Don't model queues, delivery order, or retransmission unless ordering is what you're verifying.
- **Abstract time.** Use rounds or epochs as integers. Don't model wall-clock time, timeouts as durations, or real-time constraints.
- **Fault model is protocol-level — keep it.** Whether nodes can crash or behave Byzantine is a core protocol assumption. Model it explicitly.

If a detail doesn't affect any invariant you care about, it doesn't belong in the spec.

### When to use Choreo

For event driven distributed protocols with N processes, consider the [Choreo framework](guidelines/choreo.md) instead of writing plain Quint.

**Use Choreo when:**
- Each process reacts to incoming events with distinct handlers per event type
- You need clean separation between local state manipulation and network effects
- You want the `listen_X` / `handle_X` / `choreo::cue` pattern for structured, testable specs

**Stick with plain Quint when:**
- The protocol is simple or has a single actor
- You are still exploring the design
- The protocol does not have a clear listen/react structure

---

## Guidelines

Detailed references — read these when you need more than the quick reference above:

| File | Contents |
| --- | --- |
| `guidelines/operators.md` | Complete operator reference: extended set/list/map operators, `run`/`then`/`expect`/`reps` for tests and witnesses, temporal fairness, `q::debug` |
| `guidelines/simulations.md` | Witnesses vs invariants, result interpretation, progressive increase protocol, trace analysis, coverage standard |
| `guidelines/constraints.md` | Hard language limitations: no string ops, no nested match, no destructuring, no loops, no early returns |
| `guidelines/cli.md` | Full CLI reference: `quint run`, `quint test`, `quint verify` flags, verbosity guide, reading output |
| `guidelines/patterns.md` | 14 core patterns: State Type, Pure Functions, Thin Actions, Map Pre-population, Syntax Rules, Undefined Behavior, Witnesses, Nondeterministic Testing, Separate Test Files, REPL-First Debugging, Separate Concerns First, Extract System Model, Types-First Scaffolding, Logic Stubs |
| `guidelines/tests.md` | Writing and debugging tests: `run`/`then`/`expect`/`reps`/`fail`, nondeterministic tests, error location ≠ failure point, frame counting, REPL-first debugging |
| `guidelines/choreo.md` | Choreo framework for distributed protocols: two-file split, `choreo::cue` pattern, `.with_cue().perform()` testing, witness-based test discovery |
