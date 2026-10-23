# WebDAV sync keeps a shared manifest and a per-device base

## Status
Proposed
Class: feature

## Context and Problem Statement
The library and the assistant's history should follow the student across devices ([spec 0014](../specs/0014-data-sync-and-backup.md)) without a Look Studio server. Students in China commonly have 坚果云 or a self-hosted Nextcloud or AList, all of which speak WebDAV. WebDAV offers files and folders but no change feed, no reliable modification times across servers, and listing large trees is slow and rate-limited. How do devices find out what changed and settle edits made on two devices?

## Decision Drivers
- Works with any WebDAV server, including ones with request limits (坚果云).
- Never loses an edit silently; deletions must propagate, not resurrect.
- Incremental: an idle sync costs a handful of requests.

## Considered Options
- A manifest file in the folder plus a per-device base (three-way comparison by content hash).
- Listing the remote tree (PROPFIND depth infinity) and comparing modification times.
- One archive per device uploaded on every sync.
- Syncing `library.db` itself.

## Decision Outcome
Chosen option: the remote folder holds `manifest.json` with every file's size, modification time and SHA-256 (or a tombstone); each device remembers the manifest entries it last agreed with. A path that differs on one side only changed there; one that differs on both is a conflict, settled by the newer edit with the other copy kept aside, except that append-only logs merge. The manifest is replaced with `If-Match` on its ETag so two devices cannot overwrite each other's commit, and uploads enter the base only after that write succeeds. The index is never synced; it is rebuilt from the files, and the little state that lives only there (playback, bookmarks) travels as one JSON document merged record by record.

### Consequences
- Good: one GET tells a device whether anything changed; content hashes ignore servers that rewrite modification times.
- Good: deletions propagate through tombstones; nothing is deleted locally without a copy in `.sync-trash`.
- Trade-off: the first sync hashes every file; hashes are cached by size and modification time afterwards.
- Trade-off: two edits of the same note are not merged line by line; the older one is kept as a file to compare by hand.
- Trade-off: a server that ignores `If-Match` falls back to last-writer-wins for the manifest; a rerun repairs missed entries because the base is only advanced after a successful write.

## Pros and Cons of the Options
### Manifest plus per-device base
- Good: three-way comparison distinguishes edits from deletions; few requests; independent of server time stamps.
- Bad: the manifest is a single point of contention, handled with ETags and retries.

### Listing the remote tree
- Good: no extra file.
- Bad: PROPFIND of thousands of files is slow and rate-limited; modification times vary by server; cannot tell a deletion from a file another device never uploaded.

### One archive per device
- Good: trivial to implement.
- Bad: re-uploads everything; merging archives from several devices is the same problem again.

### Syncing library.db
- Good: carries every table.
- Bad: SQLite files cannot be merged; WAL files make copies inconsistent; the index already rebuilds from files.

## Links
- [Spec 0014](../specs/0014-data-sync-and-backup.md)
- [RFC 4918: HTTP Extensions for WebDAV](https://www.rfc-editor.org/rfc/rfc4918)
- [RFC 9110 §13.1.1: If-Match](https://www.rfc-editor.org/rfc/rfc9110#name-if-match)
- [golang.org/x/net/webdav (test server)](https://pkg.go.dev/golang.org/x/net/webdav)
