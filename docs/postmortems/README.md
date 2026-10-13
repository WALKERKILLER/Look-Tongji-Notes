# Postmortems

Incident write-ups: a bug reached a place it shouldn't have (a real user, a merged change, a release), and the interesting part is *why our process let it through*, not just the one-line fix.

A postmortem is not a decision record ([docs/decisions/](../../docs/decisions/)), which preserves durable rationale. It is a backward-looking record of a failure: what broke, the mechanism, why every safety net missed it, and the concrete guardrails added so the same class of bug fails loudly next time.

## When to write one

Write one when a bug is **subtle** (the mechanism is non-obvious and a careful engineer would re-derive it the hard way), **systemic** (the reason it escaped is a gap in tests/tooling/conventions, not a one-off typo), and **costly to rediscover** (it cost real debugging time, and would cost it again).

## Format

Every postmortem opens with an **Executive summary**: one short paragraph a busy reader can absorb in thirty seconds — what broke, the root cause in plain terms, why it escaped, and the durable lesson — before the detailed sections that follow:

1. `## Executive summary`
2. `## Summary`
3. `## Timeline`
4. `## Root cause`
5. `## Guardrails`

Name files `NNNN-short-title.md` (sequential number) and put `Artifact-Version: 1` below the title. `## Guardrails` must link at least one permanent repository test, gate, skill, AGENTS.md rule, or decision record. A verbal follow-up without a durable guardrail does not close the incident loop.

## Index

None yet.
