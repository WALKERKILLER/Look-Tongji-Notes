---
name: repo-decisions
description: Use when a change chooses among meaningful alternatives whose rationale may be revisited, or when writing, updating, reviewing, or superseding a MADR record
---

# Writing and updating decision records

The decision log in [docs/decisions/](../../../docs/decisions/) is the durable home for architecture and process choices with genuine alternatives. Its directory entry defines the local or external standard; this skill carries the procedure.

## When a decision record is required

Write or update a decision record when a change chooses among meaningful alternatives and future maintainers may reasonably revisit the rationale. Do not create an ADR for routine implementation, a mechanical refactor, an obvious fix already defined by a regression test, or work that merely follows an accepted decision. Risk-boundary feature behavior belongs in a spec; commits retain change history.

## Procedure: create a new record

1. Find the next sequential number in `docs/decisions/` and take `max + 1`, zero-padded to 4 digits. Numbers are sequential starting at 0 and never change.
2. Create `docs/decisions/NNNN-kebab-case-title.md`.
3. Write the required sections in order:
   - `## Status` — first line is the status value; optional `Class: <value>` on the next line.
   - `## Context and Problem Statement`
   - `## Decision Drivers`
   - `## Considered Options`
   - `## Decision Outcome`
   - `## Pros and Cons of the Options`
   - `## Links`
4. State the decision, what it beats, and what it gives up. `## Considered Options` lists genuine alternatives; `## Pros and Cons of the Options` records why the losers lost. When the record relies on external evidence or an implementation source, cite it descriptively with a stable URL, DOI, or versioned permalink in `## Links`; do not leave research or quantitative claims unlinked.
5. Cross-reference records with relative Markdown links (`[0001](0001-title.md)`), never bare numbers.
6. Run `node scripts/verify-decisions.mjs`.

## Procedure: update an existing record

- **Status change to Accepted**: the decision shipped. Keep the record current with what actually shipped (facts only — names, paths, structure — not the decision itself). Present tense.
- **Superseding**: never rewrite an old record into its opposite. Create a new record, mark the old one `Superseded by [NNNN](NNNN-title.md)`, and cross-link both.
- **Deprecation**: a record that is no longer recommended but has no single successor becomes `Deprecated`.
- **Rejected**: a proposal considered and declined. Keep it while its rationale prevents a tempting mistake; otherwise delete it.

## Procedure: respond to a verify-decisions failure

The verifier names the violation. Fix the named file:

- `missing status value` — add the status line.
- `invalid status` — use Proposed/Accepted/Rejected/Deprecated or `Superseded by NNNN`.
- `invalid Class` — use architecture/process/testing/feature/bug-fix/simplification.
- `required sections missing or out of order` — add or reorder the seven required sections.
- `superseded target missing` — create the target record or point at an existing number.
- `numbers must be sequential` — renumber or fix the gap.
