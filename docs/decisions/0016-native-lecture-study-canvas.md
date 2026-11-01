# Render the lecture study canvas in Flutter

## Status
Accepted
Class: architecture

## Context and Problem Statement

The lecture study page combines a native media_kit video player with the course sidebar and resident assistant. The independent browser canvas prototype demonstrates handwritten ink and spatial material cards. The local macOS delivery path retains an installed runner and exact plugin dependencies; adding a Flutter WebView plugin requires a new native runner build with full Xcode.

## Decision Drivers

- Open the canvas inside the existing course study route and retain native playback and assistant behavior.
- Keep per-lecture material and ink in the local library with explicit validation and save errors.
- Produce a separate local candidate with the available pinned Flutter toolchain and Command Line Tools.

## Considered Options

- Embed the browser prototype with a new Flutter WebView plugin.
- Launch a separate browser or WKWebView companion window from the course study action.
- Render the study canvas in Flutter and rasterize imported PDFs with a standalone PDFKit helper.

## Decision Outcome

The implementation uses Flutter for ink, camera transforms and material cards, retains the existing native lecture video and assistant, and puts persistence behind lookd. A standalone macOS PDFKit helper handles bounded PDF conversion without changing the runner or plugin dependency set. The independent browser prototype informs the document structure and incremental ink approach; application code is implemented within the Flutter and Go boundaries. This requires a separate renderer. macOS uses PDFKit; Linux and Android use bounded Poppler subprocesses, as described in the build reference.

## Pros and Cons of the Options

- A WebView reuses the browser renderer and PDF.js but introduces a native plugin and runner build outside the installed-runner compatibility contract.
- A companion window avoids changing the runner but separates the canvas from the screenshot's actual learning page and complicates player and assistant ownership.
- Flutter rendering keeps the learning page, video and assistant in one native route and uses the available build path. It requires a separate renderer and an explicit macOS PDF conversion boundary.

## Links

- [Lecture study canvas contract](../specs/0019-lecture-study-canvas.md)
- [Study workspace build dependencies](../study-workspace-build.md)
- [Flutter CustomPainter API](https://api.flutter.dev/flutter/rendering/CustomPainter-class.html)
- [Apple PDFKit](https://developer.apple.com/documentation/pdfkit)
- [media_kit_video 2.0.1 controller attachment](https://pub.dev/documentation/media_kit_video/2.0.1/media_kit_video/VideoController/VideoController.html)
