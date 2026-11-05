# Hold to select canvas materials

## Status

Superseded by [0026](0026-canvas-card-input-ownership.md)
Class: feature

## Context and Problem Statement

Dragging static PDF or image content pans the shared canvas, while moving one material requires a narrow title bar. At reduced zoom that target is difficult to acquire.

## Decision Drivers

Keep immediate canvas navigation, allow selection without a precise title target, preserve handwriting and two-finger navigation, and avoid empty undo steps.

## Considered Options

- Move materials immediately when their bodies are dragged.
- Require all movement to start from a title bar.
- Distinguish a stationary hold from immediate panning.

## Decision Outcome

Use a stationary hold for material selection, with timing, movement tolerance and device rules defined in [drawing controls](../drawing-controls.md). After selection, the same contact moves the card and anchored handwriting. Early movement remains canvas navigation. Hold-only selection does not checkpoint the document; movement creates a single undo step. For lecture video in the canvas, an inherited movement scope connects only the picture gesture layer to card movement. Playback controls remain above that layer and retain their gestures. The same player outside the canvas retains long-press speed boost.

## Pros and Cons of the Options

Holding adds a small delay but avoids precision targeting and retains immediate panning. Immediate material movement would interfere with browsing a large PDF. Title-only movement remains available but is difficult at small canvas scales.

## Links

- [Drawing controls](../drawing-controls.md)
- [Input-mode regression tests](../../app/test/study_input_modes_test.dart)
