# Learning activity heatmap

Artifact-Version: 1
Status: Implemented

## Intent
Students want to see their study rhythm the way GitHub shows contributions: which days they studied, how much, and their streaks. Look Studio records no study time today (playback keeps only the last position).

Outcome: lookd records daily study activity, and the app shows a contribution-style heatmap on Home with a details page per day and per course.

Non-goals: tracking outside the app, idle detection beyond the rules below, sharing or leaderboards, data for other users.

## Contract

### What counts
The heatmap unit is **study minutes**, measured by the app:
- `watch`: the player is playing and the window is visible (unfocused counts, so a lecture beside another window counts; minimized or hidden does not). Any speed counts wall-clock seconds.
- `read`: a note or parsed courseware is open in the reader, the window is focused, and the user scrolled, typed or clicked within the last 2 minutes.
- `practice`: a quiz is open (see the quiz spec), focused, with an answer within the last 2 minutes. Added with the quiz feature.
Counted events, shown in day details but not in the minutes: questions asked to the assistant (`ask`, posted by the app), notes created or edited by the user and transcripts completed (derived by lookd from the `notes` and `assets` tables, so autosaves cannot inflate them and past days are filled truthfully), quiz sets finished (with the quiz feature).
A day is active (heatmap, streaks, `active_days`) with at least one minute of study or any event above, including a finished transcript; lookd and the app share this rule. A day with events but no minutes shows at the lowest level.

### Storage and API (lookd)
- Table `activity(day TEXT, kind TEXT, course_id TEXT, lecture_id TEXT, seconds INTEGER, count INTEGER, PRIMARY KEY(day, kind, course_id, lecture_id))`, local-time `day`; added by an in-place schema migration that keeps existing data.
- `POST /api/activity` `{id?, kind: watch|read|practice|ask, seconds?, count?, lecture_id?, course_id?, at?}` adds to the day bucket (course filled from the lecture); `seconds` per request ≤ 300, `count` ≤ 50, `at` within the last 24 h (else 400). The app credits time every 10 s, flushes every 60 s and when the window is hidden, keyed by the local day it was earned on (sent as `at`). Each report carries a random `id` (8–64 of `A-Za-z0-9_-`) that the app keeps until lookd confirms the report. lookd remembers applied ids for 48 h (`activity_reports`, not mirrored) and ignores a repeat, so a retry after a lost response is counted once.
- The table is mirrored to `activity.json` in the library root and restored by reindex, like `schedule.json`, so the index stays rebuildable from files. Each report and its mirror write share one transaction. If the file cannot be written, the report is rolled back and the request fails. Before the file changes, its previous bytes are journaled in `<library>/.mirror-journal/` and the transaction records the journal's token; when the transaction does not commit (a failed commit, or a crash before it), the previous file is put back right away or when the library next opens. Writers and reindex share one lock, and reindex settles leftover journals first, so it never imports an uncommitted file. Reindex keeps the larger of stored and restored totals, so an older file never lowers newer data. Rows that a report could not have produced are skipped: an unknown kind, a day that is not a real calendar day from 2000 to tomorrow, negative or over-a-day totals, or seconds on `ask`.
- `GET /api/activity?from&to[&course_id]` (≤ 400 days) → `{days:[{date, minutes, by_kind:{kind: seconds}, asks, notes_created, notes_edited, transcripts}], streak:{current, longest}, totals:{minutes, active_days}, courses:[{course_id, title, minutes}]}`. `GET /api/activity/day?date` adds `lectures`, `notes` and `transcribed` for the day sheet.
- No minutes are invented for the past; note and transcript counts cover existing data.

### UI
- Home card 学习足迹, below 接下来: a week-column grid (Monday-first rows, month labels on top, 周一/三/五 row labels), as many weeks as fit the card width (at most 53). Five levels: no activity plus four steps of the primary tonal ramp, thresholds from the quartiles of the user's non-zero days in the shown window, so light and heavy studiers both get contrast. Cells 11–13 dp with 3 dp gaps and 3 dp corners.
- Beside or below the grid: 本周 X 小时 Y 分, 连续 N 天, 最长 N 天. A legend 少 ▢▢▢▢▢ 多 sits under the grid.
- Hover (desktop) or press shows a tooltip: date, minutes, and the per-kind breakdown. Tap opens the day sheet: minutes per kind, lectures watched (tap to open at the last position), notes, quiz scores, questions asked.
- 学习统计 page (from the card's header action): year selector, full-year grid, a per-course minutes ranking, and kind totals. Keyboard: arrow keys move the focused cell; each cell has a semantics label "10月14日，学习 42 分钟".
- Dark theme uses its own ramp steps computed from the dark scheme. Empty state: an empty grid with "开始看课或做题后，这里会记录你的学习足迹".

## Plan
1. lookd: migration, `internal/store` activity methods with tests (note and transcript counts derived in queries), `activity.json` mirror, handlers in `internal/server`.
2. App: `core/activity_tracker.dart` (player, reader and assistant hooks; flush on lifecycle), `widgets/heatmap.dart`, Home card, stats page, day sheet. The quiz hook comes with the quiz feature.

## Verification
- `go test ./internal/store`: bucket upsert, local-day boundaries, streaks across month ends, migration on a database created with the old schema.
- Server test for input bounds (`seconds` > 300, old `at`).
- `flutter test`: heatmap levels from quartiles, week layout for a range spanning a year end, tooltip text.
- Live: play a lecture for 3 minutes → today shows 3 minutes `watch`; pausing stops the count.

## Evidence
- Store: [activity.go](../../lookd/internal/store/activity.go), tests in [activity_test.go](../../lookd/internal/store/activity_test.go) (buckets and derived counts, streak across a month end including a transcript-only day, migration of an old database, row validation) and [activity_mirror_test.go](../../lookd/internal/store/activity_mirror_test.go) (a repeated report id counted once, a failed commit undoing the mirror); file mirror [library/activity.go](../../lookd/internal/library/activity.go) with [activity_test.go](../../lookd/internal/library/activity_test.go) (restored by reindex, idempotent, never lowered by an older file, report rolled back when the file write fails, invalid rows skipped) and [mirror_test.go](../../lookd/internal/library/mirror_test.go) (a failed commit restoring the file, recovery after a crash before and after the commit, reindex ignoring an unfinished write and waiting for writers); report ids kept across a retry in [activity_test.dart](../../app/test/activity_test.dart).
- API: [server/activity.go](../../lookd/internal/server/activity.go), bounds in [activity_test.go](../../lookd/internal/server/activity_test.go).
- App: [activity_tracker.dart](../../app/lib/core/activity_tracker.dart) (hooks in `lecture_player.dart`, `note_reader.dart`, `assistant_controller.dart`), [heatmap.dart](../../app/lib/widgets/heatmap.dart), [activity_page.dart](../../app/lib/features/activity/activity_page.dart); [activity_test.dart](../../app/test/activity_test.dart) covers quartile levels, weeks across a year end, tooltip text, the tracker's visibility, focus and idle rules with an injected clock, and the Home card's semantics, hover tooltip and day sheet.
- Live check (2026-10-14): on the existing library the year view returned zero minutes and no note days (all 6 notes are assistant-written, so none count), 5 transcripts on 10-14 with titles in the day sheet; `seconds` 400, an unknown kind, an old `at` and a 2-year range each returned 400.
- Not verified: the 3-minute playback check and the UI's look; they need someone at the screen.
