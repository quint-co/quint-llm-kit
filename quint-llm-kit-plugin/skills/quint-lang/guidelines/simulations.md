# Verification — Witnesses, Invariants, and Test Interpretation

## Contents

- [Critical Distinction](#critical-distinction)
- [Witnesses (Liveness — Protocol Makes Progress)](#witnesses-liveness--protocol-makes-progress)
- [Invariants (Safety — Properties Hold)](#invariants-safety--properties-hold)
- [Trace Analysis](#trace-analysis)
- [Result Classification](#result-classification)

## Critical Distinction

Witnesses and invariants are **opposite** in what a good result means:

| Check type | VIOLATED means | SATISFIED means |
|---|---|---|
| **Witness** | ✅ State IS reachable — spec works | ⚠️ State is UNREACHABLE — over-constrained or bug |
| **Invariant** | ❌ Safety is broken — critical bug | ✅ Safety holds in all explored states |

Never confuse the two. A violated witness is success. A violated invariant is a bug.

---

## Witnesses (Liveness — Protocol Makes Progress)

### Syntax

Write a witness as `not(target_state)`. Violation means `target` was reached.

```quint
// Witness: can a transfer succeed?
val canTransferSuccessfully: bool =
  not(lastActionSuccess and balances.get("alice") < INITIAL_BALANCE)

// Pattern: state change evidence
val canWithdrawSuccessfully: bool =
  not(users.exists(u => balances.get(u) > INITIAL_BALANCE))

// Pattern: multi-condition
val canCompleteFullCycle: bool = not(and {
  delegations.size() == 0,
  users.forall(u => rewards.get(u) == 0),
  users.exists(u => balances.get(u) > INITIAL_BALANCE),
})
```

Add one witness per major action. If a witness is always satisfied, the action has an over-constrained precondition or a bug.

### Running witnesses

```bash
quint run spec.qnt \
  --main MyModule \
  --invariant canTransferSuccessfully \
  --max-steps 100 \
  --max-samples 1000
```

### Result interpretation

| Output | Meaning | Action |
|---|---|---|
| `"An example execution"` | VIOLATED ✅ | Record seed, state is reachable |
| `"No trace found"` | SATISFIED ⚠️ | Try more steps — see progressive increase below |

### Progressive increase for SATISFIED witnesses

Do not conclude a state is unreachable after one run. Increase steps first:

```bash
quint run spec.qnt --invariant myWitness --max-steps 100
quint run spec.qnt --invariant myWitness --max-steps 200
quint run spec.qnt --invariant myWitness --max-steps 500
```

If still SATISFIED after 500 steps, run with `--verbosity 3` to inspect execution, then diagnose:

| Symptom | Root cause | Fix |
|---|---|---|
| No actions execute | Protocol stuck at init | Fix `init` or witness precondition |
| Same action loops | Liveness bug or over-constrained guard | Relax action guard |
| Actions run but never reach witness | Witness condition too strong | Weaken the witness |
| Actions run, witness never reached | Real reachability bug in spec | Investigate spec logic |

### Witness as a `run` (alternative form)

```quint
// @witness
run decisionIsReachable =
  init
    .then(3.reps(i => vote(i)))
    .expect(decided == true)
```

Use invariant-style witnesses for nondeterministic exploration; run-style witnesses for documenting known reachable paths.

---

## Invariants (Safety — Properties Hold)

### Running invariants

```bash
quint run spec.qnt \
  --main MyModule \
  --invariant noNegativeBalances \
  --max-steps 200 \
  --max-samples 5000
```

### Result interpretation

| Output | Meaning | Action |
|---|---|---|
| `"No violation found"` | SATISFIED ✅ | Safety holds across all sampled traces |
| `"An example execution"` | VIOLATED ❌ | Bug — capture seed and analyze trace |

### Bug protocol: invariant violated

**Step 1 — Capture details**
```bash
# Re-run with the seed from the violation output
quint run spec.qnt --invariant myInv --seed <seed> --verbosity 3 --main MyModule
```

**Step 2 — Analyze trace**
- Find the step N where the invariant became false
- Find the action that caused the transition to step N
- Extract the relevant state snapshot: which variables changed, what values

**Step 3 — Determine root cause**

| Scenario | Root cause | Fix |
|---|---|---|
| Invariant violated at step 0 | `init` produces invalid state | Fix `init` |
| Invariant holds at init, fails after action X | Action X has wrong guard or wrong update | Fix action X |
| Invariant seems too strict | Invariant itself is wrong | Weaken invariant |


## Trace Analysis

Use `--verbosity 3` whenever you need to understand a failure or a never-violated witness.

```bash
quint run spec.qnt --invariant myInv --seed <seed> --verbosity 3 --max-steps 50
```

### Verbosity levels

| Level | Shows | When to use |
|---|---|---|
| 1 | Pass/fail only | Bulk runs |
| 2 | Action names | Quick trace understanding |
| 3 | State changes + `nondet` picks | Debugging failures |
| 4 | Full state dumps | Deep debugging of complex state |

### Analysis steps

1. Scan for repeated actions — signal of a stuck loop
2. Find the critical transition: step where invariant violated or witness should have fired
3. Read state before and after that step — what changed?
4. Trace backwards: which actions led here, what nondeterministic picks were made

---

## Result Classification

After running all checks:

| Overall status | Condition |
|---|---|
| Success | All witnesses violated, all invariants satisfied, all tests pass |
| Liveness concern | One or more witnesses never violated after 500+ steps |
| Safety Concern | Any invariant violated |
