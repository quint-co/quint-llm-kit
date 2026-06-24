# From code — intake for generating a Quint spec from source

This is the **code-intake flow**: extract a system's structure from source code (Rust, Go,
TypeScript, …). It carries only the code-specific intake; **after intake, follow the shared
spine (Steps 1–7) in `../SKILL.md`.**

## Why a spec from code

**The spec is a persistent grounding artifact, not throwaway output.** It is the source of
truth for what the system *is supposed to do*, used to verify every future change against.

- **Specs are higher leverage than code** — a 50–200 line model captures what 1000 lines of
  prose cannot, and human review at the spec stage is the highest-leverage review point.
- **The spec verifies code; it does not generate it.** Code stays primary. The spec is a
  machine-checked contract, not a code generator.
- **The spec grounds future refactors.** When the code changes, the spec is what you re-verify
  against to know the change preserved the intended behavior.

## Phase 0: Research (compact)

Before reading code in detail, catalog the codebase to keep the main context window lean
(target: under 400 lines of catalog). Skip this for simple single-file cases with a clear
entry point and no concurrency.

> Explore `[path]`. Find and catalog:
> 1. The top-level entry points and their signatures
> 2. The state-carrying data structures (structs, maps, enums)
> 3. The concurrency primitives (mutexes, channels, goroutines, async tasks)
> 4. The message types and their payload shapes
> 5. Any existing tests that reveal expected behavior
>
> Output a compact summary — file paths, key types, key operations. Do not read every file.
> Prioritize what is most relevant to concurrent/distributed behavior.

If the catalog missed something critical, do a targeted follow-up read — do not re-read the
whole codebase from scratch.

## Phase 1: Understand the code

Using the research output, answer in English.

### Step 1.1 — Identify the problem domain

1. **Overall purpose?** (e.g. "distributed leader election", "token transfer protocol")
2. **What entities exist?** (nodes, validators, clients, coordinators)
3. **What resources are shared or contested?** (leader slot, token balances, lock ownership)

### Step 1.2 — Catalog operations and their purpose

| Operation | Purpose | State it reads | State it writes | Concurrency notes |
|---|---|---|---|---|
| `functionName` | What it does | Which vars | Which vars | Atomic? Per-node? |

**Focus on:** public API / entry points, state-modifying operations, message send/receive
points, timeout/timer triggers.

**Skip:** side-effect-free getters, logging, metrics, serialization, retry plumbing (unless
retry is what you're verifying).

### Step 1.3 — Identify state variables

| Variable | Type | Purpose | Scope |
|---|---|---|---|
| `varName` | int / enum / record | What it tracks | Global / per-node |

**Look for:** state-machine enums, per-node bookkeeping, shared global state, message buffers.

### Step 1.4 — Extract system-model assumptions

Read these off the code — concurrency primitives reveal the time model, error/recovery paths
reveal the failure model, transport reveals communication. **Fill in the spine's system-model
assumptions checklist (Step 1)** from what the code shows.

## The source-construct → Quint mapping

This is the heart of code intake: translate each language construct into its Quint counterpart.

| Source | Quint |
|---|---|
| State enum | Sum type `\| State1 \| State2`, or `str` constant |
| Struct / record | `type T = { field1: Type1, field2: Type2 }` |
| `Vec<T>` / array | `List[T]` |
| `HashSet<T>` | `Set[T]` |
| `HashMap<K, V>` | `K -> V` (map type) |
| Thread / process | Element of `NODES`; per-actor `NodeId -> LocalState` |
| Atomic CAS | Guarded action (atomicity is implicit) |
| Message queue | `Set[Message]` — message soup, no ordering unless ordering is what you verify |

**Sum types use named constructors**, not inline tagged records:

```quint
type Message =
  | VoteRequest({ term: int, candidateId: int })
  | VoteResponse({ term: int, voterId: int, granted: bool })
```

## After intake

Hand the understanding (entities, the operations table, the state variables, the filled-in
assumptions checklist) to the **shared spine, Steps 1–7** in `../SKILL.md`. The spine shapes
the state, writes the pure functions, wires thin actions, proposes witnesses-then-invariants,
composes `step`, and simulates. Do not duplicate that work here.

## Handoff (spine Step 7, with a code-specific addition)

Follow the spine's Step 7 handoff (covers / does NOT cover / when to update / ground truth),
and add a **source-file correspondence map** so each module is traceable back to the code it
grounds. When those files change, update the spec first and re-verify before touching the code.

```
quint-specs/Raft.qnt       ↔   src/consensus/raft.rs, src/consensus/log.rs
quint-specs/Membership.qnt ↔   src/cluster/membership.go
```

To implement changes against this spec, use the `quint-execute-spec` skill.
