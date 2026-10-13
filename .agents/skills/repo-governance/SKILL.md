---
name: repo-governance
description: Use when repository complexity, delivery, ownership, security, release, or incident signals change; when governance may be missing; or when adding, reviewing, deferring, or upgrading repo-seed capabilities
---

# Evolving repository governance

Governance grows with the repository. Do not install every mechanism up front, and do not wait for a preventable failure before naming a new control.

## Start with a read-only assessment

Run `node scripts/audit-governance.mjs --json` and read `.repo-seed/manifest.json`. The audit observes discrete repository facts only; it does not authorize changes.

- A `blocking` recommendation affects the safety boundary of the current work. Raise it before implementation.
- An `advisory` recommendation improves maturity without making the current work unsafe. Finish the requested work, then raise it in the handoff.
- A suppressed recommendation was already declined or deferred against the same facts. Do not ask again until its assessment hash changes.

## Authority boundary

You may autonomously inspect, audit, compare capability state, and produce a dry-run. Ask the user before you:

- enable a capability or add its files;
- install or replace a Git hook;
- change governance policy or a source of truth;
- connect an external system or change remote permissions.

Once a capability is enabled, untouched repo-seed-owned files may refresh through the normal upgrade channel. Preserve user-owned content and stop on conflicts.

## Midstream capability workflow

1. Name the new repository facts and the capability they make relevant.
2. Check whether an existing or external mechanism already satisfies the need.
3. Explain benefit, ongoing cost, files/processes added, and whether the recommendation blocks current work.
4. Ask for authorization. Record `enabled`, `external`, `deferred`, or `declined` plus the assessment hash and concise reason.
5. Preview with a dry-run, apply only the approved capability, then run `node scripts/run-gates.mjs`.
6. Update review instructions when the capability adds a new risk surface.

## Promotion ladder

Promote knowledge to the cheapest layer that reliably prevents recurrence:

- one task-specific fact stays in its spec or plan;
- a repeated project convention becomes resident instruction or a focused skill;
- a rule that must hold without exception becomes a deterministic gate;
- a systemic escaped failure becomes a postmortem linked to the new guardrail.

Do not convert every preference into a gate. Deterministic enforcement is for objective rules with low false-positive cost.

## Unmanaged repositories

When `.repo-seed/manifest.json` is absent, a read-only audit and adoption proposal are allowed. Never write the Core automatically. The adoption sequence is audit, dry-run, user authorization, incremental write, then verification. Preserve an existing source of truth rather than creating a duplicate.
