# Notion sync

Artifact-Version: 1
Status: Approved

## Intent

Students who keep their notes in Notion want the Look Studio library there: one page per course and lecture, with notes and transcripts below, kept current as notes change. Scope of this contract: a one-way sync from the course library into a Notion page the user picks, through an internal integration the user creates. Non-goals: importing edits made in Notion, uploading images, slides or courseware, public OAuth, databases.

Constraints: the library stays the source of truth; nothing the user wrote in Notion is overwritten or deleted; the integration token stays inside lookd; the assistant gains no new write capability.

## Contract

- API version `2026-03-11` (`Notion-Version` header). Requests are paced (about 3 per second) and retried on network errors, 429 (honouring `Retry-After`) and 5xx; 401 means the token is invalid or revoked.
- `GET /api/notion` → status `{connected, bot{name, workspace}, token_last4, parent{id,title,url,icon}?, root_url?, auto, pages, running, progress{done,total}?, last?}`; `last` is `{at, created, updated, unchanged, trashed, conflicts[], errors[], error?}`. The token is never returned, only its last four characters.
- `POST /api/notion/connect {token}` checks the token with `GET /v1/users/me` and stores it sealed with the device key in `<data>/notion.json`; connecting to a different workspace forgets the previous page tree. `POST /api/notion/disconnect` deletes the file; synced pages stay in Notion.
- `GET /api/notion/pages[?q=]` lists the pages shared with the integration (`POST /v1/search`). `PUT /api/notion {parent?, auto?}` sets the parent page (an id or a page URL) and automatic sync; a new parent forgets the page tree, so the next sync builds a fresh one there and leaves the old pages untouched.
- `POST /api/notion/sync {full}` starts a sync in the background (409 when not connected or without a parent) and returns the status. At most one sync runs; SSE `notion_progress {done,total}` while it runs, `notion_synced <result>` at the end, `notion_changed` after connect, disconnect and configuration changes. With `auto`, saving or deleting a note syncs about one minute later (bursts coalesce).
- Tree (from `library.KnowledgeDocs`): a root page `Look Studio 课程库` under the parent; a container page per course with content (teacher, college, term) and per lecture with notes or a transcript (date, lecturer, room, duration); leaves for notes (`*课程 · 节次 · 更新于 YYYY-MM-DD*` then the body) and transcripts (`转写稿 · <lecture>`: outline, schedule, courseware names, transcript). Course notes sit under the course, loose notes under the root. Bodies go through `portable` with `NoDeepLinks`: Look links become plain labels, timestamps stay text (`` `mm:ss` `` in outlines), math becomes `$…$`/`$$…$$`; Notion rejects non-HTTP link targets.
- Ownership: `notion.json` records every page the sync created with the hash of what it wrote and the hash of the Markdown Notion returned right after the write. Containers are created once and only retitled. A leaf is rewritten (`PATCH /v1/pages/{id}/markdown` `replace_content`, never deleting child pages) only when its source changed and Notion's current Markdown still matches the recorded one; otherwise it is kept and listed in `conflicts`. Leaves no longer produced are moved to the trash only when unedited; containers are never trashed. A routine sync makes no request for unchanged pages; a full sync checks that every recorded page still exists and recreates deleted ones together with their descendants.
- App: 设置 → 知识库 shows Obsidian and Notion with their marks; the Notion page guides creating the integration and sharing a page, picks the parent, toggles automatic sync, starts a sync or a full check, and shows progress, the last result, conflicts and errors.

## Plan

1. `lookd/internal/notion` (client, service), `library.KnowledgeDocs`, `portable.Converter.NoDeepLinks`, routes in `lookd/internal/server/notion.go`.
2. App: settings regrouped into a list-detail layout with search; 知识库 category; Notion page; brand marks.
3. Docs: overview, architecture, testing; decision [0011](../decisions/0011-notion-sync-through-an-internal-integration.md).

## Verification

- `cd lookd && go test -count=1 -race ./...` — `internal/notion` against a fake Notion server (`TestConnectConfigureAndSync`: tree, idempotence, edited pages kept, stale leaves trashed; `TestRecreatesDeletedPages`; `TestNormalizeID`), `internal/library` `TestKnowledgeDocs`, `internal/portable` `TestNoDeepLinks`.
- `cd app && flutter analyze && flutter test` — `test/notion_test.dart` (connect, page picker, sync progress and result).
- Manual: connect a test workspace, share a page, sync, edit a note page in Notion and sync again (kept and listed), delete a lecture page and run a full check (recreated).

## Evidence

Pending.
