# Whole-canvas synchronization uses the last saved document

## Status
Accepted
Class: feature

## Context and Problem Statement

The user edits one lecture on Mac and Android through the folder transport. A canvas includes handwriting, material cards and layout. Independent saves can produce versions that vector clocks identify as concurrent. The user explicitly chose whole-document replacement on 2026-10-31.

## Decision Drivers

- Show the latest saved canvas automatically on connected devices.
- Retain recovery copies of superseded handwriting and layouts.
- Keep the existing transport format, integrity checks and private libraries.

## Considered Options

- Pause independent canvas versions for manual conflict resolution.
- Merge strokes and cards by identifier, resolving each object independently.
- Select the last saved whole canvas and retain the superseded version as a recovery copy.

## Decision Outcome

Select the last saved whole canvas using the existing causal clocks and concurrent-save modification times. Equal concurrent timestamps use the existing stable hash tie-break. Save time comes from each device, so accurate device clocks are required for disconnected edits. Losing canvas versions are recovery files rather than blocking conflicts. Clean editors replace their document automatically; a local edit already in progress finishes saving against the current revision, with bounded retries if another save races it. Notes and other manually reviewed conflicts retain their existing policy.

## Pros and Cons of the Options

Manual resolution preserves a visible choice but interrupts ordinary device switching. Per-object merging preserves independent strokes but needs object updates and deletion semantics that the user declined. Whole-document replacement follows the selected workflow and keeps recovery files; a later save of layout or page state can supersede handwriting from the other device. It does not provide simultaneous collaborative editing.

## Links

- [Approved course synchronization contract](../specs/0023-course-folder-sync.md)
- [Immutable transport and device manifests](0021-course-folder-sync-with-device-manifests.md)
