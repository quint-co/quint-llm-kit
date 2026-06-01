---
name: design-model-building-blocks
description: >
  Build Quint-ready model structure from requirements in plain English. Use this whenever the agent
  is translating requirements into the spec skeleton: what the system remembers, what can happen,
  who can act, and what can fail. Helps derive actions, guards, and state transitions before coding.
---
# Design Model Building Blocks

Use this skill when turning confirmed requirements into a Quint model.

## Goal

Produce a coherent model blueprint that is easy to typecheck and easy to validate.

## Decomposition order

1. **What the system remembers** (state and identities).
2. **Who can act** (single actor, multi-actor, coordinator patterns).
3. **What can happen** (operations as actions with clear preconditions).
4. **What can fail** (partial failure, reordering, retries, dropped messages).

## Action-shaping heuristics

- Keep each action narrow and explicit.
- For each action, define:
  - trigger/context,
  - precondition,
  - state updates,
  - expected effect visible to users.
- Surface forks early if two plausible interpretations imply different state or actions.

## Ambiguity policy

If a modeling fork changes the state shape or action semantics:

- pause construction,
- ask one targeted question describing the fork and consequence,
- resume only after user choice.

## Anti-patterns

- Do not hide major assumptions in defaults.
- Do not merge unrelated concerns into a single action.
- Do not proceed past unresolved forks that alter behavior.
