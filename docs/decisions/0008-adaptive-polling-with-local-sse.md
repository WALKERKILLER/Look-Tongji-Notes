# Lecture and Canvas updates come from adaptive polling in lookd, pushed to the app over SSE

## Status
Accepted
Class: architecture

## Context and Problem Statement
Replays appear on Look some time after a class ends, and Canvas assignments and announcements change at any time, but the course page only refreshed when the user pressed sync. Users want new replays and notices as soon as possible without hammering the university's services (see [live refresh spec](../specs/0010-live-refresh.md)).

## Decision Drivers
- Neither Look nor Canvas offers students a push channel (webhooks need an admin; Canvas Live Events go to institutions).
- Latency where it matters: the hours after a class ends.
- Low request volume overall, no request bursts at start-up, and nothing running while the user is signed out.
- One update path for every app screen.

## Considered Options
- A. lookd polls adaptively per course (10 minutes right after a class, then 30 minutes, then 3 hours; a 6-hour sweep otherwise) and publishes changes on its existing `/api/events` SSE stream; the app listens.
- B. The app polls lookd on a timer per screen.
- C. Fixed-interval polling of every course.
- D. A WebSocket channel between app and lookd.

## Decision Outcome
Chosen option: A. lookd already holds the session and the SSE stream every screen subscribes to, so one watcher serves all screens and the agent; scheduling by each course's lecture times concentrates requests where a replay is expected. Changes become `lecture_changed` events and items in a small notification feed.

### Consequences
- Good: a replay is noticed within about 10 minutes of appearing in the first hours, while a quiet term costs a few requests per course per day.
- Good: course pages, the bell and toasts update without a manual sync.
- Bad: updates arrive only while Look Studio runs; there are no operating-system notifications when it is closed.

## Pros and Cons of the Options
- A: one scheduler, adaptive load, reuses SSE; needs care with start-up spreading and failures (retry after 10 minutes).
- B: duplicated timers and requests per screen, nothing happens when the screen is closed.
- C: either slow (long interval) or wasteful (short interval) for every course.
- D: a second transport with no benefit over SSE for one-way updates on localhost.

## Links
- [Live refresh spec](../specs/0010-live-refresh.md)
