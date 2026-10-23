# Notion sync goes through a user-created internal integration and Markdown page content

## Status
Proposed
Class: feature

## Context and Problem Statement
Users want the library in Notion as well as Obsidian ([decision 0010](0010-obsidian-one-way-export.md)). Notion has no local files to write: content goes through its API, which needs authorization, has rate limits, and lets the user edit pages we created. How does Look Studio authorize, what does it write, and how does it avoid overwriting the user's edits?

## Decision Drivers
- No server of our own: a desktop app cannot keep an OAuth client secret.
- The user's edits in Notion must never be lost.
- Cheap routine syncs: Notion allows about three requests per second.

## Considered Options
- Internal integration token pasted by the user; page content as enhanced Markdown (`/v1/pages/{id}/markdown`).
- Public OAuth integration.
- Block-level sync through the blocks API.
- Notion's Markdown import of the Obsidian export.

## Decision Outcome
Chosen option: an internal integration the user creates and shares a page with, writing whole pages as Markdown. Every page the sync creates is recorded with the hash of what was written and of what Notion stored; a page whose stored Markdown changed since is left alone. Containers are never rewritten or trashed, so the user can add their own pages under them.

### Consequences
- Good: no backend or client secret; access is limited to the page the user shares.
- Good: unchanged pages cost no requests; edits are detected without diffing blocks.
- Trade-off: the user creates the integration by hand (guided in the app).
- Trade-off: timestamps cannot link back into the app, and images and courseware are not uploaded.

## Pros and Cons of the Options
### Internal integration with Markdown pages
- Good: works from a desktop app alone; one request writes a whole page; hashes of the stored Markdown detect edits.
- Bad: setup takes a few manual steps in Notion.

### Public OAuth integration
- Good: one-click authorization.
- Bad: needs a client secret and a redirect endpoint we would have to host.

### Block-level sync
- Good: finer updates, could merge edits.
- Bad: many requests per page under a three-per-second limit; block diffing is far more code.

### Notion's Markdown import
- Good: nothing to build.
- Bad: manual and one-off; every import duplicates pages.

## Links
- [Spec 0013](../specs/0013-notion-sync.md)
- [Decision 0010](0010-obsidian-one-way-export.md)
- [Notion API: working with Markdown content](https://developers.notion.com/guides/data-apis/working-with-markdown-content)
