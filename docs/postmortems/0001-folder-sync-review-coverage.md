# Folder-sync review missed alternate write paths

Artifact-Version: 1

## Executive summary

Repeated pre-merge reviews found data-integrity defects after earlier review summaries had reported the fixes as complete. The reviews followed individual patches and healthy fixtures rather than tracing the same invariants through automatic import, manual recovery, private indexes and the running assistant. Passing those tests did not justify confidence in the complete synchronization flow.

## Summary

Isolated reproductions showed that a null global session index could publish session deletions, manual conflict restoration could overwrite a quiz owned by another course, and deleting a synchronized course tree could leave later rounds failing on its absent marker. A null private index could also panic. Restoring a working file followed by an acknowledgement write failure left the installed content without a refresh. These were reproduced with synthetic temporary libraries; this audit does not establish that the user suffered those losses.

## Timeline

- Earlier reviews added destination ownership, baseline retention, receive limits, portable-state transactions and native publication recovery tests.
- On 2026-11-03, reviewing invariants across entry points reproduced the private-index, recovery and deletion lifecycle failures. Regression cases failed against the pre-fix source and passed with their corresponding repairs.
- A real server fixture connected file import, reindexing, private metadata and SQLite learning state. Authenticated recovery requests exposed a guard absent from that alternate path.
- A separate Go/Node interleaving experiment remained failing: Node refreshed its metadata, Go merged an imported course session, and Node completed `setKind` using its earlier snapshot. The final JSON retained the local session but lost the imported entry. The experiment paused at the Node refresh boundary and invoked the production Go merge; it did not simulate filesystem corruption. This is an unresolved release blocker, not a passed test.

## Root cause

Ownership and error-handling rules were duplicated at different entry points. Tests of the transport could pass while the HTTP recovery path lacked the same checks. Missing files, invalid JSON objects and valid empty collections were not consistently distinguished. A server callback that refreshes installed data was exercised mainly through successful imports, leaving partial completion hidden.

The assistant and daemon independently replace the same global metadata file. Their in-process queues and locks do not form a cross-process transaction. The integrated Go fixture does not launch the assistant, and Go race detection cannot observe that lost update. Atomic replacement protects file integrity, not the relationship between a read and a later write.

The earlier review reports generalized beyond the evidence. A large integration containing multiple storage owners needs separate proof for each writer and recovery path; repeated local fixes cannot substitute for that map.

## Guardrails

- [The owning specification’s verification matrix](../specs/0023-course-folder-sync.md#verification) connects each invariant to its actual evidence boundary and states remaining release blockers.
- [Shared index and restore validation](../../lookd/internal/datasync/folder_validation.go) rejects invalid collections and applies automatic-import ownership checks to manual recovery.
- [Lifecycle regressions](../../lookd/internal/datasync/folder_lifecycle_test.go) require corrupt indexes to leave the published generation unchanged and verify deletion rounds after private-baseline migration.
- [Server integration tests](../../lookd/internal/server/folder_integration_test.go) exercise the real file-to-index composition and authenticated restoration, including stale previews, backups and acknowledgement failure after a successful replacement.
- The cross-process metadata writer protocol remains unresolved. The Draft integration must not be promoted on the strength of the passing Go-only suite; the eventual repair needs a production Go/Node interleaving regression and failure-retry evidence.
