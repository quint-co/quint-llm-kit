---
name: design-verification-framing
description: >
  Property and simulation framing for Quint workflows. Use this whenever defining invariants,
  witnesses, and temporal expectations, scoring property impact, or explaining simulation outcomes
  in user language tied to requirements.
---
# Design Verification Framing

Use this skill when selecting properties and presenting simulation/verification results.

## Goal

Ensure properties are meaningful for the user's intent and results are explained clearly — **without
overstating what random simulation proves**.

## Property selection flow

- Start with the core behavior the user cares about.
- Draft candidate properties in this order:
  1. safety guarantees (invariants),
  2. reachability goals (witnesses),
  3. sequence/progress expectations (temporal).
- Validate each property in plain English before running tools.

## Impact scoring guidance

Score each property with requirement alignment:

- **High**: directly validates the requested change.
- **Medium**: validates a supporting path or edge condition.
- **Low**: broad safety checks not specific to this request.

Always include a one-line rationale tied to requirement text.

## Language & confidence (MANDATORY for simulation results)

Simulation is **bounded random sampling** of the state space — it is **not a proof**. Your job is to
report what the samples showed and hand the judgement call to the user. The user decides whether the
coverage is enough.

### Stance

- Be factual and suspicious by default. Do not volunteer confidence.
- Never claim a property is "proven", "confirmed", "verified", "correct", or "safe" from simulation.
- Never say "we can be confident", "everything works", "the spec is fine", or similar reassurance.
- Do not editorialize on whether the number of samples is "enough" — that is the user's call.
- Invite further exploration rather than declaring completion.

### Phrasing rules

Replace confident phrasings with neutral, sampling-accurate ones:

| Avoid | Use instead |
|---|---|
| "The rule holds." | "No counterexample was found in this run." |
| "Confirmed / proven / verified by simulation." | "No counterexample observed across N sampled runs." |
| "The behavior works." | "The target state was reached in this run." |
| "Safe / correct." | "No violation observed in the runs executed." |
| "I ran 200 samples, so we can be confident." | "200 runs sampled; 0 counterexamples observed. Sampling is not exhaustive." |
| "Everything passed." | "All listed properties returned no counterexamples in these runs." |

### Coverage must be reported as facts, not evidence

When reporting a simulation run, state the **coverage** explicitly and as plain facts:

- number of samples / runs,
- max steps per run,
- seed (if set),
- `--init` / `--step` if non-default.

Do not attach adjectives like "thorough", "sufficient", "comprehensive" to coverage numbers.

### Always invite exploration

After presenting results, remind the user that simulation is sampling and offer concrete next steps
(examples, not all required):

- run more samples / a different seed,
- try `quint verify` for bounded exhaustive checking,
- step through the spec interactively in the `quint` REPL (`quint -r spec.qnt::ModuleName`),
- add or tighten properties.

Frame this as **the user's decision**, not an agent recommendation.

## Result interpretation guardrails

- Explain outcomes in plain English first, then show raw output if needed.
- Keep witness semantics explicit (neutral wording):
  - **Invariant, VIOLATED** → bug: the rule was broken in this run.
  - **Invariant, no violation** → no counterexample found in this run (not a proof the rule holds).
  - **Witness, VIOLATED / trace found** → the target state was reached in this run (good for reachability).
  - **Witness, no trace** → the target state was not reached in this run; may indicate over-constraint, but could also just mean sampling missed it.
- For failures, describe:
  - what was tested,
  - what failed,
  - why that matters to the requested behavior.

## Anti-patterns

- Do not present raw tool output without interpretation.
- Do not score impact without linking back to requirements.
- Do not treat simulation as proof of correctness.
- Do not use confident verbs ("confirmed", "proven", "verified", "guaranteed") for simulation results.
- Do not make quality judgements on behalf of the user ("this is enough coverage", "the spec looks good").
