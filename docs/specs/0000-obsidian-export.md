# Obsidian export

Artifact-Version: 1
Status: Approved

## Intent

Students who keep their knowledge base in Obsidian want their Look Studio notes, transcripts and outlines there, readable without the app and linking back to the recording. Scope of this contract: a one-way export from the course library into a folder of an Obsidian vault, refreshed on demand or automatically, plus a `lookstudio://` deep link that opens the app at a lecture moment. Non-goals: importing edits made in Obsidian back into the library (a later contract), Notion, wikilinks, exporting videos.

Constraints: the library stays the source of truth; nothing the user wrote in the vault is overwritten or deleted; the assistant gains no new write capability.

## Contract

- `POST /api/library/obsidian` with `{"vault": <absolute path>, "folder": <relative folder, default "LookStudio">}`; an empty `vault` uses the saved settings. Rejects (400) a relative or missing vault, a folder that is absolute or leaves the vault, and any target that overlaps the library root. Returns `{root, written, unchanged, removed, conflicts[], vault}`; `vault` tells whether the target holds `.obsidian/`.
- Settings `obsidian.vault`, `obsidian.folder`, `obsidian.auto`. With `obsidian.auto`, saving or deleting a note triggers an export about 3 s later (bursts coalesce) and publishes SSE `obsidian_exported` `{result, error?}`.
- Layout under `<vault>/<folder>/`: `课程库.md`, the one index (per course: details, lectures with links to their transcript and notes, course notes, schedule), and one folder per course named like its library folder, holding only `笔记/` and `转写稿/`. `笔记/` has one folder per lecture named like the lecture folder (so dated and sorted by time) with that lecture's notes as `<title>.md` and an `附件/` folder for the slides, figures and courseware files they link to (copied, never hard-linked, so vault edits cannot reach the library), plus `课程笔记/` for notes of the whole course. `转写稿/<lecture>.md` holds the lecture properties, outline, notes, schedule and courseware, then the transcript. Loose notes go to `未归类笔记/` only when there are any.
- Notes carry Obsidian properties `title, course, lecture, date, source, look_note_id, look_lecture_id, look_course_id, updated, tags`. A title clash in one folder gives the newer note a ` (<last 6 id chars>)` suffix.
- Body conversion (`lookd/internal/portable`): `look://lecture|seek` and bare `[mm:ss]` / `[a]–[b]` → `lookstudio://lecture/<id>?t=<s>`; `look://slide`, `look://file`, `look://courseware` → relative standard Markdown links to the copied file, or just the label when the file is not local; `\(…\)` → `$…$`, `\[…\]` → `$$…$$`, bare math environments wrapped in `$$`, `$ x $` padding removed when clearly math. Code is untouched.
- Safety: `.lookstudio-export.json` records the content hash of every file the export wrote; files are written through uniquely named temporary files and renamed into place. A file that differs from its record (edited in Obsidian, or never written by the export) is kept and listed in `conflicts`; for a document the new version is written beside it as `<name> (Look Studio).md` (then `(Look Studio 2)`, … when that copy was edited too). Files from a previous export that are no longer produced are deleted only when unchanged since; empty folders are pruned. Targets are compared by real path (symbolic links resolved) and the export stops with an error at a symbolic link inside the export folder. A failed write fails the export and keeps the previous manifest.
- Deep link: `lookstudio://lecture/<id>[?t=<s>]` opens the player at that moment. Linux: single instance, URIs forwarded to the running app over GApplication; the user registers the handler from settings (writes a user `.desktop` entry and runs `xdg-mime`). Android: VIEW intent filter. The in-app renderer accepts `lookstudio://` like `look://`.
- Also fixed: rebuilding the index keeps notes in the top-level `notes/`.

## Plan

1. `lookd/internal/portable` converter; `library.ExportObsidian` and `ObsidianRoot`; route and auto export in `lookd/internal/server`.
2. App: settings section (vault, folder, auto, export now, register links), `look/links` method channel, Linux runner single-instance `open`, Android intent filter.
3. Docs: overview, architecture, library README; decision [0005](../decisions/0005-obsidian-one-way-export.md).

## Verification

- `cd lookd && go test -count=1 -race ./...` — `internal/portable` conversion table; `internal/library` `TestExportObsidian` (layout, links, idempotence, conflict copies, attachment edits, stale cleanup), `TestObsidianRootRejectsOverlap` (incl. symlinks), `TestExportObsidianStopsAtSymlink`, `TestReindexKeepsLooseNotes`.
- `cd app && flutter analyze --no-fatal-infos && flutter test`.
- Manual: export into a real vault and open it in Obsidian — properties show, slides render, math renders, clicking a timestamp opens Look Studio at that moment with the app already running and not running; edit a note in Obsidian, export again, check the `(Look Studio)` copy.

## Evidence

Pending.
