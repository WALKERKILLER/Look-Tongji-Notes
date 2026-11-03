# Canvas remains stale after a sync notification is lost

Artifact-Version: 1

## Executive summary

A tablet canvas reached the Mac working library while the open Mac canvas still showed an older version. The canvas listened to a single event stream without a catch-up check after interruption. Tests delivered a notification for every remote update, leaving this failure invisible. Open editors need to verify current state independently of transient notifications.

## Summary

The user reported missing tablet handwriting. Recovery copies retained 39 strokes, and the current tablet draft contained 43 strokes. Selecting the current tablet draft and restoring transport connectivity recovered all 43 strokes on the Mac. No stroke from the 39-stroke copy was missing from the current draft.

## Timeline

- On 2026-10-31, inspection found an older active canvas and a handwriting conflict copy on the Mac; Android was waiting for a version choice.
- Publishing the tablet draft saved 43 strokes. NAS received the new canvas, while Mac Syncthing remained stale and subsequently reported SOCKS relay connection errors.
- A service-scoped environment fix restored Mac Syncthing connections and the working file received all 43 strokes. The open Mac page still displayed an older document.
- A regression reproduced a remote document update without a notification. The user separately selected whole-canvas last-save-wins as the conflict policy.

## Root cause

The page subscribed directly to an event stream and ignored stream errors. A disconnected stream did not trigger a current-state read or reconnection. The existing refresh test always injected a successful notification and therefore established only the push path. Transport state, saved file state and rendered editor state were not checked independently in the initial acceptance. Global proxy environment inheritance was an additional machine-local transport failure, separate from the stale page.

## Guardrails

- [Canvas widget tests](../../app/test/study_canvas_ui_test.dart) include a received document with no push event; the open page must catch up within five seconds. The same fixture checks automatic replacement and bounded revision-race retries.
- [Canvas implementation](../../app/lib/features/study_canvas/study_canvas.dart) checks state periodically while visible and immediately after returning to the foreground, and disposes its observer and timer with the page.
- [Folder integration tests](../../lookd/internal/datasync/folder_test.go) verify whole-canvas convergence and recovery bytes, following the [selected save policy](../decisions/0022-whole-canvas-last-save-wins.md).
