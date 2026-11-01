# Retain world layout during canvas camera gestures

## Status
Accepted
Class: architecture

## Context and Problem Statement

The learning canvas combines ink with interactive media and editable cards. Updating each card's screen position and size on every camera event makes layout work grow with visible content. Selection and eraser feedback must follow input without invalidating recorded ink or rebuilding media widgets.

## Decision Drivers

- Retain the existing Flutter renderer, native video and stable world coordinates.
- Keep live video, text selection, card editing and source navigation interactive.
- Bound retained material layout while panning an infinite document.
- Keep cursor and selection feedback independent from stored ink.

## Considered Options

- Rebuild screen-sized card positions and repaint all content on every camera event.
- Snapshot the viewport as a bitmap during every pan or pinch.
- Transform a retained world-space scene with a bounded culling margin.

## Decision Outcome

Camera notifications update a transform around world-space card layouts and recorded ink. The retained stage includes the viewport and a viewport-sized margin; leaving the margin or settling a gesture recomputes the stage. Grid, live ink and interaction feedback use separate repaint boundaries. No document format or tool permissions change.

This preserves live media and avoids synchronous screenshot capture during gestures. It trades some offscreen layout and raster work for fewer repeated card layouts. Stage-edge transitions and device GPU raster costs still require performance measurements; retained layout tests do not establish a tablet frame rate.

## Pros and Cons of the Options

- Per-event screen layout is straightforward but repeats expensive widget and layout work during the highest-frequency interaction.
- Bitmap snapshots reduce scene complexity, but suspend media updates, incur capture costs and blur while enlarging; they also complicate input and source capture.
- A retained transform preserves interactive widgets and existing world coordinates, with explicit culling and separate feedback; it requires testing hit coordinates, stage transitions and widget retention.

## Links

- [Drawing controls and gesture contracts](../drawing-controls.md)
- [Native study canvas](0016-native-lecture-study-canvas.md)
- [Flutter Transform](https://api.flutter.dev/flutter/widgets/Transform-class.html)
- [Flutter RepaintBoundary](https://api.flutter.dev/flutter/widgets/RepaintBoundary-class.html)
