# Scope canvas tools to a reviewed learning selection

## Status
Accepted
Class: architecture

## Context and Problem Statement

The native study canvas owns mutable ink, materials and undo history. The resident bot has broader conversational state but its existing tool permissions do not include canvas writes. A learning request needs selected source text, optionally selected pixels, and editable output without granting a model arbitrary document replacement or access to unrelated materials.

## Decision Drivers

- Reuse the existing model configuration, vision fallback and local daemon.
- Bind references to source identities and content rather than screen pixels.
- Keep one canvas transaction, explicit overwrite review, cancellation and bounded resource consumption.

## Considered Options

- Add unrestricted document reads and replacement to the resident bot.
- Treat a whole-canvas screenshot and Markdown answer as the workspace interface.
- Use a separate bounded tool run over reviewed context and apply typed operations in the existing Flutter document.

## Decision Outcome

The canvas-run service uses the existing ModelPipeline with a finite tool budget. lookd resolves selected identifiers and ranges against the saved document; Flutter supplies only explicitly selected visual regions. Tools stage typed card and connection operations. Flutter validates the result against the source snapshot and applies one undoable transaction, with review before changing existing content. A versioned document retains structured blocks and normalized source anchors. General chat tools and their write guards retain their own scope.

## Pros and Cons of the Options

- Unrestricted bot writes reuse conversation history but widen the source and mutation boundary and bypass the canvas undo owner.
- Whole-canvas screenshots require less extraction work but lose reliable text ranges, source identity and editable structure while exposing unrelated material.
- Scoped runs require selection/context adapters and a typed operation validator, but preserve the existing renderer, safe components and local storage. A run sees only the sources the user reviewed, so missing source capabilities remain explicit.

## Links

- [Approved multimodal canvas contract](../specs/0020-multimodal-canvas-agent.md)
- [Native study canvas](0016-native-lecture-study-canvas.md)
- [Existing vision bridge](../../agent/src/vision.mjs)
