# Obsidian integration starts as a one-way export with standard Markdown links

## Status
Proposed
Class: feature

## Context and Problem Statement
Users want their lecture notes in Obsidian. The library is already plain Markdown with YAML front matter, but notes link through the app-only `look://` scheme, use `\( \)` math, and live next to videos and `library.db`. How should notes reach a vault, and in which link style?

## Decision Drivers
- The library stays the source of truth; edits made in Obsidian must never be lost.
- Exported notes should render in other Markdown tools too (the planned GitHub Pages backup, Notion).
- Timestamps must still lead back to the recording.
- Small first step that a later two-way sync can build on.

## Considered Options
- One-way export into a vault folder, standard relative Markdown links, `lookstudio://` deep links for timestamps.
- Point Obsidian at the library folder itself.
- Two-way sync from the start.
- Wikilinks (`[[...]]`, `![[...]]`) instead of Markdown links.

## Decision Outcome
Chosen option: one-way export with standard Markdown links and a `lookstudio://` deep link. The conversion lives in `lookd/internal/portable` so other exporters reuse it. Files edited in the vault are detected by hash and kept; the new version is written beside them.

### Consequences
- Good: no risk to the library; vault content is portable Markdown; timestamps open the app.
- Good: the converter is shared by future exporters.
- Trade-off: edits made in Obsidian do not flow back; the user merges the `(Look Studio)` copy by hand until two-way sync exists.
- Trade-off: deep links need the handler registered per platform.

## Pros and Cons of the Options
### One-way export
- Good: simple, safe, testable; works with any vault sync.
- Bad: duplicates the slides, figures and courseware the notes use; they are plain copies, because a hard link would let an edit in the vault change the library.

### Library as the vault
- Good: zero copies, edits are immediate.
- Bad: `look://` links and `\( \)` math do not render; videos, `.parsed/` and the WAL database burden indexing and vault sync; renaming a note title renames its file and breaks backlinks; the app's front matter rewrite drops properties added in Obsidian.

### Two-way sync first
- Good: edits flow both ways.
- Bad: needs a file watcher, conflict resolution, reverse link conversion and a stable note file naming change; too large before the export format is proven.

### Wikilinks
- Good: Obsidian-native, survive file moves inside Obsidian.
- Bad: not rendered by GitHub, static sites or Notion import; the owner chose standard Markdown.

## Links
- [Obsidian internal links](https://help.obsidian.md/Linking+notes+and+files/Internal+links) — both Markdown and wikilink formats are supported.
- [Obsidian properties](https://help.obsidian.md/Editing+and+formatting/Properties) — YAML front matter keys used for note metadata.
- [Spec: Obsidian export](../specs/0000-obsidian-export.md)
