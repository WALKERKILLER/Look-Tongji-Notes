# Architecture

This document is the ordered map of the repository: composition, modules, seams, and extension points. Read it before changing structure. Per-module detail lives in the owning module's own documentation; durable decision rationale lives in [docs/decisions/](../docs/decisions/).

Feature behavior (login, downloads, transcription, notes, schedule, outline, courseware) is described in [overview.md](overview.md); this document owns structure.

## Composition

```text
app (Flutter) ── HTTP + SSE on 127.0.0.1, per-run token ──▶ lookd (Go daemon)
                                                             ├─ supervises agent (Node.js, Pi SDK) and proxies /agent/*
                                                             ├─ Tongji IAM + Look API, cloud ASR channels, MinerU
                                                             └─ ~/LookStudio library files + library.db index
agent ── HTTP with LOOKD_URL / LOOKD_TOKEN ──▶ lookd (its only data source)
```

The app starts lookd ([lookd_service.dart](../app/lib/core/lookd_service.dart) searches `LOOKD_BIN`/`LOOK_AGENT`/`LOOK_NODE`, then next to the executable, then the development tree); lookd starts the agent.

## Modules

| Path | Owns |
| --- | --- |
| `lookd/cmd/lookd` | Daemon entry point |
| `lookd/cmd/logintest`, `lookd/cmd/probe` | Manual tools against the live service (`LOOK_USER`/`LOOK_PASS`); not run in CI |
| `lookd/internal/server` | HTTP API for the app and the agent — the main seam |
| `lookd/internal/tongji` | IAM login, JWT renewal, sealed session, Look API client |
| `lookd/internal/jobs` | Download, transcription and parse jobs with per-kind concurrency and persistence |
| `lookd/internal/dl` | Segmented, resumable downloader |
| `lookd/internal/asr` | Cloud ASR channels (bcut, JianYing), chunk pool, cooldowns and retries |
| `lookd/internal/mineru` | MinerU courseware parsing client and sealed token |
| `lookd/internal/library` | On-disk library layout, courseware search, schedule, timeline, README for AI tools |
| `lookd/internal/portable` | Converts library Markdown (`look://` links, timestamps, math) to plain Markdown for exports |
| `lookd/internal/store` | SQLite schema and FTS index ([schema.sql](../lookd/internal/store/schema.sql)); rebuildable from library files |
| `lookd/internal/events` | SSE event fan-out |
| `lookd/internal/agent` | Supervises the Node agent host and proxies `/agent/*` |
| `agent/src/host.mjs` | Agent host: HTTP endpoints, system prompt, sessions |
| `agent/src/tools.mjs` | Tool groups, `find_tools`, note playbook, write guards |
| `agent/src/models.mjs`, `catalog.mjs` | Providers, model preferences, models.dev metadata |
| `agent/src/timeline.mjs`, `vision.mjs`, `lookd.mjs` | Outline generation, image bridge for text-only models, lookd client |
| `app/lib/core` | lookd client (`api.dart`), daemon discovery and startup, app state, models |
| `app/lib/features/<area>` | Screens: assistant, courses, courseware, downloads, home, library, login, player, profile, schedule, settings |
| `app/lib/widgets` | Shared widgets, including the Markdown/LaTeX renderer and reader |
| `app/lib/theme` | Material 3 theme and spacing/motion tokens |

## Seams

- **lookd HTTP API**: routes in `lookd/internal/server`; clients in [api.dart](../app/lib/core/api.dart) and [lookd.mjs](../agent/src/lookd.mjs).
- **`look://` links**: parsed by `LookRef` in [look_markdown.dart](../app/lib/widgets/look_markdown.dart), produced by agent tools, documented for AI tools in [readme.go](../lookd/internal/library/readme.go).
- **Markdown rendering**: every Markdown surface uses `LookMarkdown` in [look_markdown.dart](../app/lib/widgets/look_markdown.dart).
- **Library on disk**: layout owned by `lookd/internal/library`; `library.db` is an index over it, not the source of truth.
- **`lookstudio://` deep links**: produced by `lookd/internal/portable` for exported Markdown; received by the app over the `look/links` method channel (Linux runner, Android `MainActivity`).
- **Release package**: [release.yml](../.github/workflows/release.yml) places `lookd` and `agent/` next to the app executable, matching the discovery order above.

## Conventions

- New behavior goes on documented extension points; a decision record is required when a core-flow change chooses among meaningful alternatives.
- Explicit > implicit at boundaries: defaulting is an explicit step in the owning implementation, never a hidden fallback.
- Long-running work in lookd takes a `context.Context` and stops on cancellation; asynchronous Flutter callbacks check `mounted` before touching `BuildContext`.
- UI spacing, shape and motion come from `app/lib/theme/tokens.dart` rather than literals.

## Change procedure

1. Trace the current owners of the flow you change.
2. For a risk-boundary change, obtain an Approved spec in [docs/specs/](../docs/specs/).
3. Record durable design choices in [docs/decisions/](../docs/decisions/) when genuine alternatives exist.
4. Update this document and the owning module docs in the same change.
5. Run the gates; add the smallest sufficient evidence for the behavior and risk, not tests for line count.
