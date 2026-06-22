# Quint CLI Reference

## Contents

- [Installation](#installation)
- [Commands Overview](#commands-overview)
- [`quint run` — Simulation](#quint-run--simulation)
- [`quint test` — Deterministic Tests](#quint-test--deterministic-tests)
- [`quint verify` — Model Checking](#quint-verify--model-checking)
- [`quint typecheck`](#quint-typecheck)
- [Reading Output](#reading-output)
- [Verbosity Guide](#verbosity-guide)

## Installation

```bash
npm i @informalsystems/quint -g
```

---

## Commands Overview

| Command | Purpose |
|---|---|
| `quint` | Start REPL |
| `quint run` | Random simulation — find invariant violations fast |
| `quint test` | Run deterministic `run` tests |
| `quint verify` | Exhaustive verification via Apalache (bounded model checking) |
| `quint typecheck` | Type-check without running |
| `quint parse` | Parse and resolve imports only |
| `quint compile` | Compile to TLA+ or JSON IR |

---

## `quint run` — Simulation

Randomly walks the state space. Finds obvious violations in seconds.

```bash
quint run spec.qnt \
  --main MyModule \
  --invariant myInvariant \
  --max-steps 100 \
  --max-samples 1000
```

### Key flags

| Flag | Default | Effect |
|---|---|---|
| `--main` | filename | Module to use |
| `--invariant` | `true` | Invariant name or expression to check |
| `--invariants` | `[]` | Space-separated list of invariant names (all checked with AND) |
| `--witnesses` | `[]` | Space-separated list of witnesses to report on |
| `--max-steps` | 20 | Max steps per trace |
| `--init` | `init` | Name of the init action in the module |
| `--step` | `step` | Name of the step action in the module |
| `--max-samples` | 10000 | Max number of runs before giving up |
| `--seed` | random | Seed for reproducibility |
| `--verbosity` | 2 | Output detail: 1=minimal, 2=action names, 3=state changes, 4=full dumps |
| `--hide` | `[]` | Variable names to hide from terminal output |
| `--out-itf` | — | Write traces in Informal Trace Format (for ITF Viewer) |
| `--mbt` | false | Emit `mbt::actionTaken` and `mbt::nondetPicks` metadata for MBT |

### Reading output

| Output | Meaning |
|---|---|
| `"An example execution"` | Invariant violated — counterexample found |
| `"No violation found"` | Invariant held across all sampled traces |
| `"An example execution"` for a **witness** | Witness violated — state is reachable ✅ |
| `"No trace found"` for a **witness** | Witness never violated — state may be unreachable ⚠️ |

### Verbosity guide

| Level | Shows | When to use |
|---|---|---|
| 1 | Pass/fail only | Bulk runs |
| 2 | Action names | Quick trace understanding |
| 3 | State changes + `nondet` picks | Debugging failures |
| 4 | Full state dumps | Deep debugging |

### Notifying the user about non-default actions

After calling `quint run` or `quint verify`, if a
non-default `init` or `step` was passed, always include a brief confirmation in your
reply, for example:

> Ran with `--init customInit --step myStep`.

If both are omitted (using Quint defaults), no confirmation line is needed.

### Reproducing a run

```bash
# Capture the seed from a violation, then replay
quint run spec.qnt --invariant myInv --seed 12345 --verbosity 3
```

---

## `quint test` — Deterministic Tests

Runs all `run` definitions in the spec (or a filtered subset).

```bash
quint test spec.qnt --main MyModule --match testName
```

### Key flags

| Flag | Default | Effect |
|---|---|---|
| `--main` | filename | Module to use |
| `--match` | all | String or regex to filter test names |
| `--max-samples` | 10000 | Max runs for randomized tests |
| `--seed` | random | Seed for reproducibility |
| `--verbosity` | 2 | Output detail level |

### Reading output

```
[PASS] basicTest
[FAIL] transferTest
```

A `[FAIL]` shows which `.expect()` failed and the state at failure.

---

## `quint verify` — Apalache (Exhaustive)

Checks invariants across **all** reachable states up to `--max-steps`. Requires Java (OpenJDK).

```bash
quint verify spec.qnt \
  --main MyModule \
  --invariant myInvariant \
  --max-steps 10
```

Quint automatically downloads and starts Apalache. To use a running Apalache server:

```bash
apalache-mc server   # start Apalache server
quint verify spec.qnt --server-endpoint localhost:8822 --invariant myInv
```

### Key flags

| Flag | Default | Effect |
|---|---|---|
| `--main` | filename | Module to use |
| `--invariant` | — | Invariants to check (comma-separated) |
| `--init` | `init` | Name of the init action in the module |
| `--step` | `step` | Name of the step action in the module |
| `--inductive-invariant` | — | Inductive invariant (checked in 2–3 Apalache calls) |
| `--temporal` | — | Temporal properties to check |
| `--max-steps` | 10 | Bound on trace length |
| `--random-transitions` | false | Symbolic simulation instead of full exploration |
| `--out-itf` | — | Write counterexample trace to ITF file |

### When to use verify vs run

| Tool | Coverage | Cost | Use when |
|---|---|---|---|
| `quint run` | Sampled | Seconds | Early design, quick sanity check |
| `quint verify` | All states up to bound | Minutes–hours | Final confirmation, critical invariants |

---

## REPL

```bash
quint                           # start blank REPL
quint -r spec.qnt::ModuleName  # load file and import module
```

### REPL commands

| Command | Effect |
|---|---|
| `.load spec.qnt` | Load (or reload) a file |
| `.clear` | Reset all session state |
| `.save kettle.qnt` | Save session to file |
| `.exit` | Exit REPL |
| `:type expr` | Show inferred type of expression |

### REPL workflow

```
>>> init              // apply init action (returns true if succeeded)
>>> step              // take one random step
>>> myInvariant       // evaluate an invariant in the current state
>>> myPureFunc(arg)   // call any pure def
>>> :type balances    // inspect type
```

Force a specific state with an anonymous action:

```quint
>>> all { balances' = Set("alice").mapBy(_ => 999), phase' = "ready" }
true
>>> balances
Map("alice" -> 999)
```

---

## Common Patterns

### Check a witness (reachability)

```bash
# Witness should be VIOLATED — violation means the state IS reachable
quint run spec.qnt --invariant canDecideSuccessfully --max-steps 100
```

### Check a safety invariant

```bash
# Invariant should be SATISFIED — violation means a bug
quint run spec.qnt --invariant noNegativeBalances --max-samples 5000
```

### Run a specific test

```bash
quint test specTest.qnt --main specTest --match happyPath
```

### Generate an ITF trace for the viewer

```bash
quint run spec.qnt --invariant myWitness --out-itf trace_{seq}.itf.json
```
