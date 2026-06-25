---
name: quint-modeling
description: >
  Build a Quint model of a system, protocol, or algorithm. Use this whenever the user wants to
  model, spec out, formally describe, model-check, or verify a system in Quint — e.g. "model this
  protocol in Quint", "spec out this design", "translate this TLA+", "formally check this Rust
  code" — even if they never say the word "specification." When the goal is to verify or
  model-check a design or implementation and no Quint model exists yet, writing the model is the
  required first step, so start here. It generates the spec from whatever the user has — an idea
  developed interactively, natural-language or functional requirements, source code (Rust, Go,
  TypeScript, etc.), or an existing TLA+ specification — and walks the modelling flow (state,
  actions, invariants), adapting to the source type. Also use this to **review or audit an
  existing Quint spec** — "review my .qnt", "audit this spec before I ship it", "is this model
  any good" — it carries the structural + runtime review checklist. Do NOT use this for
  implementing code against a spec that already exists (that's quint-execute-spec) or for pure
  Quint syntax/CLI/debugging questions (quint-lang). For Quint language syntax and the CLI, see the
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
| A **finished `.qnt` spec to audit**, not build | **review** | `guidelines/review.md` |

The first four are **build** flows: intake → the Shared modelling spine below. The **review**
flow is different — there is no new model to produce; you audit an existing spec against a
checklist and report findings. It does not use the spine; read `guidelines/review.md` and follow
it directly.

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
  verifying the previous one: `quint typecheck`, **then `quint run`**. Typecheck is not
  enough — a spec can typecheck and still fail to *execute*, which defeats the whole point of
  an executable spec. The trap to watch for: a **`const` not given a value** typechecks but
  cannot run — `quint run` fails with `Uninitialized const`. To make the spec runnable,
  **instantiate the const in a concrete instance module** —
  `module spec_3 { import spec(C = Set(1,2,3)).* }` — and run *that* module. (`assume` documents a
  premise; it does not supply a value — see Step 1 and quint-lang's `guidelines/simulations.md`.)
  After each addition, actually run it — if you can't `quint run` the module, it isn't done.
- **What, not how.** Model observable state transitions and their effects. Abstract away
  implementation detail (serialization, memory management, retry plumbing). If a detail
  doesn't affect an invariant you care about, it doesn't belong in the spec.

### Step 1 — Separate concerns

Partition the understanding into three layers. Keeping them apart is what makes a spec
testable; mixing them is the most common source of untestable specs.

- **State machine** — variables, initialization, transitions → `var`, `init`, actions
- **Functional logic** — pure computations: guards, quorum checks, state updates → `pure def`
- **Properties** — what must always hold, what must be reachable, what must *eventually* happen →
  `val` invariants + witnesses, plus `temporal` properties for liveness (Step 5; quint-lang has the detail)

Also pin down the **system-model assumptions** — they shape every invariant built on top.
Encode them as **`const` declarations**. To actually *check* an assumption (e.g. a quorum
condition like `2 * f < n`), write a **`run` test** that asserts it — the `assume` keyword
*documents* a premise but is not enforced, so don't rely on it as a check (see quint-lang's
`## Assume` for why and the `run`-test pattern). Each flow's intake fills this in from its own
source (interview, requirements doc, code, or TLA+); the checklist is the same regardless:

| Concern | Questions to answer |
|---|---|
| **Communication** | Reliable or lossy? Ordered or unordered? Broadcast or point-to-point? |
| **Failures** | Crash-stop? Crash-recovery? Byzantine? What fraction `f` of `n`? |
| **Time** | Synchronous? Asynchronous? Partial synchrony? Are timeouts modelled? |
| **Participants** | Fixed membership or dynamic? How many processes? |

If an assumption is wrong, every property built on it is wrong — surface them before building.

### Step 2 — Shape the state

**Group cohesive state into a record** and let the functional layer operate on that record — this is
the recommended shape, because most of the time the variables that describe one entity *are*
cohesive, and grouping keeps the functional layer clean and the invariants readable. Keeping
variables flat is the deliberate exception, not a co-equal default:

- **Group into a record when** the fields are the local state of one entity (a node's phase + log +
  vote), are always passed together, or an invariant relates several of them. This is the usual case.
- **Keep flat (separate `var`s) only when** the variables are genuinely independent concerns that
  change on their own, or the spec is small enough that grouping adds no clarity. (Some canonical
  examples, e.g. `ewd840`, keep per-field maps flat because the fields don't form an obvious unit.)

**The cohesive case — one unit:**

```quint
type State = {
  phase:    str,
  balances: NodeId -> int,
  members:  Set[NodeId],
}

var state: State
```

The `apply…` pure functions take and return `State`; actions assign the next-state record directly
(`state' = applyTransfer(state, …)`). No per-field reassembly.

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
| pure fns | `can…(State, …): bool` + `apply…(State, …): State` | `can…(LocalState, …): bool` + `apply…(LocalState, …): LocalState` — same shape |
| action read | reads `state` | `nodes.get(id)` |
| action write | `state' = applyOp(state, …)` | `nodes' = nodes.set(id, applyOp(nodes.get(id), …))` |
| `init` | one record literal | `NODES.mapBy(_ => <record>)` |

The guideline, stated once: **group cohesive state into a record (one var for one unit, an
`Id -> LocalState` map for N), and keep genuinely independent concerns — the message soup, a shared
registry — as their own separate vars**, never crammed into the per-instance record. Reach for flat
per-field vars only when the fields don't cohere into a unit.

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

Implement each operation's logic as `pure def`s — they take the state record and arguments and
return plain values, so you can exercise them in the REPL with hand-built states. Split the two
distinct questions a transition answers:

- **Can it happen?** — a `pure def … : bool` guard (the precondition).
- **What's the resulting state?** — a `pure def … : State` that computes the next state, *assuming*
  the guard holds.

```quint
pure def canTransfer(s: State, from: NodeId, recipient: NodeId, amount: int): bool =
  amount > 0 and from != recipient and s.balances.get(from) >= amount

pure def applyTransfer(s: State, from: NodeId, recipient: NodeId, amount: int): State =
  { ...s, balances: s.balances.setBy(from, b => b - amount)
                              .setBy(recipient, b => b + amount) }
```

Write signatures first (stub the bodies), typecheck, then fill in one function at a time and
exercise each in the REPL with a hand-built state before moving on. If the output surprises
you, the function has a bug — fix it before wiring it into the state machine.

> Keep the guard separate from the update because they are separate facts about the operation: one
> says *when* it is allowed, the other says *what it does*. The action (Step 4) uses the guard to
> decide whether it fires at all. A single `pure def` returning `{ success, newState }` — handing
> back the unchanged state when the guard fails — fuses the two and pushes the action toward a no-op
> branch; prefer the split. (If a *failed* operation is itself something the system observes and
> reacts to, model that failure as its own guarded action, not as a fallback.)

### Step 4 — Wire the state machine (guarded actions)

An action puts the guard and the update together in one `all { ... }`: the guard gates whether the
action fires, the update sets the next state. When the guard is false the action is **disabled** —
it does not fire and does not change anything. No `success` flag, no no-op branch.

```quint
action init: bool = all {
  state' = { phase: "idle",
             balances: NODES.mapBy(_ => INITIAL_BALANCE),   // pre-populate every map
             members: NODES },
}

action transferAction(from: NodeId, recipient: NodeId, amount: int): bool = all {
  canTransfer(state, from, recipient, amount),          // guard — disables the action when false
  state' = applyTransfer(state, from, recipient, amount),
}
```

A disabled action is the faithful model of "this cannot happen in this state." Resist adding a
blanket `else` / `unchanged_all` fallback to keep things moving — that puts a transition in the
model that the real system can't take, which is a modeling inaccuracy regardless of what you do
with the spec afterward.

An action and a `pure def` cannot share a name. Pre-populate every map in `init` — `.get()` on an
absent key is undefined behavior. See quint-lang for the full list of such gotchas.

### Step 5 — Properties: witnesses first, then invariants

**Witnesses first.** A witness names a target state and asks whether it is *reachable* — write the
predicate **positively** (the state you hope to reach) and pass it to `quint run --witnesses`, which
reports **how many sampled traces reached it**. Add one per major action: a witness reached in 0
traces means the action is dead (its precondition can never hold), so fix that before spending
effort on safety.

```quint
// the state you want to be reachable — written plainly, no negation
val someBalanceChanged: bool =
  state.members.exists(n => state.balances.get(n) != INITIAL_BALANCE)
```

```
quint run spec.qnt --witnesses someBalanceChanged --max-steps 10
  → someBalanceChanged was witnessed in 90 trace(s) out of 100 explored (90.00%)
```

A non-zero count means the state is reachable; **0% means it never happened** — investigate.

There is a second, complementary form: write the *negation* as an invariant — `val w = not(target)`
— so a reported "violation" is an execution that *reaches* the state. It can't batch with the other
invariants and you read a "violation" as success, but it gives you something `--witnesses` cannot: an
**actual trace** that reaches the state. Pick by what you need — `--witnesses` for the routine
reachability + coverage check, the negated-invariant form when you want to *see the path* (to
understand or document how the state is reached, or to debug a witness that fires unexpectedly).

**Then invariants** — the safety properties that must hold in every reachable state:

```quint
val noNegativeBalances: bool =
  state.members.forall(n => state.balances.get(n) >= 0)
```

Invariants and witnesses run together in one pass: `quint run --invariant noNegativeBalances
--witnesses someBalanceChanged`.

When a source yields *many* candidate properties and you need to prioritize verification effort,
the from-requirements flow describes a High/Medium/Low impact-scoring aid (`guidelines/from-requirements.md`);
it applies wherever you're modelling against stated requirements.

(Witness vs invariant interpretation, fairness, and temporal properties are detailed in quint-lang's
`guidelines/simulations.md`. `someBalanceChanged` is *state* evidence — phrase such a target so only
an action can make it true, since a predicate that already holds at `init` is "reached" at step 0 and
witnesses nothing. To confirm a *specific* action fired when several could reach the same state, use a
per-action flag `var` — quint-lang's `guidelines/patterns.md` §7 covers it and how to debug a witness
that never fires.)

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

- Check **witnesses** with `quint run --witnesses` — expect a non-zero trace count (reachable);
  0% means a dead action.
- Check **invariants** with `quint run` (sampled) and `quint verify` (bounded-exhaustive) —
  expect no violation. Read counterexample traces step by step when one appears.

#### A guarded model can reach a state where nothing is enabled

Because actions are guarded (Step 4), the model can reach a state with **no enabled action**. Which
tool tells you, and what it means, both matter:

- **`quint verify`** detects it and reports it outright: `Found a deadlock. The outcome is:
  Deadlock`. Use it when you want to know whether the model can get stuck.
- **`quint run` does not detect deadlocks** — it stops early and prints `[ok] No violation found`
  with a trace shorter than `--max-steps`. A short trace is the only hint; the run reads as success.

Whether reaching such a state is correct depends on the system: one that should keep serving must
never get stuck, while one that genuinely finishes (everyone committed, nothing left to do) is
*supposed* to end in a terminal state. The tool can't tell these apart — only you know which you
intended. (This is the other reason Step 4 avoids the no-op fallback: a blanket `unchanged_all`
lets every trace extend forever, so the model can never reach — or reveal — such a state.)

**A note on bounding.** `--max-steps` (how deep a run explores) is not a modeling decision — it's
always there. Whether the *model itself* has a bounded state space is: some protocols are
**terminating by construction** (a one-shot commit reaches a final state and stops), and modeling
them that way is correct — reaching a terminal state is the design, not a deadlock. You may also
bound an otherwise-unbounded model deliberately to shrink the state space, but never with a no-op
escape hatch (Step 4) — bound it by modeling the real terminal states, not by a fake step.

Tests (`run` definitions) go in a **separate `*_test.qnt` file** that imports the spec — keep
the main module free of test scenarios. Build incrementally: typecheck after every addition,
simulate after every action.

### Step 7 — Self-review, then hand off the spec

Before writing the handoff record, do a quick pass over your own spec against the same bar a
reviewer would apply — catching these now is cheaper than having them bounce back. Most you've
already followed while building; this is the closing check that they all hold together:

- **Guarded actions** — no business logic in an action beyond the guard and assignments; it lives
  in `pure def`s, and the guard is lifted into the action so it's disabled when it can't fire (Step 4).
- **Witness per major action** — every action in `step` has a witness, and each one is reached in
  > 0 traces under `quint run --witnesses`, not dead at 0 traces (Step 5).
- **At least one protocol-level invariant** — a real safety property (no two leaders, conservation,
  agreement), not just a type/bounds check; and every invariant references a `var`.
- **`init` assigns every `var`** and every action assigns every `var` (a missing `x' = x` is a
  silent stutter bug); every map is pre-populated (Step 4).
- **Right abstraction** — IDs are opaque (no string manipulation), messages are a `Set` unless
  ordering is the property, no serialization/retry/memory detail leaked in.

If a spec is large or being handed to someone else, run the full audit in `guidelines/review.md`
(the C1–C6 / R1–R2 checklist with a report) — reach for it when a self-pass isn't enough.

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

- `NodeId` / `LocalState` for per-actor state, and `NODES` for the participant set (the `Set[NodeId]`
  the model ranges over); descriptive type names after the protocol (`VoteRequest`, `PrepareMsg`) not
  `Msg1`, `Msg2`.
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
