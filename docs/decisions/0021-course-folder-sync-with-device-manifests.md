# Course folder sync uses immutable objects and device manifests

## Status
Accepted
Class: architecture

## Context and Problem Statement

Syncthing transports files between the user's personal devices. Library indexes and device credentials cannot be shared, and independently updated metadata and file payloads may arrive in either order.

## Decision Drivers

- Reuse Syncthing and keep each application's local library usable offline.
- Preserve concurrent edits and detect incomplete transfers.
- Support Android document providers without exposing arbitrary filesystem access.

## Considered Options

- Synchronize the working library and SQLite database directly.
- Publish a shared mutable manifest and mutable file paths.
- Publish immutable content objects with one versioned manifest per device.

## Decision Outcome

Use immutable SHA-256 objects and per-device manifests with vector clocks. Only selected course data is published. Go owns merge rules and materializes validated files into each working library. Android supplies the same storage operations through a directory-scoped native bridge. Syncthing handles transport, with no new NAS collaboration server.

## Pros and Cons of the Options

Direct database sync cannot merge SQLite transactions. Mutable files can race a shared manifest or overwrite independently published edits. Immutable objects require a transport cache but allow integrity validation and preservation of conflicting versions without coordination between devices; garbage collection is deliberately excluded from the pilot.

## Links

- [Approved contract](../specs/0023-course-folder-sync.md)
- [Syncthing synchronization and conflicts](https://docs.syncthing.net/users/syncing.html)
- [Android directory access](https://developer.android.com/training/data-storage/shared/documents-files)
