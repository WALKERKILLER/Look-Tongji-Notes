# Decision log

Every durable choice with meaningful alternatives — architecture or process — lives in one place: this directory. Architecture and process decisions share the same format, lifecycle, and verifier. Specs own change contracts; commits own change history.

## Format

The format is **MADR (Markdown Any Decision Records)** with a documented `Class:` extension. Names and structure follow the industry standard so existing MADR tooling keeps working; the extension is ignored by tools that do not know it.

A decision record is a file named `NNNN-title.md` (4-digit zero-padded number, `-`, kebab-case title) directly inside this directory. Numbers are assigned sequentially; the number is the record's identity and never changes.

### Required sections

Every record contains exactly these `##` sections, in this order:

1. `## Status`
2. `## Context and Problem Statement`
3. `## Decision Drivers`
4. `## Considered Options`
5. `## Decision Outcome`
6. `## Pros and Cons of the Options`
7. `## Links`

`## Links` may be empty ("None.") but must exist. Additional `##` sections may follow `## Links` when a record needs them.

### Status line

The first non-empty line under `## Status` is the status value. Valid values:

- `Proposed` — the decision is being considered; not yet shipped.
- `Accepted` — the decision shipped; the record describes what is.
- `Rejected` — considered and declined; kept while its rationale prevents a tempting, meaningful mistake.
- `Deprecated` — no longer recommended; superseded by a linked record.
- `Superseded by [NNNN](NNNN-title.md)` — replaced by a newer record; the target must exist.

A record whose status is `Accepted`, `Deprecated`, or `Superseded by …` describes current or frozen reality. It is never rewritten into a different decision: to change a decision, add a new record and mark the old one `Superseded by NNNN`. Both records stay, cross-linked.

### Class line (extension)

The line immediately after the status value may be `Class: <value>`. It classifies the decision:

| Class | Covers |
|---|---|
| `architecture` | Structure of the shipped source: modules, boundaries, runtime vocabulary |
| `process` | Tooling, policy, workflow around the code: gates, package manager, conventions |
| `testing` | Test infrastructure and strategy |
| `feature` | A new user- or model-facing capability |
| `bug-fix` | Corrects a defect or closes a gap a postmortem surfaced |
| `simplification` | Removes code, behavior, or surface area without adding capability |

A missing `Class:` line is valid (it is an extension); an invalid value is a violation.

## Lifecycle

A decision starts `Proposed`. Once implemented, its status becomes `Accepted` and the record is kept current with what actually shipped (facts only — names, paths, structure — not the decision itself). A declined proposal is `Rejected`; delete a rejected record only when its rationale no longer prevents a plausible mistake. An obsolete accepted decision becomes `Superseded by NNNN` or `Deprecated`; never edit it into its opposite.

## Writing rules

- Create or update a record when a change chooses among meaningful alternatives and future maintainers may reasonably revisit the rationale. Do not create a decision record for routine implementation, mechanical refactors, obvious fixes already defined by regression tests, or work that merely follows an accepted decision; risk-boundary feature behavior belongs in a spec and change history belongs in commits.
- State the decision, what it beats, and what it gives up. `## Considered Options` lists genuine alternatives; `## Pros and Cons of the Options` records why the losers lost. A decision without its alternatives invites re-litigation.
- When a record relies on external evidence or an implementation source, cite it descriptively in `## Links` with a stable URL, DOI, or versioned permalink. Do not leave research or quantitative claims unlinked.
- Cross-reference records with relative Markdown links (`[0001](0001-title.md)`), never bare numbers.
- Document current reality, not change history. Put change stories in commits; the decision record states the live contract.

## Verifier

`scripts/verify-decisions.mjs` enforces: file naming, unique sequential numbering, required sections, valid status values, valid `Class:` values when present, and `Superseded by NNNN` targets that exist. It exits non-zero on any violation. `scripts/run-gates.mjs` selects it from the manifest; an explicitly authorized managed hook calls the runner.

## Index

- [0000](0000-use-markdown-architectural-decision-records.md) — Use Markdown Architectural Decision Records
- [0001](0001-repo-seed-is-a-skill-not-a-template.md) — repo-seed is a skill that seeds a self-governing repository, not a static template
- [0002](0002-self-governing-repository-design.md) — Self-governing repository design
- [0003](0003-repo-review-instantiated-per-project.md) — repo-review is instantiated per project, not shipped statically
- [0004](0004-studio-on-an-orphan-app-branch.md) — Look Studio lives on an orphan `app` branch
- [0010](0010-obsidian-one-way-export.md) — Obsidian integration starts as a one-way export with standard Markdown links
- [0011](0011-notion-sync-through-an-internal-integration.md) — Notion sync goes through a user-created internal integration and Markdown page content
