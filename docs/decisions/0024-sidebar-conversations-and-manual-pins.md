# Sidebar conversations with explicit canvas pins

## Status

Accepted
Class: feature

## Context and Problem Statement

Learning materials and handwriting share a spatial canvas. A central chat panel competes for that space, while permanently placing every answer on the canvas accumulates objects unrelated to the learner’s current arrangement.

## Decision Drivers

Keep materials visible, retain parallel conversations and drafts, make asking about a region local to that region, and let the user decide which answers become learning artifacts.

## Considered Options

- Keep a permanent central conversation stage with visible conversation nodes.
- Put every answer directly on the canvas.
- Use a collapsible sidebar and explicit user-created answer cards.

## Decision Outcome

Use a collapsed edge entry and sidebar for conversation history, with a compact question field beside an explicit selection. Only a user click pins a completed answer as an editable, sourced card; the model has no canvas write tools. Keep the conversation identities and lecture-local sidecars defined by [0019](0019-persistent-scoped-canvas-conversations.md). Hide conversation metadata objects from the rendered canvas without rewriting saved layouts.

The pen palette and AI entry collapse during a drag, move freely and snap to the nearest edge on release at any distance, then expand. Navigation and editing tools occupy fixed, compact top controls. One layout measures the docked controls together and avoids overlaps, including on resize. Dock placement stays device-local; changing it never edits shared course content.

## Pros and Cons of the Options

A sidebar restores canvas space when closed and preserves chat history without making it an object the user must arrange. Explicit pins create an extra click for answers worth keeping, but keep their placement under user control. A permanent central stage makes chat immediately discoverable but obscures studying space. Automatic answer cards avoid the pin action but clutter the canvas and couple response generation to layout changes.

## Links

- [Approved conversation contract](../specs/0021-modular-canvas-conversations.md)
- [Runtime behavior](../multimodal-canvas.md)
- [Drawing and docking controls](../drawing-controls.md)
