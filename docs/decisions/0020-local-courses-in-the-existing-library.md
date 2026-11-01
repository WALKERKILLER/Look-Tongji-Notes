# Local courses in the existing library

## Status

Accepted
Class: architecture

## Context and Problem Statement

People need courses from local recordings as well as school recordings. Playback, notes, canvases and backups already use course and lesson identities in one library.

## Decision Drivers

- Reuse the existing study interfaces and backup format.
- Keep local identities out of campus requests.
- Preserve readable files as the source of truth.

## Considered Options

- Add local identities and uploaded videos to the existing course library.
- Keep a separate catalog, player and storage tree for local courses.
- Attach every video to an existing school lesson's canvas.

## Decision Outcome

Use the existing library with reserved `local-` course identities, a `local` term and normal lesson manifests. Authenticated uploads create independent lessons; the campus adapters skip local identities. No database schema migration is required. Local courses remain scoped to the selected library rather than being shared across school profiles.

## Pros and Cons of the Options

The existing library reuses study state and backup recovery, at the cost of explicit local-identity checks at remote boundaries. A separate catalog isolates those boundaries but duplicates course and lesson flows. Canvas attachments reuse import behavior but cannot represent an independent course with ordered lessons.

## Links

- [Local course contract](../specs/0022-local-courses.md)
- [Library and client architecture](../architecture.md)
