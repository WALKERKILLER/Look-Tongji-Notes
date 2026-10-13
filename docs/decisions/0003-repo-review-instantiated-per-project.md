# repo-review is instantiated per project, not shipped statically

## Status
Accepted
Class: architecture

## Context and Problem Statement
The seed ships resident procedure skills plus repo-review, a project policy. A static review policy generalizes poorly across stacks, carries no project red lines, and breaks the generator principle ADR 0001 established — structure deterministic, content instantiated. Every other content-bearing seeded doc (architecture.md, testing.md) is instantiated with tokens; repo-review needs the same treatment.

## Decision Drivers
- Review policy is project-specific; its value is specificity, not uniformity.
- The seed must stay stack-agnostic: no checks that presume one stack family.
- Existing machinery (verify-placeholders scope, manifest refusal logic) already enforces instantiation once a template carries tokens.
- Procedure and policy skills differ: a procedure (how to write an ADR) is bound to the seed's own standard and can ship static; a policy (what must be checked here) cannot.

## Considered Options
- Static repo-review for every project (status quo).
- Fully generic repo-review with no project content.
- Universal core plus per-project instantiation with a derivation standard — the chosen route.

## Decision Outcome
The repo-review template carries a universal core (semantic prose review, docs match code, correct Spec/decision use, tests, and provenance) plus two instantiation tokens — REVIEW_PROJECT_BLOCKING and REVIEW_PROJECT_CHECKS — that the model composes at seed time from AGENTS.md hard rules, architecture seams, stack detection, and interview Q8. The repo-seed skill carries a derivation standard (`references/review-standard.md`) with a per-stack risk catalog; it is skill-side guidance and is not seeded into target repositories. The record step marks the instantiated file's manifest entry `userModified` via `--user-owned`, and a re-run never refreshes a user-owned entry. Machine-provable gate results stay out of semantic review; blocking requirements block while manual checks rank remaining risk.

### Consequences
- Good: seeded repositories get a review policy that names their actual failure modes and red lines.
- Good: the placeholder gate mechanically prevents an un-instantiated repo-review from shipping.
- Good: upstream evolution still applies to the universal core; project content is protected.
- Trade-off: instantiation quality depends on the executing model, mitigated by the derivation standard and the universal-core floor.
- Trade-off: project-specific content no longer refreshes from upstream, by design.

## Pros and Cons of the Options
### Static repo-review (status quo)
- Good: zero instantiation cost; upstream-editable.
- Bad: stack-biased checks; no project red lines; breaks the generator principle.

### Fully generic repo-review
- Good: never wrong for any project.
- Bad: near-zero value; a reviewer needs project-specific gates to be useful.

### Universal core plus per-project instantiation
- Good: specific where it matters, standard where it does not; existing gates enforce it.
- Bad: depends on model composition quality at seed time.

## Links
- [ADR 0001](0001-repo-seed-is-a-skill-not-a-template.md) — the generator principle this restores for the review skill.
- [ADR 0002](0002-self-governing-repository-design.md) — the L3 layer this changes.
- [repo-review SKILL](../../.agents/skills/repo-review/SKILL.md) — the instantiated result.
- [.repo-seed/update-strategy.md](../../.repo-seed/update-strategy.md) — user-ownership and refresh semantics.
