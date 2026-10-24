# The assistant acts, with an approval mode

Artifact-Version: 1
Status: Approved

## Intent
Under [spec 0007](0007-resident-bot-and-course-agents.md) the assistant could not finish most tasks it was asked for: downloads, scheduled tasks, plugin switches and download, transcription or model settings became cards for the user to apply, course agents and chats could only open pages, and a download needed every lecture id, so "下载高数第 3 到 5 周的视频" took several lookups and still ended at a button. The user's rule: what a person can do in the app, the assistant can do.

Outcome: the assistant carries out operations itself, chains the steps of a task, and every change it makes can be undone. The user picks how much it may do alone with an approval mode beside the composer, as coding agents do (Codex approval modes, Claude Code permission modes): **自动** (default) runs changes at once with 撤销; **询问** turns each change into a card the user applies. Deleting downloaded files cannot be undone, so it asks in both modes, as the app's own delete does.

This amends 0007's "Operating the app (bot)" section and the matching `AGENTS.md` rule. Everything else in 0007 (identity, memory, consolidation, proposals storage and routes, mascot) stays.

Non-goals: unchanged from 0007 (no secrets, sign-in or sign-out, library location, plugin installs). Scheduled tasks still run without operate tools. The assistant cannot change the approval mode.

## Contract
### Approval mode
- Assistant prefs gain `approval: "auto" | "ask"` (default `auto`) through the existing `PUT /agent/prefs`; any other value fails with 400. It is not in the settings registry, so `change_settings` cannot change it. Tools read it when they run, so a switch applies to the next tool call.
- The app shows the mode at the end of the composer's context line (询问 / 自动 with an icon; 自动 in the primary colour, nothing filled). Tapping opens a menu with both modes, a one-line consequence each, and a note that deleting files always asks; Shift+Tab in the composer switches it.

### Operations
Every operate tool records what it did as a proposal (`<agent data>/bot/proposals.json`, unchanged shape). In 自动 mode an operation runs, is stored `applied` with its `undo`, and returns `details.app = {op: done | prefs, label, proposal_id?}` (a chip with 撤销 when it has an undo). In 询问 mode it is stored `pending` and returns `details.proposal` (a card); nothing reaches lookd, tasks or plugins until it is applied.
- `change_settings {changes}`: every registry key, app, lookd and assistant together, with an undo restoring the previous values (an unset default model has none).
- `download {lecture_ids? | course_id + from?, to?, latest?, kinds, redownload?}`: lectures by id, or a course's recorded lectures narrowed by dates (YYYY-MM-DD, inclusive) or the latest n; at most 50. Kinds already on this device are skipped unless `redownload`; lectures without a recording are reported. Jobs are enqueued by the kinds each lecture still needs; the undo cancels only jobs that were not already queued or running.
- `list_downloads {state?, course_id?}`: counts by state and the jobs (active and failed by default) with progress and errors.
- `manage_downloads {action: pause | resume | retry | cancel, job_ids?}`: cancel's undo queues the same lectures and kinds again.
- `create_task` (was `propose_task`): created at once; the undo deletes it.
- `toggle_plugin`, `manage_course`: at once, undo restores the previous state.
- `delete_files {lecture_ids (≤ 50), kinds}`: always a card; deleting has no undo. Older cards with `lecture_id` still apply.
- `open_page`, `player`, `read_settings`, `sync_courses`: unchanged.

### Who has the tools
The bot, course agents and chats load the `operate` group with `find_tools`; loading it also loads the course group (`list_courses`, `list_lectures`, `lecture_info`). Memory stays the bot's. Scheduled tasks get neither.

### Prompt
The system prompt of the bot, course agents and chats tells the model to finish what the user asks with tools instead of offering buttons or steps, to chain lookups into one `download` call, to ask first when the scope is unclear, and how each approval mode behaves. `suggest_actions` offers next steps only.

## Plan
1. Agent: `operate.mjs` (approval-aware `act`, course and date selection, `list_downloads`, cancel and requeue, batch deletion, `create_task`), `models.mjs` (`approval` pref), `host.mjs` (operate rules for every chat kind, tools for course agents and chats), `operate.test.mjs`.
2. App: approval chip and Shift+Tab in `assistant_panel.dart`, `approval` in `assistant_controller.dart`, tool labels, bot intro copy.
3. Amend 0007 and `AGENTS.md`.

## Verification
- `node --test`: settings applied at once with their undo across app, lookd and assistant; ask mode making cards with no lookd write; download selection by dates and latest, skipping local kinds, grouping by needed kinds, undo cancelling only new jobs; cancel and its requeue undo; deletion always a card and older cards still applying; task and plugin undo; `list_downloads` output.
- Widget tests: the approval chip's menu switches the mode; the header shows the bot name in full on a phone and falls back to icons with tooltips when it does not fit.
- Live: in 自动, "下载<课程>最近两节的转写" starts the jobs in one turn and 撤销 cancels them; in 询问 the same request shows a card and starts nothing until applied; "删掉第 1 节的视频" shows a confirmation card in both modes.

## Evidence
- Agent: [operate.mjs](../../agent/src/operate.mjs) with [operate.test.mjs](../../agent/src/operate.test.mjs); the `approval` pref in [models.mjs](../../agent/src/models.mjs); operate rules and tools for every chat kind in [host.mjs](../../agent/src/host.mjs).
- App: `ApprovalModeChip` and `AssistantViewSwitch` in [assistant_panel.dart](../../app/lib/features/assistant/assistant_panel.dart), `approval` in [assistant_controller.dart](../../app/lib/features/assistant/assistant_controller.dart), with [assistant_header_test.dart](../../app/test/assistant_header_test.dart).
- Checked: the Linux release build started from this branch with its lookd and agent (2026-10-25). Not verified: the live checks above with a model, and the phone layout on a device (widget tests only).
