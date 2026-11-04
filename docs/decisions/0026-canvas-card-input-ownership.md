# Canvas owns card-surface navigation

## Status

Accepted
Class: feature

## Context and Problem Statement

Video picture gestures competed with canvas navigation, and title drags could move a card while the user intended to move the viewport. Touch and stylus need distinct ownership rules across all material cards.

## Decision Drivers

Navigate from any material surface, move a card deliberately, preserve writing and playback controls, and allow a pinch to span different materials.

## Considered Options

- Let each embedded material recognize its own navigation gestures.
- Make all card surfaces unconditionally drag the card.
- Route card navigation through the canvas and reserve explicit controls for their widgets.

## Decision Outcome

The canvas routes touch navigation and stationary holds for card surfaces. Video picture regions mark their contacts before the canvas listener receives them; playback controls retain separate hit regions. The same pointer tracker handles video, PDF, image and blank contacts, so mixed-surface pinch gestures share one camera. A pen can transform a card only through an enclosing selection. Device-specific timing and control behavior are defined in [drawing controls](../drawing-controls.md).

## Pros and Cons of the Options

Shared routing gives materials consistent navigation and avoids competing video scrub gestures. It requires explicit boundaries around embedded controls. Widget-owned navigation is simpler in isolation but cannot reliably coordinate contacts across materials. Immediate card movement is quick but makes browsing and handwriting prone to accidental layout changes.

## Links

- Supersedes [hold selection](0025-material-hold-selection.md).
- [Input-mode tests](../../app/test/study_input_modes_test.dart)
- [Video input tests](../../app/test/study_video_hold_test.dart)
