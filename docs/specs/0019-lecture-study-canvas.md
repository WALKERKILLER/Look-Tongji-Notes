# Lecture study canvas

Artifact-Version: 1
Status: Approved
Approved-By: local deployment owner, explicit approval on 2026-10-28; upstream maintainer review pending

## Intent

Opening a lecture through the course's study action presents an infinite canvas containing the lecture video, imported study material and handwriting. The existing outline, transcript, notes and assistant remain available beside the canvas. This is a local macOS test candidate; the installed application and existing course files are retained.

The scope is pen and highlighter input, erasing, undo and redo, pan and zoom, movable and resizable material cards, layer visibility and locking, local image/PDF/TXT/Markdown/video import, per-lecture persistence, and questions to the existing assistant with selected textual material and the current playback position. Matching all Notein features, handwriting recognition, handwriting vision questions, cloud synchronization and changes to assistant tool permissions are outside this contract.

## Contract

The course study entry and existing lecture/deep-link navigation open the same PlayerPage route with the same lecture identity and starting playback position. The canvas contains the existing native video player, retains the existing progress tracking, subtitles and fullscreen behavior, and offers a way to return to the conventional player layout.

Each lecture owns one independent canvas document. The document records a version, a revision, camera coordinates, layers, material objects and vector strokes. The first visit creates a canvas containing that lecture's video. Loading failure displays a recoverable error and does not overwrite stored content. Saves are serialized and use revision checks; a conflicting revision is reported instead of silently replacing another editor's work. Closing the study page waits for pending saves or offers recovery when saving fails.

Pen and mouse input can draw; touch gestures can pan and zoom. Completed ink and live ink render independently so extending a stroke does not rebuild all earlier stroke geometry. Erasing uses geometric hit testing with bounds rejection. Undo and redo cover ink and material edits. Material movement keeps any attached ink aligned. Layer locking prevents editing; hiding a layer affects its material and ink together.

Import accepts local images, PDF, TXT/Markdown and video selected by the user. Assets are copied into the lecture's study asset directory and represented by stable relative library references; no external file paths, credentials or temporary URLs are saved in canvas JSON. Import has explicit file, page and rendered-pixel limits, displays progress/errors, and does not publish partially imported cards when a conversion fails. PDF rasterization uses a bundled macOS PDFKit helper and keeps the source PDF; text cards preserve editable text. Existing courseware can be selected from the lecture's material list for import without changing its source.

The lookd API provides authenticated GET/PUT canvas document operations and POST asset import under `/api/lectures/{id}/study-canvas`. Input size, finite coordinates, object/stroke/point counts, unique identifiers and asset references are validated. Library access stays within the lecture directory using rooted filesystem operations; symlinks and path traversal are rejected. Document saves are atomic. A missing lecture returns 404, malformed input returns 400, oversized input returns 413, and revision conflicts return 409. Flutter and Node API clients describe the same routes and fields. Assistant tools gain no canvas write capability.

Asking the assistant is user-triggered and uses the existing local assistant connection. The question includes bounded textual selection or card content, lecture identity and video position. It does not claim to interpret handwritten strokes or video pixels. Existing credential ownership and assistant confirmation rules remain unchanged.

The local package retains the pinned Flutter engine, runner and plugin dependency set required by [ADR 0018](../study-workspace-build.md). It contains application code and test-independent runtime assets, excluding library contents and secrets. It is ad-hoc signed for local use, delivered as a separate application, and does not overwrite `/Applications/Look Studio.app`.

## Plan

Implement the document model and lookd storage/import boundary, mirror the client methods, and add the Flutter study canvas at the existing player route. Reuse the native player and assistant. Bundle a bounded PDFKit converter without introducing a new Flutter native plugin. Extend the existing native staging and packaging scripts to include these feature modules and the converter while retaining compatibility checks.

## Verification

Storage tests exercise independent lectures, atomic persistence, invalid/oversized documents, revision conflict, traversal and symlink rejection. Import tests exercise valid files, conversion failure and bounded output. Flutter tests exercise document round trips, erase/undo behavior, hidden/locked layers and selected-text context. Existing relevant server/client/player tests continue to pass.

Package verification checks the pinned engine/plugin inputs, universal binaries and codesigning. The shipped local candidate is opened at a course study entry to verify canvas/video/sidebar composition, drawing, import, save and reopen, and the conventional player fallback. Synthetic fixtures are used for generated test assets; no credentials or private course material enter test artifacts.

## Evidence

The local deployment owner approved this contract in chat on 2026-10-28. Persistence, revision conflicts, rooted asset access and index rebuild are covered by [library tests](../../lookd/internal/library/study_canvas_test.go); authenticated route registration and error contracts are covered by [server tests](../../lookd/internal/server/study_canvas_test.go). Bounded stroke round trips, erase/undo, layer protection, card-ink transforms and textual context are covered by [Flutter model tests](../../app/test/study_document_test.dart). The packaged application framework has been exercised with a separately identified test runner: silent lecture video renders and advances, fullscreen exits back to the canvas, the conventional player opens, and PDF/ink survive a relaunch. The macOS accessibility bridge reports pending-node update failures after presentation changes; returning from the conventional player and final modal interactions remain unverified by the desktop tool. The candidate is not fully accepted. Build inputs and checks are described in [the local build reference](../study-workspace-build.md).
