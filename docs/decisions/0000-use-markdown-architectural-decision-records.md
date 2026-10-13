# Use Markdown Architectural Decision Records

## Status
Accepted
Class: process

## Context and Problem Statement
A repository's decisions — why a design or a process rule exists, what it beat, and what it gave up — are lost if they live only in commit messages or conversation. Without a decision log, the same decision gets re-litigated, and future maintainers cannot tell whether current structure is intentional or accidental.

## Decision Drivers
- A single, industry-standard home for durable architectural and process choices with meaningful alternatives.
- Tooling compatibility: records should work with existing ADR tooling.
- Machine-checkable structure so drift can be caught by a verifier.

## Considered Options
- MADR (Markdown Any Decision Records) in `docs/decisions/`.
- Nygard's original ADR format.
- A bespoke "notes" format with a custom lifecycle vocabulary.
- No decision log at all.

## Decision Outcome
Adopt **MADR** as the format for durable choices with meaningful alternatives, stored flat in `docs/decisions/NNNN-title.md`, with a documented `Class:` extension line (architecture/process/testing/feature/bug-fix/simplification). Status values are the MADR-native set: Proposed, Accepted, Rejected, Deprecated, Superseded by NNNN. The lifecycle and linking discipline — a superseded record is never rewritten into its opposite, a new record supersedes it — follow the MADR convention. Specs own risk-triggered change contracts; commits own change history. `scripts/verify-decisions.mjs` enforces naming, numbering, sections, status, class, and supersede links.

### Consequences
- Good: one place for durable rationale; existing MADR tooling can parse the files; drift is caught mechanically.
- Good: the `Class:` extension is ignored by tools that do not know it, so compatibility is preserved.
- Trade-off: a small format overhead per decision compared to free-form notes; accepted because the verifier makes the format cheap.

## Pros and Cons of the Options
### MADR
- Good: standard, documented, tooling-friendly.
- Good: `## Status` at the top makes lifecycle explicit.
- Neutral: requires a few required sections; the verifier keeps them honest.

### Nygard format
- Good: the original, widely known.
- Bad: looser section conventions; less uniform to verify.

### Bespoke notes format
- Good: fully tailored vocabulary.
- Bad: no ecosystem compatibility; reinvents a wheel the industry already standardized.

### No decision log
- Bad: decisions live only in memory and commit history; re-litigation is guaranteed.

## Links
- [ADR 0001](0001-repo-seed-is-a-skill-not-a-template.md) — why this repository exists as a skill.
- [ADR 0002](0002-self-governing-repository-design.md) — the five-layer governance design this log protects.
