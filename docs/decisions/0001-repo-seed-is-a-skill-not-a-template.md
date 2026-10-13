# repo-seed is a skill that seeds a self-governing repository, not a static template

## Status
Accepted
Class: architecture

## Context and Problem Statement
The goal is to let any repository — empty or existing, any technology stack — become agent-native: documented, decision-logged, and governed by mechanical checks, ready for vibe coding. Two shapes were on the table: a static template repository that users fork or clone, or a skill that generates and maintains the governance layer in place.

Static templates have a known fatal flaw: a fork is a single-commit snapshot with no upstream history, so it can never receive template improvements, and it cannot adapt to the target repository's actual state. Pure runtime skills have a different flaw: skill triggering is unreliable (Vercel's focused Next.js evals found that an available skill was never invoked in 56% of cases), and generated-but-not-committed output is invisible and unversioned.

## Decision Drivers
- The generated repository must stay upgradeable: upstream governance improvements must reach existing seeded repositories.
- The generated repository must be deterministic where structure matters, and adaptive where content matters.
- The user must see and own the result: generated files are committed baselines, not ephemeral context.
- The industry-standard shapes (AGENTS.md, SKILL.md, MADR) must be reused, not reinvented.

## Considered Options
- A static template repository (fork-to-start).
- A pure runtime skill whose output never lands in the repository.
- A skill that scaffolds deterministic structure and delegates content to the model, with an ownership manifest for updates — the chosen route.

## Decision Outcome
repo-seed is **one generator skill** (SKILL.md + zero-dependency scripts + templates under `references/`). It writes an approved governance baseline into the target repository (resident instructions, docs, Specs, decision/postmortem memory, three in-repo skills, gates, and `.repo-seed/manifest.json`), which the user reviews and commits. Hooks are a separately authorized capability. Re-running the skill is the upgrade channel: the manifest records ownership, capabilities, governance paths, and external sources; files the user changed are preserved and template evolution applies only to untouched files.

### Consequences
- Good: seeded repositories remain upgradeable — the "dead template" failure mode is structurally removed.
- Good: the user owns the result because it is committed baseline, not ephemeral context.
- Good: the generator is a single explicit-invocation skill, the shape where skills are most reliable.
- Trade-off: the generator needs a state file (`.repo-seed/manifest.json`) and update semantics; the complexity is contained in one scripted path.

## Pros and Cons of the Options
### Static template repository
- Good: instant, deterministic, zero runtime.
- Bad: fork cannot receive upstream updates; cannot adapt to repository state; no question-based customization.

### Pure runtime skill, no persisted output
- Good: cheap to trigger; no repository pollution until invoked.
- Bad: unreliable triggering; invisible, unversioned output; cannot be reviewed as a diff.

### Skill generator with persisted baseline and ownership manifest
- Good: deterministic structure, adaptive content, upgradeable baseline, user-owned result.
- Bad: requires manifest maintenance and update-mode logic.

## Links
- [ADR 0000](0000-use-markdown-architectural-decision-records.md) — the decision log this record lives in.
- [ADR 0002](0002-self-governing-repository-design.md) — what the generated baseline contains.
- [.repo-seed/update-strategy.md](../../.repo-seed/update-strategy.md) — the ownership/update semantics.
- [Vercel: “AGENTS.md outperforms skills in our agent evals”](https://vercel.com/blog/agents-md-outperforms-skills-in-our-agent-evals) — source for the 56% non-invocation result.
