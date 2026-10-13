# AGENTS.md — Documentation standard

This file defines document structure, Markdown tiers, writing rules, and the hygiene checklist for this repository. Use the `repo-review` skill for semantic review and the `repo-decisions` skill for decision records.

## Document structure

Every human-facing document belongs to a tier. A document's subject and tree position fix its scope: describe its own subject at appropriate detail, direct children only by purpose and responsibility, and link to the owning descendant for lower-level detail. Testing mechanisms belong at the lowest owning level.

### The tier taxonomy: one home per fact

Each fact has one home; everywhere else, link there.

| Tier | Job | Does NOT belong there |
|---|---|---|
| Root `AGENTS.md` | Management identity, skill router, and standing orders needed in every session | Stories, worked examples, restated procedures |
| `docs/AGENTS.md` | The documentation standard | Repo-wide rules the root file carries |
| `docs/architecture.md` | Ordered map: composition, modules, seams | Per-module detail, decision rationale |
| `docs/development.md` | Contributor setup, daily workflow, commands | Runtime rationale |
| `docs/testing.md` | Test mission, risk-to-layer selection, topology, evidence, maintenance budget | Per-case walkthroughs or drifting command inventories |
| `docs/specs/` | Risk-triggered Intent, Contract, Plan, Verification, and Evidence for a change | Durable alternative rationale or routine-change ceremony |
| `docs/decisions/` | Durable choices with genuine alternatives (MADR + Class extension) | Change logs, implementation plans, product contracts |
| `docs/postmortems/` | Incident write-ups linked to permanent guardrails (the only war-story tier) | — |
| In-repo skills | Reusable workflows and decision procedures | Product contracts |

Placement: change contract → specs; durable alternative rationale → decisions; procedures → skills or development; incident stories → postmortems; standing orders → root `AGENTS.md` with a link.

## Tutorial or reference

Classify every in-scope document as a tutorial or a reference. A tutorial follows an ordered path to an outcome. A reference defines a lookup scope and current behavior without a teaching sequence. Separate substantial mixed forms; label a small secondary form clearly.

## Writing rules

- Document current state, not change history. Avoid "previously/now/no longer", PRs, commits, and stack positions in durable prose; name the live mechanism.
- One physical line per paragraph.
- State complete contracts, not reasoning transcripts.
- Cross-reference with machine-checkable relative Markdown links. Links must resolve.
- No fill-in tokens may remain in any doc that ships.
- Comments and JSDoc state contracts or provenance; do not restate code.

## Hygiene checklist

Hunt these in any doc:

- The same rule stated in more than one home. Keep one home and link the rest.
- Narrated history or war stories.
- Implementation-status annotations ("implemented!", "future: …"). Status rots.
- Hand-restated catalogs or inventories when source or a generator is authoritative.
- Reasoning transcripts: step-by-step narration, test walkthroughs, rejected alternatives.
- Rationale repeated beside sibling methods instead of once at the owning place.
- Paragraph walls. Split or demote.
- Emphasis inflation. Reserve emphasis for the clause that changes behavior.
- Spec-speak in shipped decisions ("should", migration plans, acceptance checklists).

## Budget

Root `AGENTS.md` has a soft budget of 100 lines. When it grows past that, relocate content to its tier home and leave a one-line link.
