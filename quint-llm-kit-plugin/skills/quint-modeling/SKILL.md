---
name: quint-modeling
description: >
  Generate a Quint specification from whatever you have — an idea to develop interactively,
  natural-language or functional requirements, source code (Rust, Go, TypeScript, etc.), or an
  existing TLA+ specification.
  Walks through the modelling flow — identifying state, actions, and invariants — and adapts
  to the source type. Use whenever the user wants to model, specify, or formally describe a
  system, protocol, or algorithm in Quint, or to translate code or a TLA+ spec into Quint —
  even if they don't use the word "specification." Also use when the user wants to verify,
  model-check, or formally check a design or implementation: writing the Quint model is the
  required first step, so begin here. For Quint language syntax and the CLI, see the
  quint-lang reference.
---

# Quint Modelling

Produce a Quint specification from whatever the user starts with. This skill owns the
**shared modelling discipline** (below) and **routes** to a flow-specific guideline for the
intake — the part that turns a particular kind of input into the understanding the shared
steps build on.

For language syntax, operators, the CLI, and `basicSpells`, defer to the **quint-lang**
reference. This skill is about *how to model*, not Quint syntax.

---

## Pick the flow

Identify what the user is starting from, then read the matching guideline. The guideline
handles **intake** — extracting the system's state, operations, and assumptions from that
source. After intake, everyone converges on the **Shared modelling spine** below.

| Starting point | Flow | Guideline |
|---|---|---|
| Only an idea / informal proposal, built interactively with the user | **from nothing** | `guidelines/from-nothing.md` |
| A written requirements / functional-spec document | **from requirements** | `guidelines/from-requirements.md` |
| Source code (Rust, Go, TypeScript, …) | **from code** | `guidelines/from-code.md` |
| An existing TLA+ specification | **from TLA+** | `guidelines/from-tlaplus.md` |

If the starting point is ambiguous (e.g. "a design doc with some pseudocode"), ask the user
which source is authoritative before picking — the intake differs materially.

---

## Shared modelling spine

Every flow lands here. Intake (flow-specific) produces an **understanding** of the system:
its entities, the operations they perform, the state each operation reads and writes, and the
system-model assumptions (communication, failures, time, participants). The spine turns that
understanding into a verified Quint spec.

Two principles hold throughout:

- **Executable from the first line.** Quint specs run immediately — you validate design
  decisions as you make them, not at the end. Never build more than one step without
  verifying the previous one (`quint typecheck`, then `quint run` / `quint test`).
- **What, not how.** Model observable state transitions and their effects. Abstract away
  implementation detail (serialization, memory management, retry plumbing). If a detail
  doesn't affect an invariant you care about, it doesn't belong in the spec.

### Step 1 — Separate concerns

Partition the understanding into three layers. Keeping them apart is what makes a spec
testable; mixing them is the most common source of untestable specs.

- **State machine** — variables, initialization, transitions → `var`, `init`, actions
- **Functional logic** — pure computations: guards, quorum checks, state updates → `pure def`
- **Properties** — what must always hold, what must be reachable → `val` invariants + witnesses

Also pin down the **system-model assumptions** — they shape every invariant built on top.
Encode them as **`const` declarations**. To actually *check* an assumption (e.g. a quorum
condition like `2 * f < n`), write a **`run` test** that asserts it — a `run` test executes
and fails if the condition is violated. You may also state a premise with the `assume`
keyword, but the current toolchain does **not** enforce it — a violated `assume` is not
flagged by `quint run`, `test`, or `verify` — so don't rely on it as a check. Each flow's
intake fills this in from its own source (interview, requirements doc, code, or TLA+); the
checklist is the same regardless:

| Concern | Questions to answer |
|---|---|
| **Communication** | Reliable or lossy? Ordered or unordered? Broadcast or point-to-point? |
| **Failures** | Crash-stop? Crash-recovery? Byzantine? What fraction `f` of `n`? |
| **Time** | Synchronous? Asynchronous? Partial synchrony? Are timeouts modelled? |
| **Participants** | Fixed membership or dynamic? How many processes? |

If an assumption is wrong, every property built on it is wrong — surface them before building.

### Step 2 — Shape the state

Group cohesive state into a record and let the **functional layer operate on that record**.

**Default — one cohesive unit:**

```quint
type State = {
  phase:    str,
  balances: NodeId -> int,
  members:  Set[NodeId],
}

var state: State
```

Pure functions take and return `State`; actions assign the next-state record directly
(`state' = result.newState`). No per-field reassembly.

**Scaling to N instances** — when there are N actors, the record describes **one** actor's
local state, and the variable becomes a map keyed by actor id. The pure functions are
**unchanged** — they still operate on a single `LocalState`; only the wiring around them
changes:

```quint
type NodeId = int
type LocalState = { phase: str, balance: int, voted: bool }

var nodes:    NodeId -> LocalState   // per-actor cohesive state
var messages: Set[Message]           // genuinely global concern → its OWN var, not inside LocalState
```

| | One instance | N instances |
|---|---|---|
| state var | `var state: State` | `var nodes: NodeId -> LocalState` |
| pure fn | `(State, …) => {success, newState: State}` | `(LocalState, …) => {success, newState: LocalState}` — same shape |
| action read | reads `state` | `nodes.get(id)` |
| action write | `state' = result.newState` | `nodes' = nodes.set(id, result.newState)` |
| `init` | one record literal | `NODES.mapBy(_ => <record>)` |

The rule, stated once: **group what is cohesive into a record; one var for one unit, a
`Id -> LocalState` map for N, and keep genuinely independent concerns (the message soup, a
shared registry) as their own separate vars** — never crammed into the per-instance record.

#### When to use Choreo instead

For **event-driven distributed protocols with N processes** (consensus, BFT, multi-phase
commit), the Choreo framework is often a better structure than the plain
`NodeId -> LocalState` + message-soup layout above. It gives you pre-built abstractions for
message passing, per-process listen/react handlers, and a clean split between local-state
updates and network effects. This is a structural fork — decide it **here**, before writing
logic, and confirm the node/role decomposition with the user.

**Reach for Choreo when:**
- Each process reacts to incoming messages with distinct handlers per message type
- You want local state manipulation cleanly separated from network effects
- The protocol has a clear listen → react shape (a message soup, a `Send`/broadcast pattern)

**Stick with plain Quint when:**
- The protocol is simple or has a single actor
- You are still exploring the design
- There is no clear listen/react structure

When Choreo fits, the per-process state still follows the grouping rule above — Choreo just
supplies the messaging and handler scaffolding around it. See
`../quint-lang/guidelines/choreo.md` for the framework's API and patterns.

Decide grouping (and Choreo-or-not) with the user and **get explicit approval on the type
sketch before writing any logic** (Step 3). Typecheck the types + `var` declarations first;
this is the highest-leverage review point — a wrong shape is expensive to unwind later.

### Step 3 — Write the functional logic (pure functions)

Implement each operation as a `pure def` that takes the state record and returns
`{ success: bool, newState: <record> }`. All business logic lives here.

```quint
pure def transfer(s: State, from: NodeId, recipient: NodeId, amount: int):
  { success: bool, newState: State } =
  if (s.balances.get(from) >= amount and amount > 0)
    { success: true,
      newState: { ...s, balances: s.balances.setBy(from, b => b - amount)
                                            .setBy(recipient, b => b + amount) } }
  else
    { success: false, newState: s }
```

Write signatures first (stub the bodies), typecheck, then fill in one function at a time and
exercise each in the REPL with a hand-built state before moving on. If the output surprises
you, the function has a bug — fix it before wiring it into the state machine.

> Why pure-functions-first: a pure function can be tested in isolation with any input state.
> Logic buried in an action can only be tested by driving the whole state machine. Even if the
> user asks for an action directly, write the `pure def` first — the action is a thin wrapper.

### Step 4 — Wire the state machine (thin actions)

Actions do exactly three things: call the pure function, check `success`, assign the next
state. No logic in actions beyond the `success` check.

```quint
action init: bool = all {
  state' = { phase: "idle",
             balances: NODES.mapBy(_ => INITIAL_BALANCE),   // pre-populate every map
             members: NODES },
}

action unchanged_all: bool = all { state' = state }

action transferAction(from: NodeId, recipient: NodeId, amount: int): bool = {
  val result = transfer(state, from, recipient, amount)
  if (result.success) state' = result.newState else unchanged_all
}
```

The action and its pure function must have **different names** (a `pure def` and an `action`
cannot share a name). Pre-populate every map in `init` — `.get()` on an absent key is
undefined behavior. See quint-lang for the full list of such gotchas.

### Step 5 — Properties: witnesses first, then invariants

**Witnesses first.** A witness asserts a target state is *reachable*, written as
`not(target)` so that a **violation means the state was reached — which is the success case**.
Add one per major action. A witness that is *satisfied* means the action is dead (its
precondition can never hold) — fix that before spending effort on safety.

```quint
// VIOLATED = ✅ the action is reachable.  SATISFIED = ❌ over-constrained — fix the action.
val canTransferSuccessfully: bool =
  not(state.members.exists(n => state.balances.get(n) != INITIAL_BALANCE))
```

**Then invariants** — the safety properties that must hold in every reachable state:

```quint
val noNegativeBalances: bool =
  state.members.forall(n => state.balances.get(n) >= 0)
```

(Witness vs invariant interpretation, fairness, and temporal properties are detailed in
quint-lang's `guidelines/simulations.md`. The witness above checks that a *state* is reachable
(some balance changed). If you instead need a witness to assert an **action actually
succeeded** — not merely that a matching state exists — quint-lang's `guidelines/patterns.md`
describes the `lastActionSuccess` technique and how to debug a witness that never fires. Reach
for it when state evidence alone can't distinguish a successful transition from a coincidence.)

### Step 6 — Compose `step` and simulate

Compose the actions in `any { ... }` and stress the model with random walks.

```quint
action step: bool = {
  nondet from = NODES.oneOf()
  nondet dst  = NODES.oneOf()   // `dst`, not `to` (a built-in) — see quint-lang
  any {
    transferAction(from, dst, 10),
    // other actions…
  }
}
```

- Check **witnesses** with `quint run` — expect them VIOLATED (reachable).
- Check **invariants** with `quint run` (sampled) and `quint verify` (bounded-exhaustive) —
  expect no violation. Read counterexample traces step by step when one appears.

Tests (`run` definitions) go in a **separate `*_test.qnt` file** that imports the spec — keep
the main module free of test scenarios. Build incrementally: typecheck after every addition,
simulate after every action.

### Step 7 — Hand off the spec

A finished spec needs a short record so the next reader knows its scope and can trust it.
Produce one (as a comment block, a `README.md`, or whatever the flow prefers) covering:

- **What it covers** — which modules/protocols are modelled, which assumptions (`const`
  declarations, with `run`-test checks for the ones that must hold) are encoded, which
  properties are verified.
- **What it does NOT cover** — implementation detail left out on purpose, edge cases excluded
  (and why), properties still to add. This honesty note is what stops the spec from being
  over-trusted.
- **When to update it** — for a spec that grounds an artifact (code, a TLA+ source), update
  the spec and re-verify *before* changing the artifact.

**The spec is the ground truth. Never edit the spec to match broken code.** If the spec is
wrong, stop and discuss with the user — that is the highest-leverage review point.

Each flow adds its own format detail (source-file correspondence for code, a translation
README with recorded `quint run` output for TLA+, a comment block for an interactive build).

---

## Conventions

- `NodeId` / `LocalState` for per-actor state; descriptive type names after the protocol
  (`VoteRequest`, `PrepareMsg`) not `Msg1`, `Msg2`.
- Small domains: `N = 3` actors (or `N = 2` for first exploration) and value ranges like
  `0..10` are enough for most safety properties and keep simulation cheap. Use **symbolic IDs**
  (`int` or `str`) for participants.
- Message soup: store sent messages in one `Set` and don't model delivery order unless
  ordering is what you're verifying.
- Abstract time: when the protocol has a notion of time or progress, model it as an integer
  **round/epoch counter** (`round: int`), not wall-clock time or timer mechanics — a timeout is
  just the round advancing. Exception: model timing explicitly only when the timing bound
  itself is what you're verifying.
- Start with **one action**: get `init` + one action + one witness working before adding the
  rest. For N actors, model **one actor first, verify, then generalize** to the map — never
  wire up all N at once.
- Test pure functions in **isolation** in the REPL with hand-built states; that catches logic
  bugs before they get tangled into the state machine.

For everything syntactic — operators, undefined-behavior rules, `basicSpells`, the CLI flags —
consult the **quint-lang** reference rather than reproducing it here.
