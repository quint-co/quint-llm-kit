# Writing and Debugging Tests

## Contents

- [File Structure](#file-structure)
- [Writing Tests](#writing-tests)
- [Running Tests](#running-tests)
- [Debugging Failures](#debugging-failures)
- [REPL-First Debugging](#repl-first-debugging)

## File Structure

Tests live in a separate file that imports the main spec. The main spec has no `run` definitions.

```quint
// system.qnt — spec only, no tests
module system {
  // ... vars, actions, invariants ...
}

// systemTest.qnt — tests only
module systemTest {
  import system.* from "./system"

  run basicTest = {
    init
      .then(transfer("alice", "bob", 50))
      .expect(balances.get("alice") == INITIAL_BALANCE - 50)
  }
}
```

Run with:
```bash
quint test systemTest.qnt --main systemTest --match basicTest
```

---

## Writing Tests

### Basic pattern

```quint
run happyPath =
  init
    .then(action1(args))
    .expect(condition1)
    .then(action2(args))
    .expect(condition2)
```

### Operators

| Operator | Meaning |
|---|---|
| `a.then(b)` | Execute `a`, then execute `b` from resulting state |
| `a.expect(p)` | Execute `a`, fail if `p` is false in resulting state |
| `n.reps(i => A)` | Execute action `A` n times; iteration index passed as `i` |
| `a.fail()` | Asserts `a` evaluates to false (action should be blocked) |
| `assert(p)` | Does not change state; fails if `p` is false |

### Repeat an action N times

```quint
run threeVotes =
  init
    .then(3.reps(i => vote(i)))
    .expect(votes.size() == 3)
```

### Negative test — assert an action is blocked

```quint
run cannotDoubleVote =
  init
    .then(vote("alice"))
    .then(vote("alice").fail())   // second vote must fail
```

### Assert mid-trace

An `assert` must sit inside an `all { }` block that also assigns the state
variables. A standalone `.then(assert(...))` step assigns nothing, so its effect
cannot unify with the rest of the trace and the test fails to typecheck. For an
after-the-fact check, use `.expect(...)` instead of a trailing assert step.

```quint
run checkTiming =
  init
    .then(all { vote(1), assert(votes.size() == 0) })  // assert BEFORE vote executes
    .expect(votes.size() == 1)                          // assert AFTER
```

### Nondeterministic tests

```quint
run nondetTest = {
  nondet amount = 50.to(300).oneOf()
  nondet user   = USERS.oneOf()
  init
    .then(transfer(user, "treasury", amount))
    .expect(balances.get(user) >= 0)
}
```

Multiple `nondet` bindings explore combinations. Use `--seed` to reproduce a specific run.

---

## Running Tests

```bash
# Run a specific test
quint test systemTest.qnt --main systemTest --match basicTest

# Run all tests matching a pattern
quint test systemTest.qnt --main systemTest --match ".*"

# Run with detailed trace output
quint test systemTest.qnt --main systemTest --match basicTest --verbosity 3

# Reproduce a failure with a seed
quint test systemTest.qnt --main systemTest --match basicTest --seed 0x1a2b3c
```

---

## Debugging Failures

### Critical: error location ≠ failure point

Quint reports errors at the **start** of the test chain (`init`), not where `.expect()` actually failed.

```quint
run myTest = {
  init                              // ← error reported HERE (e.g. line 42)
    .then(action1)
    .then(action2)
    .expect(some_condition)         // ← actual failure HERE
    .then(action3)
    .expect(another_condition)      // ← or here
}
```

```
error: [QNT508] Expect condition does not hold true
42:     init
```

The line number in the error points to `init`, not the failing `.expect()`. Always use `--verbosity 3` to find the real failure.

### Step 1: Run with verbosity 3

```bash
quint test systemTest.qnt --main systemTest --match myTest --verbosity 3
```

Output shows frames:
```
[Frame 0] init => true
[Frame 1] action1 => true
[Frame 2] action2 => true
[Frame 3] action3 => true
# Fails here — no Frame 4

Frame 3 state:
  balance: 0
  votes: Set()
```

### Step 2: Map frames to test code

```quint
run myTest = {
  init                    // Frame 0
    .then(action1)        // Frame 1
    .then(action2)        // Frame 2
    .expect(cond1)        // checked after Frame 2
    .then(action3)        // Frame 3
    .expect(cond2)        // checked after Frame 3 ← FAILS HERE
}
```

If the trace stops after Frame 3 and no Frame 4 appears, the `.expect()` after Frame 3 failed.

### Step 3: Compare actual vs expected

From the frame output, read the actual state values. Compare against what each `.expect()` requires.

### Step 4: Classify the bug

| Symptom | Type | Fix |
|---|---|---|
| Action doesn't update the field being checked | Spec bug | Fix the action's state update |
| `.expect()` checks a field before the action that sets it | Test bug | Move the `.expect()` later in the chain |
| `.expect()` uses wrong value | Test bug | Correct the expected value |
| Action sets a wrong value | Spec bug | Fix the pure function logic |

### Common mistakes

```quint
// ❌ Checking state before it's set
run bad =
  init
    .then(all { action1, assert(result == 42) })  // assert runs BEFORE action1 updates state

// ✅ Check after
run good =
  init
    .then(action1)
    .expect(result == 42)

// ❌ Forgetting action order matters
run bad =
  init
    .then(approve(100))
    .expect(balance == INITIAL - 100)   // approve doesn't deduct — transfer does

// ✅ Complete the sequence
run good =
  init
    .then(approve(100))
    .then(transfer(100))
    .expect(balance == INITIAL - 100)
```

---

## REPL-First Debugging

Before writing a failing test, isolate the problem in the REPL:

```bash
# Load the spec and test interactively
quint -r system.qnt::system

# Force a specific state with an anonymous action
>>> all { balances' = Set("alice").mapBy(_ => 100), phase' = "ready" }
true
>>> transfer("alice", "bob", 50)
true
>>> balances.get("alice")
50
```

If the REPL shows wrong output, the spec has a bug. If the REPL shows the right output but the test fails, the test chain has a sequencing error.
