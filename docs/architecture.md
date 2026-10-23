# Architecture

This document is the ordered map of the repository: composition, modules, seams, and extension points. Read it before changing structure. Per-module detail lives in the owning module's own documentation; durable decision rationale lives in [docs/decisions/](../docs/decisions/).

Feature behavior (login, downloads, transcription, notes, schedule, outline, courseware) is described in [overview.md](overview.md); this document owns structure.

## Composition

```text
app (Flutter) ── HTTP + SSE on 127.0.0.1, per-run token ──▶ lookd (Go daemon)
                                                             ├─ supervises agent (Node.js, Pi SDK) and proxies /agent/*
                                                             ├─ Tongji IAM + Look API, cloud and local ASR channels, MinerU
                                                             ├─ Canvas (Tongji IAM / Fudan UIS sign-in or token)
                                                             ├─ watcher: adaptive polling → notification feed → SSE
                                                             └─ ~/LookStudio library files + library.db index
agent ── HTTP with LOOKD_URL / LOOKD_TOKEN ──▶ lookd (its only data source)
```

The app starts lookd ([lookd_service.dart](../app/lib/core/lookd_service.dart) searches `LOOKD_BIN`/`LOOK_AGENT`/`LOOK_NODE`, then next to the executable, then the development tree); lookd starts the agent. On Android the same lookd and agent run in an Ubuntu workspace started with proot from the APK's native library folder ([workspace.dart](../app/lib/core/workspace.dart), [decision 0013](decisions/0013-android-runs-lookd-in-a-proot-ubuntu-workspace.md), [draft spec](specs/draft-android-app.md)).

## Modules

| Path | Owns |
| --- | --- |
| `lookd/cmd/lookd` | Daemon entry point |
| `lookd/cmd/logintest`, `lookd/cmd/probe` | Manual tools against the live service (`LOOK_USER`/`LOOK_PASS`); not run in CI |
| `lookd/internal/server` | HTTP API for the app and the agent — the main seam; the lecture watcher (`watch.go`, [spec 0010](specs/0010-live-refresh.md)); school profiles, Canvas sign-in adapters and the schedule merge (`canvas.go`, [spec 0011](specs/0011-canvas-and-schools.md)) |
| `lookd/internal/tongji` | IAM login, JWT renewal, sealed session, Look API client |
| `lookd/internal/jobs` | Download, transcription and parse jobs with per-kind concurrency and persistence |
| `lookd/internal/dl` | Segmented, resumable downloader |
| `lookd/internal/asr` | Cloud ASR channels (bcut, JianYing), chunk pool with the optional `local` channel, cooldowns and retries |
| `lookd/internal/localasr` | Local recognition: model catalog with digests and benchmarks, verified resumable installs, sherpa-onnx runner and punctuation realignment ([spec 0009](specs/0009-local-asr-models.md), [decision 0007](decisions/0007-sherpa-onnx-command-line-for-local-asr.md)) |
| `lookd/internal/notify` | In-app notification feed (`notifications.json`), deduplicated by id and published as `notification` events |
| `lookd/internal/canvas` | Canvas REST client and service: session or token sign-in with renewal and token rotation, sync cache, notifications, course links, files ([decision 0009](decisions/0009-canvas-through-the-school-sso-session.md)) |
| `lookd/internal/fudan` | Fudan UIS sign-in and WebVPN addresses |
| `lookd/internal/mineru` | MinerU courseware parsing client and sealed token |
| `lookd/internal/library` | On-disk library layout, courseware search, schedule, timeline, README for AI tools |
| `lookd/internal/portable` | Converts library Markdown (`look://` links, timestamps, math) to plain Markdown for exports |
| `lookd/internal/notion` | Notion API client (pacing, retries) and the one-way sync of `library.KnowledgeDocs` with edit detection ([spec 0013](specs/0013-notion-sync.md), [decision 0011](decisions/0011-notion-sync-through-an-internal-integration.md)) |
| `lookd/internal/datasync` | Backup archives, a WebDAV client and the three-way sync of the library and the assistant's portable data ([spec 0014](specs/0014-data-sync-and-backup.md), [decision 0012](decisions/0012-webdav-sync-with-a-shared-manifest.md)) |
| `lookd/internal/store` | SQLite schema and FTS index ([schema.sql](../lookd/internal/store/schema.sql)); rebuildable from library files (schedule and activity via their JSON mirrors) |
| `lookd/internal/events` | SSE event fan-out |
| `lookd/internal/agent` | Supervises the Node agent host and proxies `/agent/*` |
| `lookd/internal/agentenv` | Installs Node.js and the agent's npm dependencies into the data directory and prunes what they never read at run time ([spec 0008](specs/0008-assistant-runtime-setup.md)) |
| `lookd/internal/rootfs` | Unpacks the Android workspace's Ubuntu base (`lookd unpack`), refusing entries that escape it |
| `agent/src/host.mjs` | Agent host: HTTP endpoints, system prompt, sessions |
| `agent/src/http.mjs` | Request body reading with the 1 MiB limit and 30 s deadline, HTTP error replies |
| `agent/src/tools.mjs` | Tool groups, `find_tools`, note playbook, write guards |
| `agent/src/models.mjs`, `catalog.mjs` | Providers, model preferences, models.dev metadata |
| `agent/src/timeline.mjs`, `vision.mjs`, `lookd.mjs` | Outline generation, image bridge for text-only models, lookd client |
| `agent/src/usage.mjs` | Usage ledger (`usage.jsonl`): one line per model call, summaries and call paging |
| `agent/src/practice.mjs` | Quiz grounding checks and playbook for `create_quiz` |
| `agent/src/tasks.mjs` | Scheduled tasks: validation, next-run computation, queue and run history (`tasks.json`, `tasks-runs.jsonl`) |
| `agent/src/bot.mjs` | The resident bot: identity (`bot.json`), conversation kinds (`sessions-meta.json`), proposals, consolidation scheduling and transcripts |
| `agent/src/memory.mjs` | Bot memory files: paths, limits, sensitive-value guard, hash-checked writes, prompt injection and memory tools |
| `agent/src/operate.mjs` | The bot's app operations: settings registry, operate tools, proposal ops and undo |
| `agent/src/plugins.mjs` | Plugin host: manifests, install state (`plugins.json`), catalogs, loading plugins as Pi extensions, the permission-gated Look API, actions |
| `agent/plugins/` | Official plugins and their catalog; the [plugin author guide](../agent/plugins/README.md) |
| `app/lib/core` | lookd client (`api.dart`), daemon discovery and startup, the Android workspace and platform bridge (`workspace.dart`, `android_bridge.dart`, `background_work.dart`), app state, models, study-time tracker (`activity_tracker.dart`), installed plugins and their contributions (`plugins.dart`) |
| `app/lib/features/<area>` | Screens: activity, assistant, courses, courseware, downloads, home, library, login, notifications, player, plugins, practice, profile, schedule, settings, setup (Android workspace) |
| `app/android/workspace/prepare.py` | Fetches the pinned Termux proot build and builds `liblookd.so` and the agent's sources for the APK; [NOTICE](../app/android/workspace/NOTICE) for the shipped programs |
| `app/lib/widgets` | Shared widgets, including the Markdown/LaTeX renderer and reader, statistics charts (`charts.dart`) and the activity heatmap (`heatmap.dart`) |
| `app/lib/theme` | Material 3 theme and spacing/motion tokens |

## Seams

- **lookd HTTP API**: routes in `lookd/internal/server`; clients in [api.dart](../app/lib/core/api.dart) and [lookd.mjs](../agent/src/lookd.mjs).
- **`look://` links**: parsed by `LookRef` in [look_markdown.dart](../app/lib/widgets/look_markdown.dart), produced by agent tools, documented for AI tools in [readme.go](../lookd/internal/library/readme.go).
- **Markdown rendering**: every Markdown surface uses `LookMarkdown` in [look_markdown.dart](../app/lib/widgets/look_markdown.dart).
- **Plugins**: a plugin is a package with a `lookStudio` manifest whose agent module is loaded as a Pi extension per conversation ([decision 0005](decisions/0005-plugins-as-pi-extensions-with-declarative-views.md), [spec 0004](specs/0004-plugin-platform.md)). Its tools reach the model through `find_tools` groups `plugin:<id>`; its results are data for views the app draws (`pluginViewBuilders` in [plugin_views.dart](../app/lib/features/plugins/plugin_views.dart)); its contributions appear through `PluginMenuButton` on the note toolbar, lecture side panel, course page and schedule items, and the composer's "+" menu.
- **Bot and conversation kinds**: the agent host keeps one bot thread and course agents, told apart by `sessions-meta.json` ([decision 0006](decisions/0006-resident-bot-with-file-memory.md), [spec 0007](specs/0007-resident-bot-and-course-agents.md)). Bot memory lives in Markdown files the host injects into prompts; app operations come back as `details.app` (run by `BotOps` in [bot_ops.dart](../app/lib/features/assistant/bot_ops.dart)) or as proposals the host applies through `/agent/proposals/{id}/apply`.
- **Library on disk**: layout owned by `lookd/internal/library`; `library.db` is an index over it, not the source of truth.
- **`lookstudio://` deep links**: produced by `lookd/internal/portable` for exported Markdown; received by the app over the `look/links` method channel (Linux runner, Android `MainActivity`).
- **Release package**: [release.yml](../.github/workflows/release.yml) places `lookd` and `agent/` next to the app executable, matching the discovery order above.
- **Android guest**: every program in the workspace runs through `Workspace.guest` (proot, `env -i`, the files folder bound at its own path, native programs at `/opt/look`); paths lookd reports are valid in the app.

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
