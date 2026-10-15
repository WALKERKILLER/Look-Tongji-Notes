# Usage ledger and cost statistics

Artifact-Version: 1
Status: Implemented

## Intent
Token and cost figures exist only per conversation (Pi session stats) and vanish when a conversation is deleted. Calls outside chat (outline generation, image descriptions, provider tests, scheduled runs) are not counted at all. Users cannot answer "what did the assistant cost this month, on which model, for what".

Outcome: every model call the agent host makes is recorded once in a durable ledger, and a Usage page shows totals, a daily trend, and breakdowns by model, purpose and conversation, plus a list of individual calls.

Non-goals: provider billing reconciliation (costs are estimates from model prices); budgets that block calls (scheduled tasks have their own cap, see the scheduled-tasks spec); request/context logs.

## Contract

### Ledger
- One JSON line per completed model call in `<agent data dir>/usage.jsonl`, appended by the agent host:
  `{ts, provider, model, purpose, session_id?, task_id?, input, output, cache_read, cache_write, cost, ms, ttft_ms?, ok}`.
  - `input` excludes cached tokens; `cost` is the Pi-computed USD estimate (0 when the model has no price); `ok=false` for errored calls, which keep whatever usage the provider reported.
  - `purpose` ∈ `chat`, `timeline`, `vision`, `title`, `test`, `task`, `quiz`.
- Every assistant message of a turn is recorded, including tool-loop round trips (counting only the last message of a turn under-reports several-fold).
- On SIGINT/SIGTERM the host waits up to 3 s for appends in flight before exiting (lookd allows 5 s), so finished calls are not lost.
- Backfill: on first start with no ledger, existing session files are scanned once and their assistant messages written as `purpose: chat` with their original timestamps; a marker line prevents a second backfill.
- Deleting a conversation does not delete its ledger lines.
- The ledger holds no prompt or response text.

### API (agent host, reached by the app as `/agent/usage…` through lookd)
- `GET /usage/summary?from=YYYY-MM-DD&to=YYYY-MM-DD` →
  `{totals:{calls, input, output, cache_read, cache_write, cost, errors}, days:[{date, input, output, cache_read, cost, calls}], by_model:[…], by_purpose:[…], by_session:[{session_id, title, …}]}`; days use local time and include zero days in range. The range spans at most 366 days (本年 in a leap year); longer → 400.
- `GET /usage/calls?before=<cursor>&limit=50` → newest-first page of ledger lines with the session title resolved. Calls are ordered by (time, position in the ledger), and each carries `cursor` `<ts>:<position>`. The next page passes the last call's cursor, so calls sharing a millisecond are not skipped (a bare `<ts>` still means "older than"). `limit` is an integer 1–200 (default 50; anything else → 400). `from`/`to` and `summary` dates must be real calendar days (`2026-02-31` → 400).
- Bad dates → 400.

### UI
- Entry points: 设置 → 助手 → 用量与费用; the context ring popover in the assistant panel gets a "查看用量" link.
- Range control: segmented button 7 天 / 30 天 / 90 天 / 今年.
- Header row of four stat tiles: 估算费用, Tokens (输入+输出), 调用次数, 缓存命中率 (`cache_read / (input + cache_read)`). Each tile shows the change against the previous equal-length period in muted text.
- Daily chart: one card, metric toggle 费用 / Tokens. Tokens are stacked bars (输入, 缓存命中, 输出), cost is a single series; one y-axis, hover/press tooltip per day, legend above the plot, a table view for accessibility.
- Breakdown card with tabs 模型 / 用途 / 对话: ranked rows with a thin proportional bar, cost and token figures in tabular numerals; a row opens the filtered call list.
- Call list: time, model, purpose, input → output (cached), cost, duration; errored calls marked with an icon and label.
- Empty state when the ledger has no lines in range.
- Visual rules: Material 3 tonal surfaces, theme color roles only, no gradients or decorative illustrations, numbers in tabular figures, currency `$` with 4 significant decimals below $0.01.

## Plan
1. `agent/src/usage.mjs`: append, backfill, summary, call paging; wire `message_end` in `host.mjs`, `completeSimple` call sites in `timeline.mjs`, `vision.mjs`, `models.mjs` (provider test).
2. Routes in `host.mjs`.
3. App: `features/usage/usage_page.dart` and `widgets/charts.dart` (shared bar chart and stat tile used by the activity spec), settings entry and context-ring link.

## Verification
- `node --test agent/src/usage.test.mjs`: summary over a fixture ledger (zero days, cache rate, grouping, range edges); backfill idempotence on a fixture session directory; a turn with tool round trips records every assistant message.
- Live: one chat turn with a tool call adds one line per assistant message; outline generation adds a `timeline` line; totals on the page equal the sum of the call list for the same range.
- `flutter test`: widget test of the page with a stub summary (tiles, toggle, empty state).

## Evidence
- Ledger and summaries: [usage.mjs](../../agent/src/usage.mjs), tests in [usage.test.mjs](../../agent/src/usage.test.mjs) (zero days, grouping, previous period, range errors including impossible dates and spans over 366 days, paging with shared timestamps, idempotent backfill, flush waiting for appends in flight).
- Recording: `recordUsage` in [host.mjs](../../agent/src/host.mjs) (every assistant message, with time to first token; the signal handler awaits `usage.flush()`); `timeline`, `vision` and `test` purposes in [timeline.mjs](../../agent/src/timeline.mjs), [vision.mjs](../../agent/src/vision.mjs), [models.mjs](../../agent/src/models.mjs).
- Page: [usage_page.dart](../../app/lib/features/usage/usage_page.dart), [charts.dart](../../app/lib/widgets/charts.dart); widget test [usage_page_test.dart](../../app/test/usage_page_test.dart).
- Live check (2026-10-14): backfill imported 42 calls from 4 conversations; a chat turn with two tool round trips added 3 lines (one per assistant message, all with the session id and time to first token); a provider test added a `test` line; an invalid date returned 400.
- Not covered: Pi's automatic context compaction makes a summarization call that is not an assistant message and is not recorded; the `title` purpose is reserved (titles are not model-generated today).
