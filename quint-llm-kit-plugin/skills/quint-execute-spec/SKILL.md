---
name: quint-execute-spec
description: >
  Implement code against an existing Quint specification. Uses Research → Plan → Implement workflow
  (ACE-FCA style) grounded by the spec as the source of truth. Use when the user wants to refactor
  code, add a new feature, or close a gap between implementation and spec — with the Quint spec
  as the formal constraint that all changes must satisfy.
---

# Execute the Quint Specification

When you have a Quint spec and want to make a change to the codebase, this skill grounds the work
in the spec. The spec is not advisory — it is the formal statement of what the system must do.
All changes must satisfy it. The spec is reviewed, then the code follows.

## When to use this skill

- **Refactor**: restructure code while preserving behavior (spec stays fixed; code must still satisfy it)
- **New feature**: add functionality described by or consistent with the spec
- **Gap closure**: code has drifted from the spec; bring it back into alignment
- **Spec-first change**: update the spec first, then implement to satisfy it

If no spec exists yet, use `quint-modeling` first to create the grounding artifact.

---

## Core principle: spec is ground truth

This skill is the **post-spec** half of the loop: **Research** and **Plan** are anchored by the
existing `.qnt` file and compact gap analysis—not by prose plans alone. **Implement** proceeds only
with the **verification gates** in Phases 3–4 (Quint tool runs after substantive edits). Natural-language
plans are not proof; **tool results** are.

**Never modify the spec to make a failing verification pass.**
If the spec must change (behavior is intentionally changing), stop and present the proposed spec
change to the user before touching any code. The spec change is the highest-leverage review point.

Context utilization target: **40–60%** during research and planning. Catalog the codebase compactly
rather than reading everything into the main context.

---

## Workflow

```
[Quint spec] + [Desired change description]
         ↓
┌────────────────────────────────────────────────────────────┐
│ Phase 0: Orient                                             │
│   → Read the spec: what does it guarantee?                 │
│   → Clarify the change: what new behavior is needed?       │
│   → Decide: is this a spec change or a code change?        │
└────────────────────────────────────────────────────────────┘
         ↓
┌────────────────────────────────────────────────────────────┐
│ Phase 1: Research (compact)                                 │
│   → Map the gap between spec and code                      │
│   → Output: compact gap analysis (target: under 300 lines) │
└────────────────────────────────────────────────────────────┘
         ↓
┌────────────────────────────────────────────────────────────┐
│ Phase 2: Plan                                               │
│   → Precise steps: files to change, expected state delta   │
│   → For each step: how to verify it satisfies the spec     │
│   → Identify which Quint properties to run at each gate    │
│   → Present plan to user before implementing               │
└────────────────────────────────────────────────────────────┘
         ↓
┌────────────────────────────────────────────────────────────┐
│ Phase 3: Implement                                          │
│   → Follow plan phase by phase                             │
│   → After each phase: run Quint tools, verify properties   │
│   → Compact status back into the plan after each phase     │
└────────────────────────────────────────────────────────────┘
         ↓
┌────────────────────────────────────────────────────────────┐
│ Phase 4: Verify                                             │
│   → Run all witnesses (expect VIOLATED)                    │
│   → Run all invariants (expect no violation)               │
│   → If any invariant fails: return to Phase 2, fix plan    │
└────────────────────────────────────────────────────────────┘
```

---

## Phase 0: Orient

Read the spec and understand the desired change.

1. **Read the spec**. What does it model? What invariants does it assert? What witnesses does it have?
2. **Read the Spec Handoff section** (if present). Which source files does the spec correspond to?
3. **Clarify the change**. Ask the user:
   - What behavior is changing? (for refactors: nothing should change; for features: what is new?)
   - Should the spec change, or must the code satisfy the existing spec?
   - Is there an existing failing invariant, or is this forward-looking?

**Lightweight path** (skip research for simple changes):
If the change is small (single function, one module, no new state), skip Phase 1 and go straight
to Phase 2.

---

## Phase 1: Research (Compact)

For non-trivial changes, produce a compact gap analysis between spec and code. Keep this focused —
the goal is a compact, accurate summary, not a full codebase read. Answer these questions:

> Given the Quint spec at `[spec path]` and the source files `[file list from handoff]`:
>
> 1. For each state variable in the spec, find where it is managed in source code
> 2. For each action in the spec, find the corresponding function(s) in source code
> 3. Identify any spec behaviors that have no corresponding source code (gaps)
> 4. Identify any source code behaviors not captured in the spec (out-of-scope)
> 5. For the change `[change description]`: which source files are affected?
>
> Output a compact summary. Do not read files that are not relevant. Target: under 300 lines.

If the analysis missed something critical, do a targeted follow-up read before proceeding.

---

## Phase 2: Plan

Create a precise implementation plan. Each plan step must:

- Name the file and function to change
- Describe the expected state delta (what changes in the system's behavior)
- Specify the Quint property to run as a verification gate
- Be small enough to verify independently

### Plan format

```markdown
## Change: [one-sentence description]

### Spec impact
- Properties that must continue to hold: [list]
- Properties that will change (if any): [list] — REQUIRES USER APPROVAL BEFORE IMPLEMENTATION

### Implementation steps

#### Step 1: [file] — [what changes]
- Expected behavior change: [description]
- Quint verification gate: `quint run` / `quint verify` — invariant `[name]`

#### Step 2: [file] — [what changes]
...

### Rollback criteria
If invariant `[name]` fails after Step N, stop and return to planning. Do not proceed.
```

**Present the plan to the user before implementing.** Human review of the plan has higher leverage
than review of the code.

If the plan requires modifying the spec, present the spec change explicitly and get approval first.

---

## Phase 3: Implement

Follow the plan. After each step:

1. Run `quint typecheck` and fix all reported errors.
2. Run the step's verification gate (`quint run` / `quint test` / `quint verify`)
3. If the gate fails: stop, diagnose, return to Phase 2. Do NOT fix by loosening the spec.
4. Compact current status back into the plan file after each step. This keeps the context window
   lean for the next step.

### Context compaction pattern

After each step is verified, compact progress:

```markdown
## Status (after Step N)
- Steps 1–N: DONE ✓
- Current: Step N+1
- Blocking issues: [none / description]
- Next verification gate: [invariant name]
```

Write this to the plan file. In complex implementations, start a new context window with the
updated plan rather than continuing in an overloaded context.

### Quint tool usage during implementation

| Need | Tool |
|---|---|
| Type-check spec after any edit | Run `quint typecheck`; fix all reported errors before continuing |
| Verify witnesses are reachable | `quint run` with witness as invariant |
| Verify safety invariants hold | `quint run` with `--max-samples 5000` or `quint verify` |
| Interactive exploration | `quint REPL session` + `quint REPL eval` (only when CLI is insufficient) |

---

## Phase 4: Verify

Run the full property suite.

### Witnesses (liveness check)
All witnesses must be **violated** (meaning the expected state is reachable):
- Use ``quint run`` with witness name in `witnesses` (or mapped invariant selector).
- Expected result: witness reachability is reported (equivalent to `Counterexample found` in raw CLI wording).

### Safety invariants
All invariants must **not be violated**:
- Use ``quint run`` (or ``quint verify`` when stronger coverage needed).
- Expected result: no invariant violation reported.

### If a safety invariant is violated

1. Read the counterexample trace step by step
2. Identify which implementation step introduced the violation
3. Return to Phase 2 — fix the plan, not the spec
4. If the spec's invariant is genuinely wrong, present the proposed spec change to the user

### If a witness is satisfied (action is unreachable)

The implementation has over-constrained behavior — a path that should be reachable is blocked.
Return to Phase 2 and identify which step introduced the constraint.

---

## Spec change protocol

If the desired change requires updating the spec (new state variables, changed invariants):

1. **Draft the spec change** — show the diff to the user before any code changes
2. **Verify the updated spec in isolation** — typecheck, run witnesses, run invariants
3. **Get explicit approval** — do not proceed to code until the spec change is approved
4. Then implement the code to satisfy the updated spec

This preserves the spec as the source of truth even when it evolves.

---

## What NOT to do

| Anti-pattern | Why it breaks the workflow |
|---|---|
| Modify spec to pass a failing invariant | Destroys the spec as ground truth |
| Skip verification gates between steps | Breaks incremental verification; bugs compound |
| Read the whole codebase into main context | Floods context; catalog compactly in Phase 1 instead |
| Plan in prose, implement "roughly" | Plan must be precise enough to verify step-by-step |
| Treat spec as advisory documentation | Spec is a formal constraint — machine-checkable |
| Fix invariant failure by weakening the invariant | Invariants must be fixed in code, not loosened |

---

## Lightweight path for simple changes

For small, well-understood changes (single function, no new state):

1. Read the relevant spec module
2. Identify which invariant(s) cover the changed behavior
3. Make the change
4. Run `quint run` with those invariants
5. Done

Skip Phase 0–1. Use Phases 2–4 only for non-trivial changes.
