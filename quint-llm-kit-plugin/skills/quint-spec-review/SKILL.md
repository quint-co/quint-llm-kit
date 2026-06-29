---
name: quint-spec-review
description: >
  Audit a Quint specification for quality, coverage, and correctness. Checks structural patterns
  (thin actions, witnesses, record grouping), abstraction level, non-trivial properties, and runtime
  behavior (init, invariant stability). Use when reviewing a spec at `<spec_path>` before handing
  it off, before implementing against it, or when a collaborator asks for a spec review.
---

# Quint Spec Review

Apply this skill when auditing a Quint spec at **`<spec_path>`**. Read the spec and the
`quint-lang/SKILL.md` skill, then run the checks below.

## Preparation

Before checking:
1. Read the spec. Catalogue: `var` declarations, `pure def` functions, `action` definitions, `val` invariants and witnesses, `temporal` properties, `assume` axioms.
2. For runtime checks (C4, R1, R2): start the REPL with `quint -r <spec_path>::<ModuleName>` and run `init`.

Run all checks. Record **pass / warn / fail** for each. Print the report only after all checks are done.

---

## C1 — Quint patterns respected

**C1a — Thin actions**: Actions must not contain business logic. Each action body should call a `pure def` and update state variables. Logic inside `all { ... }` blocks beyond `require` and assignments signals a logic leak.
- Pass: actions are thin wrappers calling pure functions
- Warn: action `<name>` contains non-trivial logic — move it to a `pure def`

**C1b — Enums over strings**: Roles, phases, and message types must be represented as sum types or typed constants, not raw string literals like `"leader"`, `"propose"`, `"vote"`.
- Pass: sum types or typed constants used for all roles/phases
- Warn: raw string literals found in state or guards — consider a sum type

**C1c — Record grouping**: Related state variables that describe the same entity must be grouped into a record type. A flat list of unrelated `var` declarations with no records signals missing structure.
- Pass: records used to group cohesive state
- Warn: variables `<A>`, `<B>`, `<C>` appear to describe the same entity — consider grouping into a record

**C1d — Witnesses present**: The spec must have at least one witness (a `val` whose condition is `not(target_state)`) alongside invariants. Invariants alone only check safety — witnesses confirm the spec is not over-constrained.
- Pass: ≥1 witness found
- Fail: no witnesses — "Add one witness per major action to confirm the spec can reach interesting states"

---

## C2 — Appropriate abstraction level

**C2a — No string manipulation**: Strings must be used as opaque identifiers only. Concatenation, interpolation, or parsing strings signals implementation detail leaking into the spec.
- Pass: no string manipulation found
- Warn: string manipulation detected — use sum types or records instead

**C2b — Message soup**: Messages must be stored in a `Set`, not in ordered lists or queues. Modelling message ordering is only appropriate when ordering is what the spec is verifying.
- Pass: messages stored as `Set[...]`
- Warn: messages stored as `List[...]` — use message soup unless ordering is a protocol property being verified

**C2c — No implementation concerns**: The spec must not model serialization, retry logic, memory layout, error handling boilerplate, or network-level details unless they directly affect the invariants being checked.
- Pass: no implementation concerns found
- Warn: `<construct>` looks like an implementation detail — explain what protocol property it is verifying

---

## C3 — Spec checks something non-trivial

**C3a — Invariants reference state**: Every invariant must reference at least one `var`. An invariant that is always `true` regardless of state provides no value.
- Pass: all invariants reference state variables
- Warn: invariant `<name>` does not reference any state variable — it is a tautology

**C3b — Witnesses are falsifiable**: Every witness must be a condition the simulator can plausibly violate. A witness of `not(false)` or one whose target state can never be reached is vacuous.
- Pass: witnesses reference plausibly reachable state
- Warn: witness `<name>` looks unfalsifiable — tighten the condition or remove it

**C3c — At least one protocol-level invariant**: The spec must have at least one invariant expressing a real protocol property (safety, consistency, mutual exclusion, agreement) — not just a type check or bounds check.
- Pass: ≥1 protocol-level invariant found
- Fail: all invariants are structural — "Add a safety invariant capturing the core protocol guarantee (e.g. no two leaders, no negative balances, agreement on a single value)"

**C3d — Witnesses cover major actions**: Every major action in `step` should have a corresponding witness confirming it can succeed.
- Pass: all major actions covered by a witness
- Warn: action `<name>` has no witness — add `val can<Name>Successfully = not(...)`

---

## C4 — `init` assigns every `var`

Run `init` in the REPL. Check that every declared `var` appears on the left side of an assignment in `init`.
- Pass: `init` returns `true` and all vars assigned
- Fail: `init` returns `false` or errors — quote the error
- Warn: `<var>` not assigned in `init`

---

## C5 — Every `var` updated in every action

For each action, check that every `var` appears on the left side of an assignment (`var' = ...`). Missing assignments cause implicit stuttering bugs.
- Pass: all vars updated in all actions
- Warn: `<var>` not assigned in action `<name>` — "Did you mean `<var>' = <var>` (stutter)?"

---

## C6 — `step` action exists and is complete

- Pass: a `step` action using `any { ... }` exists and includes all major actions
- Warn: no `step` — "Add a `step` action so the simulator and model checker can drive the system"
- Warn: action `<name>` exists but is not included in `step`

---

## R1 — Invariants hold at init

Evaluate each invariant `val` after `init` in the REPL.
- Pass: all return `true`
- Fail: invariant `<name>` returns `false` at init — "Either `init` is wrong or the invariant is too strong"

---

## R2 — Invariants hold after each action

For each action that can fire from the initial state, fire it and re-evaluate all invariants.
- Pass: all invariants hold after each action
- Fail: invariant `<name>` violated after action `<action>` — show the state at violation

---

## Report format

Print after all checks complete:

```
── Spec review: <filename> ──────────────────────────────────

C1  Patterns
  C1a  thin actions                  [✓ / ⚠ list actions with logic]
  C1b  enums over strings            [✓ / ⚠ list raw string literals]
  C1c  record grouping               [✓ / ⚠ list ungrouped vars]
  C1d  witnesses present             [✓ / ✗ none found]

C2  Abstraction level
  C2a  no string manipulation        [✓ / ⚠]
  C2b  message soup                  [✓ / ⚠ list queued messages]
  C2c  no implementation detail      [✓ / ⚠ describe what was found]

C3  Non-trivial properties
  C3a  invariants reference state    [✓ / ⚠ list tautologies]
  C3b  witnesses are falsifiable     [✓ / ⚠ list vacuous witnesses]
  C3c  protocol-level invariant      [✓ / ✗ none found]
  C3d  witnesses cover major actions [✓ / ⚠ list uncovered actions]

C4  init assigns all vars            [✓ / ✗ error]
C5  full var assignment per action   [✓ / ⚠ list gaps]
C6  step action exists               [✓ / ⚠ missing or incomplete]

R1  invariants hold at init          [✓ / ✗ list violations]
R2  invariants hold after actions    [✓ / ✗ <action> broke <invariant>]

── Top issues ─────────────────────────────────────────────
  1. <most important finding with a concrete suggestion>
  2. <second>
  3. <third>

── Suggested next steps ───────────────────────────────────
  1. Fix critical issues above
  2. Use `quint run` or the `quint` REPL to stress-test flagged scenarios
  3. Run `quint run --invariant <name> <spec_path>` to simulate
```

## After the report

Fix any **fail** checks immediately without asking.

For **warn** checks: present the list to the user and ask which ones to address (offer "All of the above" and "None — leave as-is"). Address only the ones the user selects.
