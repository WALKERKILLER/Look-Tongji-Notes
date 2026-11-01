# Native stylus prediction as disposable preview

## Status

Accepted
Class: architecture

## Context and Problem Statement

The canvas uses Flutter pointer events and portable ink records on desktop and Android. Android stylus hardware can supply predicted points and button events, but persisting predictions would change handwriting after synchronization and tying the document to a vendor canvas would break portability.

## Decision Drivers

- Keep actual ink, undo, shape recognition and synchronization independent of hardware prediction.
- Use supported SDK entry points with a working fallback on other Android devices.
- Bound native-to-Dart traffic and discard stale or incorrectly transformed preview frames.

## Considered Options

- Replace the canvas with a Huawei handwriting view.
- Use only Flutter pointer events and no prediction.
- Attach an optional native prediction bridge to the existing canvas.

## Decision Outcome

Use an optional native bridge. Android records real MotionEvents with AndroidX Input 1.0.0 and, when available, the official Huawei Pencil Engine 11.1.0.300 queue. Huawei produces the preferred prediction; empty results or runtime failures fall back to AndroidX. An optional manifest library declaration comes from the Huawei artifact; vendor availability is checked before construction. No Notein libraries or implementation code are included.

Predictions are coalesced to display callbacks, bounded in time and distance, and mapped from physical screen coordinates to Flutter view coordinates. Dart accepts them only for the currently drawn stylus event, using its timestamp and position. Preview points expire after 48 milliseconds and never enter the document, shape recognizer, undo history or saved data. Buttons use Android standard stylus events and Flutter's primary-stylus-button flag; unsupported proprietary gestures do not substitute arbitrary keyboard shortcuts.

## Pros and Cons of the Options

- A vendor view provides more integrated drawing functions but replaces the existing cross-platform document and rendering behavior.
- Flutter-only input minimizes dependencies but cannot use Android's device prediction APIs.
- The optional bridge preserves portable real ink and supports hardware acceleration paths. It adds a coordinate/lifecycle boundary, two pinned SDK dependencies and device validation obligations; prediction does not remove Flutter rendering latency.

## Links

- [AndroidX Input releases](https://developer.android.com/jetpack/androidx/releases/input)
- [Android MotionEventPredictor API](https://developer.android.com/reference/androidx/input/motionprediction/MotionEventPredictor)
- [Android advanced stylus features](https://developer.android.com/develop/ui/views/touch-and-input/stylus-input/advanced-stylus-features)
- [Huawei Pencil Engine](https://developer.huawei.com/consumer/cn/hms/huawei-pencilengine/)
- [Official Huawei artifact metadata](https://developer.huawei.com/repo/com/huawei/stylus/penengine/11.1.0.300/penengine-11.1.0.300.pom)
- [Drawing controls reference](../drawing-controls.md)
