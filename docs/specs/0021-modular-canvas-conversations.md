# Modular canvas conversations

Artifact-Version: 1
Status: Approved
Approved-By: local deployment owner (upstream maintainer review pending), explicit implementation request and subsequent instruction to restrict generated AI content to conversations on 2026-10-29; amended by explicit approval of edge docking, sidebar conversations and user-pinned answers on 2026-11-04

## Intent

Make the existing study canvas a peer workspace for videos, documents, notes and independent AI conversations, retaining the handwriting engine and user data. Use one shared implementation and source staging for Android and macOS.

## Contract

Navigation and editing tools occupy fixed top controls; their layout is defined in [drawing controls](../drawing-controls.md). The pen box and AI entry retain device-local placement preferences: they collapse temporarily to compact draggable controls, follow the pointer freely and snap to the nearest edge on release, then expand. Docked controls avoid overlaps using their measured sizes; cancellation restores the prior layout. Course materials remain discoverable when empty or unavailable and are grouped by lecture within the current course. Course files are read through confined references; existing originals are not rewritten. New PDFs are paged modules with on-demand rendering and actual text geometry; existing page cards remain intact. Card-surface navigation, stationary holds and stylus selection follow [canvas input ownership](../decisions/0026-canvas-card-input-ownership.md). PDF text-selection UI is absent; extracted text and geometry remain available to explicitly bound AI context. Paging and playback buttons retain their own actions.

Conversation objects have independent explicit reference bindings, draft and turn history. No current video, whole course or other conversation is automatically included. Each request freezes its material ranges; prior conversation turns are reusable only with matching source fingerprints and ranges. Tool reads remain limited to the selected sources. This contract extends [0020](0020-multimodal-canvas-agent.md) by allowing the video context tools to extract a bounded local clip of at most 180 seconds and reuse the configured ASR pool or extract an actual frame when visual input is enabled. It does not permit whole-video upload, automatic downloads, arbitrary filesystem reads, shell/model-generated code, or changes to generic agent permissions.

Generated content initially remains in the conversation. The default UI is a collapsed edge entry with a sidebar for history and drafts, plus a compact input beside an explicit selection. Only an explicit user click on a completed answer can copy it into an editable canvas card with source anchors and undo; the original turn stays intact. The model receives only scoped read tools; card creation, updates, connections and automatic source focus are unavailable. The client never applies returned canvas operations, including pending results from earlier versions. Existing cards remain readable and manually editable. Actual observed source anchors accompany answers for user-initiated navigation.

Version 3 preserves version 1/2 readers in the new app and writes a pre-upgrade canvas snapshot before the first version-3 save of an existing document. Conversation sidecars stay outside canvas undo snapshots and remain recoverable after card deletion. Android retains application ID and signing identity; macOS retains the test app identity and library defaults. No original installation or user library is replaced by build/test commands.

## Plan

Implement explicit references and lecture-local conversations, shared three-bar UI, paged document extraction, scoped model history and bounded video parsing. Validate real parsers and storage independently of protocol fixtures; build both packages from the same staged source.

## Verification

Exercise public authenticated routes, course and conversation isolation, CAS, byte-identical originals and upgrade backups, actual PDFKit page/text extraction, per-page ink, scope removal, batch replay and undo, independent conversation recovery, tool cancellation, native builds and source manifests. Real-provider reasoning and physical-device frame measurements are separate acceptance requirements and cannot be inferred from protocol tests or signature checks.

## Evidence

Tests live beside the library and server seams and in `study_modules_test.dart`, the existing drawing widget tests and `canvas-agent.test.mjs`. Delivery-specific evidence and any unavailable real-provider or device checks are recorded with the build outputs; the [module reference](../multimodal-canvas.md) defines runtime behavior.
