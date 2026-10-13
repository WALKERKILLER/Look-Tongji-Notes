# Self-governing repository design

## Status
Accepted
Class: architecture

## Context and Problem Statement
A generated repository that is "documented" but ungoverned will drift: links rot, placeholder text survives, decisions get re-litigated, seeded files get edited silently, and process steps get skipped. Documentation alone does not prevent drift; layered instruction, distinct durable artifacts, deterministic gates, and a feedback loop form one governance system.

The open question: how much of that system should a seed repository get on day one, and in what shape, without coupling the seed to any one technology stack or any one vendor's tooling?

## Decision Drivers
- Objective anti-drift rules must be mechanical through verifiers and a shared runner.
- The seed must be technology-stack agnostic: no generated build config, no generated CI.
- The seed must be cross-tool for agents: AGENTS.md and SKILL.md are the industry standards; no vendor-private extensions.
- Day-one scope must be a governance skeleton, not a full harness machine; the upgrade channel grows it.
- Read-only assessment may be autonomous; changing governance or local/external state requires user authority.

## Considered Options
- Single-layer governance: one large AGENTS.md carrying everything, no gates.
- Harness-scale day one: port all 35+ gates, i18n pairing, coverage gates, vendoring policy.
- Five-layer governance skeleton plus an upgrade channel — the chosen route.

## Decision Outcome
The generated repository is governed by **five layers plus an upgrade channel**:

- **L0 — resident instructions**: root `AGENTS.md` (soft budget of 100 lines) plus `CLAUDE.md` that imports it via `@AGENTS.md`. Carries the governance loop hard rules and the security rules (never commit/push without explicit request).
- **L1 — deterministic gates**: the manifest-selected `scripts/run-gates.mjs` executes Spec, decision, postmortem, link, placeholder, and ownership verifiers. CI and an optional authorized hook call the same runner.
- **L2 — change memory**: risk-boundary work uses an Approved Spec; MADR records preserve durable alternatives; postmortems link escaped failures to permanent guardrails.
- **L3 — in-repo skills**: `repo-review`, `repo-decisions`, and `repo-governance` live in `.agents/skills/`; review policy is instantiated per project.
- **L4 — process evidence**: testing policy, Spec Evidence, postmortem guardrails, and PR review findings outlive an agent session.
- **Upgrade channel**: `.repo-seed/manifest.json` records ownership, capability state, governance paths, external sources, and progressive artifact policy; re-running refreshes untouched files, preserves user edits, and never deletes user files.

### Consequences
- Good: drift and path-level hallucination are caught mechanically through one installed gate set.
- Good: the seed is stack-agnostic and cross-tool; it adds no build configuration.
- Good: day-one scope is a skeleton; optional capabilities are assessed and added later when facts justify their ongoing cost.
- Good: local hooks, CI, policy changes, and external connections retain an explicit human authority boundary.
- Trade-off: semantic correctness (does the prose say something true?) cannot be proven by gates; `repo-review` and the decision log's "what we gave up" discipline mitigate but cannot eliminate it. This is an industry-wide limit, not a repo-seed gap.

## Pros and Cons of the Options
### Single-layer governance
- Good: simplest possible seed.
- Bad: resident instructions have bounded capacity (context limits); no mechanical verification; process steps decay.

### Harness-scale day one
- Good: maximal rigor from the start.
- Bad: disproportionate for a new repository; couples the seed to a specific toolchain; violates the stack-agnostic constraint.

### Five-layer skeleton plus upgrade channel
- Good: mechanical anti-drift where it matters most; stack-agnostic; grows with the repository.
- Good: honest about the semantic-correctness limit.
- Bad: requires manifest/update machinery from day one.

## Links
- [ADR 0000](0000-use-markdown-architectural-decision-records.md) — the decision log standard.
- [ADR 0001](0001-repo-seed-is-a-skill-not-a-template.md) — why the generator shape is a skill.
- [.repo-seed/update-strategy.md](../../.repo-seed/update-strategy.md) — ownership and update semantics.
- [docs/AGENTS.md](../AGENTS.md) — the documentation standard (L0/L2 discipline).
