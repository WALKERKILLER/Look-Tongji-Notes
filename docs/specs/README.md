# Specs

A spec is the stable contract between intent and implementation. It says what observable result must hold and how completion is proven. It is not an implementation diary: a plan says how to edit the code, while a decision record preserves why one meaningful option beat another.

## When a spec is required

Write and obtain human approval for a spec before implementation when a change affects public or model-visible behavior, a cross-module contract, data or security boundaries, a migration, or work that must survive a person/agent/session handoff. Routine documentation fixes, mechanical refactors, and local bugs already defined by a failing regression test do not require one.

## Lifecycle

- **Draft** — proposed; under discussion. File name: `draft-<title>.md`.
- **Approved** — reviewed and accepted; implementation may start. Rename to `<NNNN>-<title>.md` (sequential).
- **Implemented** — shipped; the spec describes what exists.
- **Superseded** — replaced by a newer numbered spec; keep both and link the new one from `Status:`.

## Template

```markdown
# <Title>

Artifact-Version: 1
Status: Draft

## Intent
Problem, desired outcome, scope, non-goals, and constraints.

## Contract
Observable behavior, inputs, outputs, errors, side effects, and compatibility.

## Plan
Implementation seams and ordering. Keep this brief; volatile execution detail can stay in the working plan.

## Verification
Commands and acceptance scenarios that prove the contract.

## Evidence
Pending until implementation. Implemented specs link permanent repository tests, gates, screenshots, or other durable proof.
```

## Rules

- An agent may draft a spec, but a human changes it to Approved.
- Draft files use `draft-<title>.md`; approved records use sequential `NNNN-<title>.md` names.
- Implemented specs contain at least one relative repository link in Evidence.
- Existing external requirements may remain the source of truth; set the Spec capability state to `external`, register the stable source link, and do not create a parallel contract.
- Keep one spec under roughly 200 lines; split independent contracts rather than growing a design essay.
