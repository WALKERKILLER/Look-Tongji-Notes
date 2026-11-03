# Persistent conversations as canvas modules

## Status

Accepted
Class: architecture

## Context and Problem Statement

A one-shot modal cannot represent parallel learning conversations. Putting full histories inside canvas undo snapshots multiplies memory use and couples writing history to unrelated object movements.

## Decision Drivers

Preserve the retained Flutter canvas, explicit reference permissions, user documents and recoverable conversation history across native platforms.

## Considered Options

- Keep the one-shot modal and fixed assistant sidebar.
- Embed all conversation messages in each canvas snapshot.
- Store conversation modules in the canvas and their histories in lecture-local sidecars.

## Decision Outcome

Choose lecture-local conversation sidecars with independent revision checks. Canvas objects retain identity, layout and conversation ID; undo retains the sidecar so a restored object can recover its history. Each model run reads only explicitly bound sources. History is reusable only when the exact source identities, ranges and fingerprints match the current context; removing a reference excludes its dependent history from subsequent requests.

## Pros and Cons of the Options

Sidecars preserve dialogue without enlarging each drawing checkpoint and fit existing backup boundaries. They require separate save errors, interrupted-run recovery and explicit correlation of applied operation IDs. Embedded histories simplify a single write but make drawing undo expensive. A modal preserves less state but fails the parallel-module interaction requirement.

## Links

- [Approved module-canvas contract](../specs/0021-modular-canvas-conversations.md)
- [Retained world layout](0018-retain-world-layout-during-canvas-gestures.md)
- [Scoped tool runs](0017-scoped-canvas-tool-runs.md)
