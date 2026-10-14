# Scheduled assistant tasks

Artifact-Version: 1
Status: Implemented

## Intent
Some assistant work is periodic: a nightly recap of today's lectures, a weekly quiz on the week's material, a morning digest of upcoming deadlines. Users want to set these up once.

Outcome: users create scheduled tasks (prompt plus schedule); the agent host runs each due task as a new conversation without a user present, with tighter limits than interactive chat, and reports results.

This adds unattended assistant runs. They use the same tools and write boundary as chat (notes, schedule marks, outlines, quiz sets); downloads still only start from a user click.

Non-goals: running while Look Studio is closed (no system service), event triggers (for example "after a transcript finishes"), chained workflows, sending results outside the app.

## Contract

### Task
`{id, name, prompt, schedule, enabled, budget_usd, catch_up, created_at}`; the API adds `next_run`, `last_run` and `state` (idle, queued, running). Runs use the current model; a per-task model is left for later.
- `schedule`: `{type: daily, time}`, `{type: weekly, days:[1..7], time}`, `{type: once, at}`; local time; minute precision.
- `budget_usd`: per-run cost cap, default 0.20; a run that exceeds it is aborted after the current call and marked `budget`.
- `catch_up`: when the app starts after a missed time, run once if the miss is under 12 hours (default on); without it a run still starts up to 5 minutes late. A missed time outside the window is recorded as a `skipped` run. Each scheduled time is handled once (the task keeps the last handled time); times before a task was created or rescheduled never run.
- Validation: name ≤ 40 chars, prompt ≤ 4000, `HH:MM` times, at least one weekday, a future `once` time, budget $0.01–$5.
- Stored in `<agent data dir>/tasks.json`; run history (last 50 per task) in `tasks-runs.jsonl`: `{task_id, run_id, started, finished, status: ok|error|budget|skipped|aborted, session_id, cost, summary}`.

### Execution
- The host checks due tasks every 30 s while running. One run at a time; a due run while another runs waits; a task never overlaps itself.
- A run opens a new conversation named `定时 · <name> · MM-DD HH:mm` and prompts it with the task prompt plus a context line saying it is an unattended scheduled run (no user available to answer questions; finish with a short summary). Tool-call cap 24 per run (as chat). Usage is recorded with `purpose: task` and `task_id`.
- A run stops on the budget, on a 15-minute timeout (`error`), or when its task is disabled or deleted (`aborted`).
- On start and finish the host notifies lookd (`POST /api/agent/event`, `{type: agent_task, data}`; other types → 400), which publishes `agent_task` on the event bus.
- Disabling or deleting a task cancels its pending run; deleting keeps its conversations.

### API (agent host, via `/agent/…`)
`GET /tasks`, `POST /tasks`, `PUT /tasks/{id}`, `DELETE /tasks/{id}`, `POST /tasks/{id}/run` (run now), `GET /tasks/{id}/runs`. Validation errors → 400 with a Chinese message.

### UI
- 助手 → 定时任务 (assistant panel menu, and 设置 → 助手): a list with name, next run in words (`明天 21:30`), last status and cost, and an enable switch.
- Editor (full-screen dialog on compact, a 560 dp dialog on wide): name, prompt (multi-line), schedule (segmented 每天 / 每周 / 一次 with time and date pickers and weekday chips), 单次费用上限, 错过时补跑 switch. Templates offered as suggestion chips: 每晚复盘今天的课, 每周一出一组复习题, 每天早上汇总近期截止.
- Run history: status icon + label, start time, duration, cost, summary; a row opens the conversation in an assistant sheet. The detail page also has 立即运行, 编辑 and 删除.
- When a run finishes, a snackbar `定时任务「…」已完成` with action 查看; failures say why (budget, model error).

## Plan
1. Agent: `agent/src/tasks.mjs` (store, scheduler, runner using `openConversation`), routes, budget enforcement via `message_end` usage, ledger purpose `task`.
2. lookd: `POST /api/agent/event` (token-authenticated, agent only) → bus.
3. App: `features/assistant/tasks_page.dart`, editor, history, snackbar on `agent_task`.

## Verification
- `node --test agent/src/tasks.test.mjs`: next-run computation for daily, weekly and once across DST-free local days and month ends; catch-up window; no overlap; budget abort marks the run.
- Live: a task scheduled one minute ahead runs once, creates a conversation, records `task` usage and shows the snackbar; disabling before the time prevents the run.

## Evidence
- Scheduler: [tasks.mjs](../../agent/src/tasks.mjs) with [tasks.test.mjs](../../agent/src/tasks.test.mjs) (previous and next runs across a month end, weekdays and a year end; catch-up and late windows; a time runs once; validation; serial runs, budget status, abort on disable, skipped runs, history kept across a restart).
- Runner and routes: `runTask` and `/tasks` routes in [host.mjs](../../agent/src/host.mjs); lookd relay [agent_event.go](../../lookd/internal/server/agent_event.go).
- App: [tasks_page.dart](../../app/lib/features/assistant/tasks_page.dart) (list, detail, editor, run listener; entries in the assistant menu and 设置 → 助手), [tasks_test.dart](../../app/test/tasks_test.dart) (wording, list, toggle request, editor from a template).
- Live check (2026-10-15): a daily task set two minutes ahead with a $0.05 cap ran once at its time (not manually), produced `started` and `finished` `agent_task` events, a conversation titled `定时 · 验证A · 10-15 05:15`, and one usage line with purpose `task` and its task id; a second task disabled before the time never ran; an empty name and a non-task event type returned 400. The test tasks and their conversation were deleted afterwards.
- Not verified: the budget and timeout aborts against a live model (unit-tested through the scheduler), the snackbar and the screens' look.
