# Course folder sync uses immutable objects and device manifests

## Status
Accepted
Class: architecture

## Context and Problem Statement

A shared folder transports files between the user's personal devices. At the time of this decision it was a Syncthing-managed folder; the Amendment below replaces that with direct WebDAV. Library indexes and device credentials cannot be shared, and independently updated metadata and file payloads may arrive in either order.

## Decision Drivers

- Reuse one shared folder and keep each application's local library usable offline.
- Preserve concurrent edits and detect incomplete transfers.
- Support Android document providers without exposing arbitrary filesystem access.

## Considered Options

- Synchronize the working library and SQLite database directly.
- Publish a shared mutable manifest and mutable file paths.
- Publish immutable content objects with one versioned manifest per device.

## Decision Outcome

Use immutable SHA-256 objects and per-device manifests with vector clocks. Only selected course data is published. Go owns merge rules and materializes validated files into each working library. Android supplies the same storage operations through a directory-scoped native bridge. The transport is a plain folder of objects, so it is independent of how the folder is replicated and needs no collaboration server.

## Pros and Cons of the Options

Direct database sync cannot merge SQLite transactions. Mutable files can race a shared manifest or overwrite independently published edits. Immutable objects require a transport cache but allow integrity validation and preservation of conflicting versions without coordination between devices; garbage collection is deliberately excluded from the pilot.

## Links

- [Approved contract](../specs/0023-course-folder-sync.md)
- [WebDAV (RFC 4918)](https://www.rfc-editor.org/rfc/rfc4918)
- [Android directory access](https://developer.android.com/training/data-storage/shared/documents-files)

## Amendment: direct WebDAV, no second sync client

On 2026-11-03 the user rejected running a second synchronisation client next to Studio. The NAS folder is now read and written directly over WebDAV by `datasync.Client`: the settings page takes the address, account, app password and folder, `List` is a `PROPFIND` with `Depth: 1`, and the object/manifest protocol above is unchanged. The local-folder and Android SAF paths stay as fallbacks. A device's sync identity is the address plus folder, so pointing it elsewhere starts from an empty baseline rather than inheriting agreed state. The device-manifest guarantees, including the known cross-process writer blocker on `sessions-meta.json`, are unaffected.
