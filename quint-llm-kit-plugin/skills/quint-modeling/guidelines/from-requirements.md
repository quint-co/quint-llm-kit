# From requirements — written specification

The user has a written requirements or functional-spec document (prose, user stories, a design
doc) and wants it modelled in Quint. Intake here is **reading and structuring**: you extract the
model from the document rather than interviewing for it. After intake, follow the shared spine
(Steps 1–7) in `../SKILL.md`.

This is the non-interactive sibling of `from-nothing`: the same target understanding (entities,
operations, properties, system model), but sourced from a document instead of a conversation.
The interaction is *targeted* — you ask the user only where the document is silent or ambiguous
on something that changes the spec.

## Extract from the document

Read the document and produce, in English, the same understanding the spine builds on:

1. **Entities & state** — what the system tracks and what each entity remembers. → spine Step 2.
2. **System model** — fill the spine's **assumptions checklist** (Step 1): participants, failure
   model, communication, time. Requirements docs frequently leave these *implicit* — list what
   the document states explicitly and flag what it omits (see below).
3. **Operations** — every operation the document describes, with its precondition and effect.
   → spine Step 3 pure functions.
4. **Properties** — the document's stated guarantees become invariants; "the system can reach X"
   statements become witnesses. → spine Step 5.

A table is often the cleanest intake artifact:

| Requirement (quote/§) | Entity / operation / property | Maps to |
|---|---|---|
| "a transfer must not overdraw" | invariant: no negative balance | spine Step 5 |
| "any node may propose" | operation `propose(node)` | spine Step 3 |

Linking each modelling decision back to a line in the document keeps the spec traceable and makes
the handoff's "what it covers" trivial to write.

## Resolve gaps before modelling, not by guessing

Requirements docs are written for humans and routinely omit what a formal model must pin down —
exact failure semantics, ordering, what happens on a precondition violation, how many
participants. **Where the document is silent on something that changes state shape or action
semantics, ask one targeted question** rather than inventing a default. Record the answer (and
that it was a gap) so the handoff can note it. Where the document is silent on something
*immaterial* to any property you care about, omit it — that's the "what, not how" rule from the
spine.

## Then follow the spine

With the understanding extracted, proceed through the spine: separate concerns, shape the state,
write pure functions, wire thin actions, add witnesses then invariants, compose `step`, simulate.
Build incrementally and get approval on the type sketch (spine Step 2) before writing logic.

## Handoff

The spine's Step 7 handoff, with a requirements-specific addition: a **coverage map** linking each
modelled operation/property back to the requirement it came from, and an explicit list of
requirements *not* modelled (and why). The gaps you had to ask about belong in the "what it does
NOT cover" / assumptions note.
