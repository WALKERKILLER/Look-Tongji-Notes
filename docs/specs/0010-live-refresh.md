# Live refresh and notifications

Artifact-Version: 1
Status: Approved

## Intent
Course pages only refreshed on a manual sync, so users missed replays that appeared after class and had no single place for new Look and Canvas items. Outcome: lookd notices new lectures and replays by itself (and new Canvas assignments and announcements once Canvas is connected), the course page updates in place, a toast appears, and a bell keeps an inbox. Design choice: [decision 0008](../decisions/0008-adaptive-polling-with-local-sse.md).

Non-goals: operating-system notifications, notifications while Look Studio is closed, email or phone push.

## Contract

### Watcher
- Runs in lookd every minute while setting `watch.enabled` is not `false` (default on). Look courses are checked only while the session status is `active` or `renewing`; a connected Canvas is synced every 15 minutes regardless ([Canvas spec](0011-canvas-and-schools.md)).
- The course list is synced at most once an hour. A course is watched when it is not hidden, its end is less than 14 days ago (or unknown) and its start is less than 14 days ahead (or unknown).
- Next check per course from its cached lectures: a lecture ending within 24 h → 10 minutes after its end; a lecture that ended without a replay → every 10 minutes for 3 h, every 30 minutes until 24 h, every 3 h until 7 days; otherwise a 6-hour sweep. Up to 10% jitter; failures retry after 10 minutes; courses are fetched one at a time, 2 s apart.
- After a start, a course is fetched at once only if a replay is awaited; others get their first sweep at a random time within 6 hours.
- On each fetch, lectures are diffed: a new lecture (in a course that already had lectures) publishes `lecture_changed {what: "added"}` and, if it begins within 14 days of now, a `lecture_added` notification; a lecture whose replay appeared publishes `lecture_changed {what: "playback"}` and a `lecture_ready` notification.
- `GET /api/watch` → `{enabled, last_run, last_error, courses: [{course_id, next_at, awaiting}]}`; `POST /api/watch/run` checks every watched course and Canvas on the next pass.

### Notification feed
- `<data>/notifications.json`, newest first, at most 200 items `{id, kind, title, body, course_id, lecture_id, url, at, read}`; `id` is a stable key (`lecture_ready:<lecture id>`, `canvas:a:<assignment id>` …) and a repeated id is ignored.
- Each new item is published as event `notification`. `GET /api/notifications` → `{items, unread}`; `POST /api/notifications/read {ids}` or `{all: true}` → `{unread}` and event `notifications_read`.

### App
- `AppState.unreadNotifications` follows the events. The navigation rail (or the home header on phones) shows a bell with the unread count; it opens a modal side sheet (bottom sheet on phones) listing items with kind icons, marking one read when opened and all with 全部已读. Opening goes to the replay, the course, or the item's web page.
- A snackbar with 查看 announces each new item wherever the user is. The course page reloads quietly on `lecture_changed` for its course.
- 设置 → 通知与自动刷新: the `watch.enabled` switch, the number of awaited replays, the next and last check, the last error, and 立即检查.

## Plan
`lookd/internal/notify` (feed), `lookd/internal/server/watch.go` (scheduler and diff), routes in `server.go`; `app/lib/features/notifications/notification_center.dart`, `app/lib/features/settings/watch_settings.dart`, shell and home wiring.

## Verification
- `go test ./internal/notify ./internal/server`: dedupe, persistence, read marks, cap; next-check intervals by lecture age; which courses are current.
- `flutter test test/notification_center_test.dart`: list, kind icons, mark one and all read, live insertion.
- Live: with the daemon running and signed in, `GET /api/watch` lists the current courses with next check times.

## Evidence
- [notify tests](../../lookd/internal/notify/notify_test.go), [watch tests](../../lookd/internal/server/watch_test.go), [app test](../../app/test/notification_center_test.dart).
