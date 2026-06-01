---
name: spec-plain-english-explanation
description: >
  Plain-English walkthrough of a Quint spec for engineers unfamiliar with formal methods:
  what it models, state, transitions, properties, and explicit non-goals. Parameter: spec file path
  (read the file and then explain following this structure).
---

# Spec plain-English explanation

Apply when explaining a Quint spec at **`<spec_path>`**. Read the spec at that path, then structure
the explanation as follows for an engineer unfamiliar with formal methods:

## What this models

2–3 sentences on the system/component being specified.

## State

For each `var`: what it represents, what values it can take, what it means for the real system.

## Transitions

For each `action`: when it fires, what it changes, what it guarantees.

## Properties

For each invariant or temporal property: what correctness condition it captures and why it matters.

## What the spec does NOT model

Call out explicit abstractions and simplifications — what was left out and why.
