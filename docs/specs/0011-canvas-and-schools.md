# Canvas and school profiles

Artifact-Version: 1
Status: Approved

## Intent
Students at Tongji and Fudan use Canvas for assignments, courseware and announcements next to their recorded lectures, but had to check it separately and type homework into the schedule by hand. Outcome: Look Studio connects to the school's Canvas, puts assignments into the schedule with reminders, links each Canvas course to its Look course, downloads courseware into that course's folder, and keeps the connection alive without the user renewing anything. A school chooser with each school's emblem makes Fudan (whose Canvas is the same product) a first-class choice. Design choice for sign-in: [decision 0009](../decisions/0009-canvas-through-the-school-sso-session.md).

Non-goals: submitting assignments or changing anything on Canvas; grades beyond the score shown with an assignment (Fudan iCourse replays are [spec 0015](0015-fudan-icourse.md)); Canvas instances other than through an access token.

## Contract

### Schools
- `GET /api/canvas` returns `schools`: `{id, name, canvas, sso, look, emblem_url, note}` for `tongji` (`https://canvas.tongji.edu.cn`, `sso: "look"`, Look replays) and `fudan` (`https://elearning.fudan.edu.cn`, `sso: "uis"`, iCourse replays per [spec 0015](0015-fudan-icourse.md)). The app adds `other`: any `https://` Canvas site with a token.
- Emblems: Fudan's (public domain, trademark) is bundled as `app/assets/schools/fudan.svg` with a NOTICE; Tongji's (not freely licensed) is downloaded by the app from `emblem_url` on first use and cached in the app support folder `emblems/`. Both are drawn on a white disc so their brand colours read the same in light and dark themes; while missing, the school's first character is shown.

### Connection modes
- `sso` (default where available). Tongji: lookd opens `<canvas>/login/openid_connect` with the HTTP client that holds the Tongji IAM cookies of the Look session; the redirects end on Canvas with its session cookies, which persist with the Look session state. Fudan: lookd runs the UIS chain (`/idp/authn/queryAuthMethods`, `getJsPublicKey`, RSA-encrypted `authExecute`, `authnEngine`, ticket) for `<canvas>/login/cas` with a sealed UIS password; cookies stay in memory. API calls send the session cookies.
- `token`. A pasted access token, or with `create: true` (schools with SSO) a token that lookd creates through the web session: `POST /api/v1/users/self/tokens` with `token[purpose]=Look Studio`, `token[expires_at]` 90 days ahead, and the session's CSRF token.
- Renewal, the reason for the modes: Canvas personal access tokens have no refresh token, and their expiry is whatever was set when they were created ([Canvas access tokens API](https://canvas.instructure.com/doc/api/access_tokens.html)). Refresh tokens exist only for OAuth2 developer keys, which only an institution's admin can issue ([Canvas OAuth2](https://canvas.instructure.com/doc/api/file.oauth.html)). Therefore:
  - In `sso` mode, a call answered with 401, or redirected to `/login`, signs in again and retries once. Canvas answers `/api/v1/users/self` with 404 (not 401) when there is no session, so that 404 counts as signed out, and a 404 from any other call is checked against `users/self` before it is reported. Renewal is single-flight: concurrent calls that hit an expired session share one sign-in, and a renewal less than 30 s old is reused; after signing in, `users/self` must answer or the error says Canvas did not accept the session. Network errors, 5xx and 429 are retried once after 2 s. The status reports the last renewal as `renewed_at`. Tongji first tries silent SSO; when IAM wants credentials, it renews the Look session (silent SSO, then the remembered password) and tries again. Fudan logs in to UIS again with the sealed password.
  - An automatic token is replaced when fewer than 14 days remain, or when Canvas rejects it: lookd creates a new one, then deletes the old one with `DELETE /api/v1/users/self/tokens/:id`. Disconnecting revokes it.
  - A pasted token that Canvas rejects leaves the error `Canvas 访问令牌已失效或被撤销，请重新粘贴令牌` in the status.
- Canvas's API policy asks multi-user applications to use OAuth rather than tokens that users generate by hand ([Canvas OAuth2](https://canvas.instructure.com/doc/api/file.oauth.html)), so the default mode uses the student's own web session, the way a browser does, and token modes are opt-in.
- Secrets: tokens and UIS passwords are sealed with the per-install key (`tongji.Seal`) in `<data>/canvas.json` (mode 0600). They are never logged or returned; the status shows only `token_last4`.

### Sync
- Every 15 minutes while `watch.enabled` is on (and on connect, on 立即检查, on `POST /api/canvas/sync`), independent of the Look session. One sync at a time.
- Steps: `GET /api/v1/users/self`; `GET /api/v1/courses?enrollment_state=active&include[]=term` following `Link: rel="next"`; per course `GET /assignments?include[]=submission` (courses that refuse are skipped); `GET /api/v1/announcements` for the last 30 days, ten courses per request. Requests send `Accept: application/json+canvas-string-ids`; a `while(1);` prefix is removed.
- The result is cached in `<data>/canvas-cache.json`, and the sync publishes `canvas_changed {what: "syncing" | "synced" | "connect" | "disconnect" | "links"}`. It also publishes `schedule_changed {id: "canvas"}` when assignments changed.
- Notifications use ids `canvas:a:<id>` (`assignment_new`), `canvas:due:<id>` (`assignment_due`: not done, due within 24 hours) and `canvas:n:<id>` (`announcement`). The first sync after connecting marks everything seen and announces only deadlines within 24 hours. Each notification carries the Canvas page URL and the linked Look course.

### Course links
- Each Canvas course links to at most one Look course. Automatic links match names after lower-casing and removing bracketed parts, spaces and punctuation: an exact match wins; otherwise a single Look course whose name contains, or is contained in, the Canvas name (at least 3 characters). Ambiguous names stay unlinked.
- `PUT /api/canvas/links/{canvas id} {course, auto}`: `auto: true` returns the course to automatic matching; otherwise `course` is a Look course id, or `""` for none. Manual choices are kept across syncs.

### Schedule
- `GET /api/schedule` also returns Canvas assignments that have a due date and are not hidden. Each is returned as `{id: "canvas:<id>", kind: "homework", source: "canvas", title, detail: "<Canvas course> · <points> 分", due_date, due_time, course_id, course_title, done, url}`, with due times in Asia/Shanghai. The same query filters apply, and the result is sorted together with stored items.
- Done means submitted, graded or pending review, unless the user overrode it locally. `PATCH /api/schedule/canvas:<id>` accepts only `{done}` (a local override) or `{hidden: false}`; anything else is 400. `DELETE` hides the item. Canvas itself is never changed.
- The assistant's duplicate check for new homework includes Canvas items, and it may change only `done` on them.

### Courseware and detail
- `GET /api/canvas/courses/{id}` → `{course, assignments (with done, newest due first), announcements}` from the cache.
- `GET /api/canvas/courses/{id}/files` lists files live (newest first). When the Files page is closed to students, it lists the File items of the course's modules instead, with their module name.
- `POST /api/canvas/files/{id}/download {course}` saves the file:
  - linked: into `<Look course folder>/Canvas/`, otherwise `canvas/<Canvas course>/` under the library;
  - an existing file of the same name and size is kept;
  - returns `{path}` relative to the library.

### Other routes
`POST /api/canvas/connect {school, base, mode, token?, create?, username?, password?}` → status (`base` defaults to the school's site; 400 for bad input, 401 for rejected credentials); `POST /api/canvas/disconnect`; `POST /api/canvas/sync` → status with `syncing: true`. Status: `{connected, school, base, mode, user, username, token_last4, token_auto, expires_at, syncing, error, synced_at, courses: [{id, name, course_code, term, look_course, manual, open, total}]}`.

### App
- 设置 → 学校与 Canvas: a row with the school emblem and the state. It opens a page that is either the connect form or the connection:
  - Form: school cards with emblem and what each offers; a segmented 统一身份认证 / 访问令牌 choice; an explanation of what each does; UIS fields for Fudan; for tokens, a switch to let Look Studio create and renew one, or three steps with a link to the Canvas settings page and a masked field. 连接 stays disabled until the input is complete; Tongji SSO needs the Look sign-in.
  - Connection: a card with the emblem, user, sign-in mode (token as `····last4`, renewal and expiry), last sync, a progress bar while syncing, the error, 立即同步, 更改登录方式 and 断开 (with a confirmation saying what is removed). Below it, the course list, each row with a link chip whose menu offers automatic matching, none, or any Look course; tapping a row opens the course view.
- Course page: for each linked Canvas course, a card with up to three upcoming assignments and chips 作业 / 课件 / 公告. These open the course view: a dialog on wide windows, a bottom sheet on phones, with tabs for assignments (state, due, points; opens on Canvas), files (download into the course folder, then open; locked files disabled) and announcements.
- Schedule: Canvas items carry a Canvas badge. Tapping opens the assignment on Canvas, and the menu offers 在 Canvas 打开 and 从日程隐藏 with undo; the done check sets the local override.

## Plan
`lookd/internal/canvas` (client, service), `lookd/internal/fudan` (UIS, WebVPN), `lookd/internal/server/canvas.go` (schools, sign-in adapters, routes, schedule merge), the watcher hook, and `Session.Client()` in `lookd/internal/tongji`. In the app: `app/lib/features/canvas/` (emblem, page, course view), the schedule tile, the course page and the settings entry.

## Verification
- `go test ./internal/canvas`: SSO sign-in and silent re-sign-in after the session expires; pagination; skipped courses; notifications (first sync only due soon, then new ones once); local done and hide/unhide; persistence; automatic token creation with CSRF, rotation before expiry and after revocation, revocation on disconnect, sealed at rest; a rejected pasted token; plain-http and SSO-less refusals; files falling back to modules and download; name matching.
- `go test ./internal/fudan`: WebVPN host encryption, and the UIS chain against a fake server. `go test ./internal/server`: schedule merge order.
- `flutter test test/canvas_test.dart`: Fudan and other-school forms post the right body and stay disabled while incomplete; the connected status shows only the last 4 token characters; link menu; the course view's assignments, download and announcements.
- Live (Tongji, read-only): connecting in SSO mode with a signed-in Look session listed the Canvas courses, auto-linked them, merged their assignments into the schedule, listed and downloaded a file; the Look session stayed active. Token creation, Fudan UIS sign-in with an account, and Fudan Canvas were not exercised live.

## Evidence
- [canvas tests](../../lookd/internal/canvas/canvas_test.go), [fudan tests](../../lookd/internal/fudan/uis_test.go), [server merge test](../../lookd/internal/server/canvas_test.go), [app test](../../app/test/canvas_test.dart).
- Canvas REST API: [access tokens](https://canvas.instructure.com/doc/api/access_tokens.html), [OAuth2](https://canvas.instructure.com/doc/api/file.oauth.html), [pagination](https://canvas.instructure.com/doc/api/file.pagination.html).
- Fudan UIS and iCourse protocol, learned (not copied) from [fudan-courseflow](https://github.com/kniphofia1/fudan-courseflow).
- Emblems: [Fudan University Logo](https://commons.wikimedia.org/wiki/File:Fudan_University_Logo.svg), [Tongji University Emblem](https://zh.wikipedia.org/wiki/File:Tongji_University_Emblem.svg).
