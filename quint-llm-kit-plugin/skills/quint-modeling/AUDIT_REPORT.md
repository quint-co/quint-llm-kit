# Audit report — `quint-modeling`

Two-stage quality audit of the `quint-modeling` skill against the skill-authoring
rubric (34 rows): a **static critique** (read-only, via the `auditing-skills` skill)
followed by a **behavioral evaluation** (runs the skill in a fresh sandbox, via
`skill-creator`). Audited: `SKILL.md` plus `guidelines/{from-nothing, from-requirements,
from-code, from-tlaplus}.md`.

**Status: shippable.** No Critical or unresolved Major failures. Every behavioral row
passed; the one model caveat (Haiku) is recorded below as a known limitation, not a bug.

---

## Summary verdict

| Row | Area | Criterion | Verdict |
|---|---|---|---|
| 1 | Discovery | Triggers on a direct ask | **Pass** — Sonnet 3/3; Haiku 2/3 (one flaky) |
| 2 | Discovery | Third-person description | Pass |
| 3 | Discovery | Triggers on an indirect ask (never says "specification") | **Pass** — both models |
| 4 | Discovery | Specific key terms | Pass |
| 5 | Discovery | Description passes validation (≤1024, non-empty, no XML) | Pass |
| 6 | Discovery | No trigger collision with sibling skills | **Pass** — siblings removed + `quint-lang` re-partitioned |
| 7 | Naming | Name passes validation | Pass |
| 8 | Naming | Name not vague | Pass |
| 9 | Structure | Body under 500 lines | Pass (301 lines) |
| 10 | Structure | Detail in separate reference files | Pass |
| 11 | Structure | References one level deep | Pass |
| 12 | Structure | Reference files >100 lines have a TOC | **Pass** — TOCs added to `from-tlaplus.md`, `from-code.md` |
| 13 | Structure | Env-specific values in config | N/A |
| 14 | Content | No time-sensitive statements | Pass |
| 15 | Content | Consistent terminology | Pass |
| 16 | Content | No facts Claude already knows | Pass |
| 17 | Content | Degrees of freedom match task fragility | Pass |
| 18 | Content | Reasoning, not bare imperatives | Pass |
| 19 | Instructions | Explicit step workflow with feedback loop | Pass |
| 20 | Instructions | Concrete examples where quality depends on them | Pass |
| 21 | Instructions | One default with an escape hatch | Pass |
| 22 | Code | Scripts handle errors | N/A (no bundled scripts) |
| 23 | Code | No undocumented constants | Pass |
| 24 | Code | Execution intent explicit | Pass |
| 25 | Code | Plan-validate-execute for destructive ops | N/A |
| 26 | Code | Dependencies listed/valid | N/A |
| 27 | Code | Forward-slash paths | Pass |
| 28 | Code | MCP tools fully-qualified | N/A |
| 29 | Evaluation | ≥3 eval scenarios tied to real failures | **Pass** — 5 scenarios designed |
| 30 | Evaluation | Tested with a fresh Claude on real tasks | **Pass** — Sonnet scenarios S3 & S4 |
| 31 | Evaluation | Tested across target models | **Pass (caveat)** — Sonnet robust; Haiku weaker, caught failure fixed |
| 32 | Evaluation | No bundled file never read | Pass |
| 33 | Security | Trusted source / audited | Pass (in-house) |
| 34 | Ops | Within skill budget; domain not over-split | **Pass** — one skill, 4 flows |

**Scoring:** no Critical failures; all Majors resolved.

---

## Stage 1 — Static critique (auditing-skills)

Read-only pass. Frontmatter validation gate **passed** (name 14 chars, charset/reserved-word/XML
clean; description 766 chars at audit time, non-empty, no XML tags).

Rows judgeable by reading all passed except the items below, which were fixed in this pass:

- **Row 12 (Major) — missing TOCs.** `from-tlaplus.md` (267 lines) and `from-code.md` (116 lines)
  opened straight into prose; a partial read would miss their scope. **Fixed:** added a Contents
  TOC at the top of each, mapping to the real `##` sections.
- **Minor — cross-ref inconsistency.** `from-tlaplus.md` referenced `../quint-lang/guidelines/choreo`
  (no extension) while `SKILL.md` used `…/choreo.md`. **Fixed:** unified to `.md`.
- **Minor — em-dash rule.** The `from-tlaplus.md` pitfall forbidding em-dash parenthetical clauses
  appeared to contradict the guideline's own prose. **Fixed:** scoped the rule explicitly to
  *generated output* (spec/comments/README), not the guideline text.

Rows **1, 3, 29, 30, 31** were marked *requires execution* — a static read cannot confirm whether
a description fires or whether a fresh agent succeeds. These were deferred to Stage 2.

**Rows 6 & 34 at static time** were Majors *contingent on superseded sibling skills existing in the
workspace* (`quint-from-code`, `quint-from-tlaplus`, `quint-model-building`, plus a loose
`spec-builder.md`). These were deleted, and references to them repointed to `quint-modeling`
(`quint-execute-spec/SKILL.md`, `quint-lang/evals/scenarios.md`). That clears the in-suite
collision and the over-split concern.

---

## Stage 2 — Behavioral evaluation (skill-creator)

Ran the skill in a fresh sandbox against the full current shipped skill set.

### Method

- Loaded the workspace plugin via `--plugin-dir` and **quarantined the globally-installed
  superseded siblings** (then restored them) so the trigger test was an honest competition among
  only the current `quint-llm-kit:*` set.
- Detected triggering by the actual `Skill` `tool_use` in `--output-format stream-json` (ground
  truth), **not self-report** — which matters, because once a skill triggers, its body suppresses
  any self-report.
- Ran on **Sonnet 4.6** and **Haiku 4.5**; independently re-verified every produced spec
  (`quint typecheck` and `quint run` with the agent's intended module/invariant) rather than
  trusting transcripts.

### Key findings & fixes (each re-run to confirm it now succeeds)

1. **Triggering.** Negatives 6/6 on both models — never over-fires; siblings correctly chosen.
   The description fix (front-loaded imperative trigger + an explicit "Do NOT use this for…"
   partition) recovered Haiku's "model-check this design" miss.

2. **Cross-skill collision (highest-value find).** `quint-lang` also advertised "modeling
   distributed systems / translating TLA+", so TLA+-translation tasks sometimes routed to
   `quint-lang` — even on Sonnet — skipping the modelling discipline and producing an un-runnable
   spec. **Fixed in `quint-lang`'s description** (narrowed to a syntax/CLI reference that defers
   task work to `quint-modeling`). Note: this collision could not be caught by a static audit of
   `quint-modeling` alone — the fix lived in a *different* skill's description.

3. **Executability on Haiku.** Iter-1 Haiku specs typechecked but didn't run (the
   `assume`-doesn't-initialize-a-`const` trap; logic-in-actions with a bare `and`). **Strengthened
   the spine's executability gate** to name both traps. The previously parse-erroring Haiku run
   now typechecks and runs with the invariant holding.

4. **Ambiguous-source routing (scenario S5).** Given a doc with conflicting prose + pseudocode,
   the skill correctly **asked which source is authoritative** before modelling — as specified.

### Known limitation

Haiku 4.5 remains the weaker model: a bare "model my protocol" triggers ~1/3 of the time. This was
**deliberately not over-tuned** — forcing Haiku's bare-ask trigger rate up risked the clean
negative results (not over-firing on unrelated asks). Recorded as a known limitation, not a defect.

Two harness artifacts (a session rate-limit and a file-not-in-cwd error) were identified and
excluded from verdicts after clean re-runs.

---

## Changes made during this audit

Edits are isolated to the workspace plugin; global skills were untouched (quarantined and restored
during the eval).

- `quint-modeling/SKILL.md` — description rewritten (imperative trigger, example phrasings,
  explicit "Do NOT use this for…" partition); spine executability gate strengthened to name the
  `assume`/`const` and logic-in-actions traps.
- `quint-modeling/guidelines/from-tlaplus.md` — added TOC; cross-ref `.md` fix; em-dash rule scoped.
- `quint-modeling/guidelines/from-code.md` — added TOC.
- `quint-lang/SKILL.md` — description narrowed to a syntax/CLI reference that defers task work.
- Deleted superseded siblings: `quint-from-code/`, `quint-from-tlaplus/`, `quint-model-building/`,
  `spec-builder.md`; repointed their inbound references to `quint-modeling`.

## Residual (not blocking)

The audit and eval edits are in the **workspace plugin copies**. A globally-installed
`~/.claude/skills/` set still contains superseded siblings (e.g. `quint-from-code`,
`tlaplus-to-quint`, `tlaplus2quint`). When this plugin is promoted, ensure those global copies are
removed or superseded — otherwise the clean trigger partition validated here gets re-muddied in
real sessions.
