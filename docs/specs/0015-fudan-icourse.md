# Fudan iCourse sign-in and replays

Artifact-Version: 1
Status: Approved

## Intent
Fudan students want Look Studio for their recorded lectures, which live on iCourse (`icourse.fudan.edu.cn`). iCourse is the product Tongji runs as Look (same `courseapi/v3`, `userapi`, `pptnote` routes and media signing), but it answers only on campus or through WebVPN (`webvpn.fudan.edu.cn`), and it signs in through Fudan UIS rather than Tongji IAM. Outcome: the login page offers a school picker with emblems; choosing 复旦大学 signs in to WebVPN and, through it, to iCourse, and the existing courses, player, downloads, slides and transcription work on Fudan replays.

This changes [spec 0011](0011-canvas-and-schools.md), which listed iCourse as a non-goal: Fudan's school profile now has `look: true` and no note.

Non-goals: Fudan UIS captcha or second-factor prompts (the sign-in fails with UIS's message); courses of two schools side by side (one school is signed in at a time; courses from a previous school stay in the local list); iCourse features Look lacks.

## Contract

### Sign-in
- `GET /api/schools` → the school profiles of spec 0011 (`{id, name, canvas, sso, look, emblem_url}`); the login page offers those with `look: true`.
- `POST /api/auth/login {school, username, password, captcha?, remember}`: `school` is `tongji` (default, unchanged behavior) or `fudan`; anything else is 400. Rejected credentials are 401 with UIS's message.
- Fudan: lookd runs the UIS chain of spec 0011 (`queryAuthMethods`, `getJsPublicKey`, RSA `authExecute`, `authnEngine`, ticket) twice: for WebVPN (`/login?cas_login=true`, entity `https://webvpn.fudan.edu.cn`), then through the gateway for iCourse (`/casapi/index.php?r=auth/login&school_login=1&tenant_code=222`, entity `https://icourse.fudan.edu.cn` when the address lacks one; a ticket address naming iCourse itself is rewritten to its WebVPN address). It then requires `/userapi/v1/infosimple` to answer as the user. The gateway's session cookie is the only Fudan credential lookd keeps besides the remembered password.
- `GET /api/auth` and its events carry `school`. A Fudan session has no expiry time (`expires_at` is the zero time).

### Renewal
- Every iCourse call goes through WebVPN (the host rewritten with the gateway's AES-CFB scheme). An answer of 401/403, HTML, or an address outside the gateway's `/http…` paths means the session is gone: lookd signs in again and retries once. Renewal is single-flight, like Tongji's.
- Order: without the password first (succeeds while the UIS session lasts; method `sso`), then the remembered password (method `password`). Without a remembered password the status becomes `needs_password` with `复旦 WebVPN 登录已过期，请重新登录`.
- Persistence: `session.json` stores `school`, the cookies and, with `remember`, the sealed password (as for Tongji). Logging out keeps only the school, so the login page preselects it.

### Media
- Stream, slide and courseware addresses are fetched through WebVPN with the gateway cookie. The cookie never leaves lookd: for Fudan, `GET /api/lectures/{id}/media` returns stream URLs `/api/lectures/{id}/streams/{n}`, empty `headers` and `relayed: true`.
- `GET /api/lectures/{id}/streams/{n}` (token as header or `?token=`) relays stream `n`, passing `Range`/`If-Range` and returning `Content-Type`, `Content-Length`, `Content-Range`, `Accept-Ranges`, `Last-Modified`, `ETag`. The resolved media is reused for 10 minutes; a refused or signed-out answer resolves it once more (which renews the session when needed).
- Remote slides for a relayed lecture load from `/api/lectures/{id}/slides/{idx}/image`, which fetches through WebVPN. Downloads and re-signing use the same addresses inside lookd.
- Canvas: Tongji's SSO mode requires a Tongji Look sign-in; Fudan's Canvas keeps its own UIS sign-in.

### App
- Login page: product mark (phones), title, 「选择学校，用统一身份认证账号登录」, a row of school tiles (emblem on a white disc, name, radio mark; the selected tile has a neutral fill, a primary outline and a check), a per-school hint (Tongji: Look's address; Fudan: WebVPN, about half a minute), 学号 / 工号, 密码, captcha only for Tongji, 保持登录, the error next to the form and 登录. Sign-in waits up to 130 s. Re-entering the password after a lapse keeps the school fixed.
- Settings → 账号 shows the signed-in school.

## Plan
`lookd/internal/fudan` (`UIS.VPN`, `UIS.Entity`, `ErrNeedsPassword`, `SignInICourse`), `lookd/internal/tongji` (school in `Session`: login, renewal, `Do` through WebVPN, `Base`, `URL`, `Header`; `Client.StreamURL`), `lookd/internal/server` (`/api/schools`, login school, media relay in `relay.go`, slide fetch, Canvas guard), `lookd/internal/jobs` (addresses and headers from the session), app login page, models, player and account section.

## Verification
- `go test ./internal/tongji -run Fudan`: against a fake UIS, WebVPN gateway, iCourse and video host: a wrong password is rejected with UIS's message; sign-in, course list and signed video through the gateway with ranges; silent renewal when only iCourse's session lapsed (no credential submission); password renewal when the gateway session ended; restart from `session.json` with the password stored only sealed; `needs_password` without a remembered password.
- `go test ./internal/server -run Relay`: ranges and the gateway cookie stay on the daemon side.
- `flutter test test/login_test.dart`: at 360×780 the picker lists only `look: true` schools without overflow, Fudan posts `school: fudan`, and a 401 shows its message.
- Live (pending an account): sign in with a Fudan account, list courses, play and download one replay, wait for the gateway session to lapse and play again.

## Evidence
- [Fudan session tests](../../lookd/internal/tongji/fudan_test.go), [relay test](../../lookd/internal/server/relay_test.go), [login form test](../../app/test/login_test.dart), [about test](../../app/test/about_test.dart).
- Live, without an account: UIS's real redirect carried `lck` and `entityId`, offered `userAndPwd`, and its RSA key parsed. Sign-in with an account, courses and playback through WebVPN are not yet exercised live.
