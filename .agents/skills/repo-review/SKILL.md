---
name: repo-review
description: Use when reviewing a pull request or a change in this repository — orients the reviewer to this repository's standards (AGENTS.md conventions, decision log, gates) and the review-specific checks that code alone cannot show
---

# Reviewing a change in this repository

Read the diff, the owning docs, the decision log, and enough surrounding code to understand the design before judging it. **Blocking requirements** are hard: a violation blocks the change. **Manual checks** rank remaining risk by this project's real failure modes — apply the ones the change touches, not every one, to every change.

## Sources of truth

- [AGENTS.md](../../../AGENTS.md): standing repository rules.
- [docs/AGENTS.md](../../../docs/AGENTS.md): documentation placement and prose discipline.
- [docs/decisions/](../../../docs/decisions/): durable design rationale. Disagreement with a decision record is a design discussion, not an automatic veto.
- [docs/specs/](../../../docs/specs/): risk-triggered change contracts.
- [docs/testing.md](../../../docs/testing.md): risk-to-layer selection, test topology, evidence rules, and maintenance budget.
- [docs/architecture.md](../../../docs/architecture.md): the module map and seams.

## Blocking requirements

### Universal (applies to any repository)

1. **New prose receives semantic review.** Critically review every added or changed Markdown passage, JSDoc, comment, prompt, description, diagnostic, and visible string. Verify required coverage, accuracy, placement, and editorial quality against the owning code or behavior; automated checks do not establish those properties.
2. **Docs match the code.** Config, defaults, errors, wire fields, events, and public behavior update the owning docs and JSDoc in the same diff.
3. **Contracts and decisions use the right artifact.** A risk-boundary change has an Approved spec; a durable choice with real alternatives has a decision record. Do not demand an ADR as a change log.
4. **Tests provide minimum sufficient behavior evidence.** Name the meaningful regression each changed test prevents and place its primary evidence at the lowest sufficiently real boundary. A fix links an existing deterministic reproduction or adds a regression test that fails before the fix and passes afterward; redundant coverage or implementation-only assertions do not satisfy this requirement.
5. **External-source provenance is retained.** If implementation is materially derived from a paper, article, community post, benchmark, research report, or copied/adapted code, cite it at the closest stable code location or link that location to a decision record whose `## Links` cites the source. A pull request, issue, prompt, or chat-only citation does not count; copied or adapted material also preserves applicable license and NOTICE requirements.

### Project-specific (instantiated at seed time from this project's own rules)

1. **Governance routing and ownership:** the change follows the [AGENTS.md](../../../AGENTS.md) routing, and its pull request into `app` carries the code-owner approval required by [CODEOWNERS](../../../CODEOWNERS).
2. **Credentials stay in lookd:** no diff logs, commits, or returns the Tongji session or password, the MinerU token (beyond its last 4 characters), or provider keys, and nothing from `~/LookStudio/` or `~/.local/share/look-studio/` is added.
3. **Assistant write boundary:** agent tools still write only notes, schedule marks and outlines, downloads still start from a user click, and the note overwrite and transcript-coverage guards in `agent/src/tools.mjs` are not weakened without an Approved spec.
4. **License hygiene:** no code is copied from GPL/AGPL projects; protocol-derived code cites its source, and third-party assets keep their `NOTICE`.
5. **API and link contracts stay in sync:** a lookd route or JSON field change updates `app/lib/core/api.dart` and `agent/src/lookd.mjs`; a `look://` scheme change updates `LookRef`, the producing agent tools and `lookd/internal/library/readme.go` in the same diff.

## Manual checks

### Project-specific (instantiated at seed time from this project's stack and known failure modes)

- **Daemon lifecycle (`lookd/internal/jobs`, `dl`, `asr`):** trace cancellation through every goroutine and HTTP call, cleanup of `.part` files and temp chunks on error, and pause/resume after a restart. Shared state needs `go test -race` evidence at the owning package.
- **External service etiquette:** Tongji, bcut/JianYing and MinerU calls keep their pacing, backoff, cooldowns and quotas; a new call path reuses the existing client rather than opening a parallel one, and user-facing errors say what failed.
- **Store and library data:** a `schema.sql` change upgrades an existing `library.db` with user data in place, and the index can still be rebuilt from library files.
- **Model perspective (`agent/src`):** read the exact tool names, schemas, descriptions, `GUIDE`/playbook text and system prompt a model receives; check tool-result size caps, the per-turn tool-call cap, and that error text tells the model how to recover.
- **Flutter state and rendering:** after every `await`, check `mounted`; dispose controllers, timers and subscriptions; snackbars and overlays do not outlive their page. Markdown/LaTeX changes extend `app/test/look_markdown_test.dart` with the failing input.
- **Release packaging:** a change to binary discovery in `app/lib/core/lookd_service.dart` or to the agent entry keeps `.github/workflows/release.yml` producing a working layout.

### Universal fallbacks (apply where the project has no specific rule)

- **Intent and interface contracts:** trace both sides of every changed interface. Confirm the implementation matches the change and any decision record, including errors, cancellation, ownership, and disposal.
- **Lifecycle and concurrency:** for async setup, callbacks, processes, or teardown, check races before publication, cancellation during awaits, independent error reporting, and complete cleanup.
- **Human readability:** read changed code from its entry point downward. The primary path stays understandable without opening every helper. Challenge abstractions that only forward or rename, mixed abstraction levels, misleading or generic names, new synonyms for existing concepts, and logic outside its owning boundary. Block when these make behavior unreliable to infer, hide effects or cost, or violate established vocabulary or boundaries; otherwise report subjective polish as advisory. Line counts, parameter counts, duplication, and complexity scores are signals, not verdicts.
- **Scope and necessity:** map each abstraction, option, defensive copy, and compatibility path to its current contract and consumer. Challenge unrelated features and speculative generality.
- **Bounds cover the final operation:** probe tiny and exact limits, oversized chunks, and multibyte text for byte limits.
- **Test value and boundary:** identify the contract each changed test owns, challenge duplicate evidence, and use the real shipped entry path whenever packaging, configuration, process setup, or wiring is part of the risk.
