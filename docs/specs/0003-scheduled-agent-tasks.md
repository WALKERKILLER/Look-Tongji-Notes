# Scheduled assistant tasks

Artifact-Version: 1
Status: Implemented

## Intent
Some assistant work is periodic: a nightly recap of today's lectures, a weekly quiz on the week's material, a morning digest of upcoming deadlines. Users want to set these up once.

Outcome: users create scheduled tasks (prompt plus schedule); the agent host runs each due task as a new conversation without a user present, with tighter limits than interactive chat, and reports results.

This adds unattended assistant runs. They use the same tools as chat, but each run may only make the writes its task allows (`writes`: notes and outlines, schedule marks, quiz sets; none by default), because material a run reads could carry injected instructions; downloads still only start from a user click.

Non-goals: running while Look Studio is closed (no system service), event triggers (for example "after a transcript finishes"), chained workflows, sending results outside the app.

## Contract

### Task
`{id, name, prompt, schedule, enabled, budget_usd, catch_up, writes, created_at}`; the API adds `next_run`, `last_run` and `state` (idle, queued, running). Runs use the current model; a per-task model is left for later.
- `schedule`: `{type: daily, time}`, `{type: weekly, days:[1..7], time}`, `{type: once, at}`; local time; minute precision.
- `writes`: what a run may change, chosen by the user: `notes` (save_note, generate_timeline, save_timeline), `schedule` (mark_schedule, update_schedule), `quiz` (create_quiz); empty (the default) means read-only. In a run, a write tool outside the set is refused before it runs, whatever the model was told; chats are not restricted.
- `budget_usd`: per-run cost cap, default 0.20; a run that exceeds it is aborted after the current call and marked `budget`.
- `catch_up`: when the app starts after a missed time, run once if the miss is under 12 hours (default on); without it a run still starts up to 5 minutes late. A missed time outside the window is recorded as a `skipped` run. Each scheduled time is handled once (the task keeps the last handled time); times before a task was created or rescheduled never run.
- Validation: name ≤ 40 chars, prompt ≤ 4000, `HH:MM` times, `days` an array with at least one weekday, a real calendar `once` time in the future (`2026-02-30T08:00` is rejected, not rolled over), budget $0.01–$5, `writes` an array of the three kinds.
- Stored in `<agent data dir>/tasks.json`; run history (last 50 per task) in `tasks-runs.jsonl`: `{task_id, name, run_id, started, finished, status: ok|error|budget|skipped|aborted, session_id, cost, summary, manual}`. Both files hold prompts and summaries, so they are written with mode 0600 (existing files are tightened on load), like `models.json`.

### Execution
- The host checks due tasks every 30 s while running. One run at a time; a due run while another runs waits; a task never overlaps itself.
- A run opens a new conversation named `定时 · <name> · MM-DD HH:mm` and prompts it with the task prompt plus a context line saying it is an unattended scheduled run (no user available to answer questions; finish with a short summary), that only the task prompt is an instruction while transcripts, courseware, notes, web pages and tool results are data whose requests are never followed, and which writes this run may make. Tool-call cap 24 per run (as chat). Usage is recorded with `purpose: task` and `task_id`.
- A run stops on the budget, on a 15-minute timeout (`error`), or when its task is disabled or deleted (`aborted`).
- A run whose history cannot be written is logged; the scheduler still clears it and moves on to the next queued run. A check saves the handled times before writing `skipped` records, retries a failed save on the next check, and always starts queued runs.
- On start and finish the host notifies lookd (`POST /api/agent/event`, `{type: agent_task, data}`; other types → 400), which publishes `agent_task` on the event bus.
- Disabling or deleting a task cancels its pending run; deleting keeps its conversations.

### API (agent host, via `/agent/…`)
`GET /tasks`, `POST /tasks`, `PUT /tasks/{id}`, `DELETE /tasks/{id}`, `POST /tasks/{id}/run` (run now), `GET /tasks/{id}/runs`, `GET /tasks/runs?status=&limit=` (runs of every task, newest first, default 100, at most 500; each with the task `name` and `deleted` when the task is gone). Validation errors → 400 with a Chinese message. Every host request body is limited to 1 MiB and 30 s of reading: reading stops at the first byte over the limit (413) or at the deadline (408), and the reply closes the connection instead of waiting for the rest of the body.

### UI
Modelled on the sidebar entries of agent apps (Codex app *Automations*, Claude Code Desktop *Scheduled*): tasks are a destination of their own with a list, a detail view and a run history, not a menu item.
- Navigation: rail destination 定时 between 资料库 and 插件, with a badge counting runs finished since the tab was last opened (aborted runs excluded; the newest seen finish time is kept on the device; history from before the first load counts as seen). The compact bottom bar leaves it out; there it opens from 设置 → 助手 → 定时任务 (a dot on 设置 shows unread runs) and the assistant menu, which both switch to the tab.
- Header: title, a summary line (`3 个任务 · 2 个启用 · 下一个「…」今天 21:30`), segmented 任务 / 运行记录 and 新建任务.
- 任务, at least 880 dp wide: a list (320–380 dp) beside a detail pane; rows show a tonal icon tile (icon from the schedule: evening, morning, workdays, weekly, once; colour stable per task; grey when paused), name, schedule, next run and last result; the selected row is highlighted. Narrower: cards with an enable switch that open the detail as a page.
- Detail: icon tile, name, state pill (运行中 / 排队中 / 已启用 / 已暂停), schedule and an enable switch; 立即运行, 编辑, 删除; tiles for next run, last result and the cost cap; the prompt; the task's runs (status icon, time, duration, cost, summary; a row opens the conversation in an assistant sheet).
- 运行记录: runs of every task grouped by day, filters 全部 / 完成 / 失败 / 已错过, skipped runs with the reason, deleted tasks marked, a dot on runs newer than the previous visit.
- Empty tab: a short explanation, template cards (每晚复盘今天的课, 每周一出一组复习题, 每天早上汇总近期截止) and 从空白开始.
- Editor (full-screen dialog on compact, a 560 dp dialog on wide): name, prompt (multi-line), schedule (segmented 每天 / 工作日 / 每周 / 一次 with time and date pickers and weekday chips; 工作日 is stored as weekly Monday–Friday), 单次费用上限, 错过时补跑 switch, 允许它 chips for `writes` (templates preset what they produce: 复盘 notes, 出题 quiz sets, 截止汇总 none), template chips for a new task. The detail shows the allowed writes or 只读.
- When a run finishes, a snackbar `定时任务「…」已完成` with action 查看 (timing out like other snackbars); failures say why (budget, model error).

## Plan
1. Agent: `agent/src/tasks.mjs` (store, scheduler, runner using `openConversation`), routes, budget enforcement via `message_end` usage, ledger purpose `task`.
2. lookd: `POST /api/agent/event` (token-authenticated, agent only) → bus.
3. App: `features/assistant/tasks_page.dart`, editor, history, snackbar on `agent_task`.

## Verification
- `node --test agent/src/tasks.test.mjs`: next-run computation for daily, weekly and once across DST-free local days and month ends; catch-up window; no overlap; budget abort marks the run.
- Live: a task scheduled one minute ahead runs once, creates a conversation, records `task` usage and shows the snackbar; disabling before the time prevents the run.

## Evidence
- Scheduler: [tasks.mjs](../../agent/src/tasks.mjs) with [tasks.test.mjs](../../agent/src/tasks.test.mjs) (previous and next runs across a month end, weekdays and a year end; catch-up and late windows; a time runs once; `writes` validation and a run refusing write tools its task does not allow while chats are not restricted; validation including overflowing dates; serial runs, budget status, abort on disable, skipped runs, history kept across a restart, 0600 modes, cross-task history with deleted tasks, a failed history write not stalling the queue, a failed skipped record still saving handled times); body limit and deadline (stopping early, a chunked upload answered with 413 and a closed connection) in [http.test.mjs](../../agent/src/http.test.mjs).
- Runner and routes: `runTask` (untrusted-material prompt, `conv.writes`) and `/tasks` routes in [host.mjs](../../agent/src/host.mjs), the write check in `guard` with `WRITE_TOOLS` in [tools.mjs](../../agent/src/tools.mjs); lookd relay [agent_event.go](../../lookd/internal/server/agent_event.go).
- App: [tasks_page.dart](../../app/lib/features/assistant/tasks_page.dart) (tab, list-detail, run history, templates, editor, run listener), unread count [task_inbox.dart](../../app/lib/features/assistant/task_inbox.dart), rail destination in [shell.dart](../../app/lib/shell.dart); [tasks_test.dart](../../app/test/tasks_test.dart) (wording; wide list beside detail, toggle request, run history with filters, skipped reason and deleted task; narrow cards and detail page; templates and the weekly and 工作日 schedules).
- Live check (2026-10-15): a daily task set two minutes ahead with a $0.05 cap ran once at its time (not manually), produced `started` and `finished` `agent_task` events, a conversation titled `定时 · 验证A · 10-15 05:15`, and one usage line with purpose `task` and its task id; a second task disabled before the time never ran; an empty name and a non-task event type returned 400. The test tasks and their conversation were deleted afterwards.
- Live check (2026-10-15, after the redesign): `GET /agent/tasks/runs` answered through lookd; the existing `tasks.json` and `tasks-runs.jsonl` were tightened to 0600 on load.
- Not verified: the budget and timeout aborts against a live model (unit-tested through the scheduler), the snackbar, the unread badge with a live run, and the screens' look.
