# Canvas eraser mode and material gesture routing

Artifact-Version: 1

## Executive summary

Temporary eraser triggers ignored the selected erase mode, and material content intercepted gestures before canvas navigation could see them. The repair separates the eraser trigger from its mode and allows navigation from static material bodies.

## Summary

Pressure, side-button and inverted-pen erasing follow the selected partial, whole-stroke or lasso mode. PDF and image content accepts canvas panning while title bars and paging controls retain their actions. PDF text selection is removed from the UI at the user's request; extracted text and geometry remain available to explicit AI references.

## Timeline

The user reported pressure erasing always behaving as partial erase and being unable to pan from imported PDF content. Inspection identified explicit temporary-eraser exclusions and an early return before pointer registration. Widget regressions reproduced both failures on the unmodified implementation and passed with the repair.

## Root cause

The temporary-eraser flag controlled both activation lifetime and erase semantics. Material routing treated static page bodies like interactive child widgets, preventing canvas gesture tracking even when the page had no gesture to handle.

## Guardrails

[Input-mode regression tests](../../app/test/study_input_modes_test.dart) exercise pressure, side-button and inverted-pen modes, undo and return to writing, touch and mouse navigation from PDF/image bodies, pinch, paging, header movement and retained PDF text. [Handwriting tests](../../app/test/study_handwriting_test.dart), [shape tests](../../app/test/study_shape_test.dart) and [PDF-column tests](../../app/test/study_pdf_column_test.dart) protect adjacent gestures and saved ink. Simulated pointer events do not replace physical stylus acceptance.

## Follow-up: card title grip

A later report exposed a separate title-bar dead zone: a fixed 150-world-unit action exclusion covered the visible six-dot move grip and part of the title, even after the header actions changed layout. The exclusion now follows the rendered action row's actual bounds, including camera transforms; title text and the grip remain draggable. The input-mode regression exercises lecture and PDF grips with touch at normal zoom and mouse at reduced zoom, verifies that only the card moves, and checks undo.

## Follow-up: video surface ownership

An embedded player's picture drag still changed playback or volume instead of navigating the canvas, and stylus title drags could bypass deliberate selection. The shared canvas pointer tracker owns video picture contacts as well as static materials; explicit playback controls retain their own input. [Video input tests](../../app/test/study_video_hold_test.dart) cover panning, hold-to-drag, mixed-surface pinch, cancellation and playback controls. [Input-mode tests](../../app/test/study_input_modes_test.dart) require an enclosing pen selection before a card can move.

## Follow-up: palm priority

A mixed-input audit reproduced touch navigation continuing when the pen entered hover, including a matured card hold and an existing pinch. The old guard checked only the time since the last pen down/move at touch-down, without cancelling existing touches or renewing protection at pen-up. Pen contact lifetime now takes priority independently of drawing mode; hover/down cancels accepted touch navigation, and lift/cancel starts a one-second cooldown. Rejected contacts remain inert until lifted. [Palm regressions](../../app/test/study_palm_rejection_test.dart) cover hover takeover, stationary contact, lift/cancel, recovery through fresh touches and palm contacts overlapping a saved stroke. These injected events verify routing, not hardware palm classification.
