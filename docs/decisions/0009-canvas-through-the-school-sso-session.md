# Canvas is read through the student's single sign-on session by default; access tokens are opt-in

## Status
Accepted
Class: architecture

## Context and Problem Statement
Look Studio reads assignments, files and announcements from the school's Canvas and must keep doing so for a whole term without the student renewing anything (see [Canvas spec](../specs/0011-canvas-and-schools.md)). Canvas offers personal access tokens and OAuth2. Personal tokens have no refresh token, and their expiry is set when they are created. OAuth2 refresh tokens need a developer key, which only the institution's admin can issue. Canvas's API policy also asks applications used by many people to use OAuth rather than tokens that users generate by hand.

## Decision Drivers
- No silent expiry: the schedule and courseware must not stop updating mid-term.
- Nothing created on the student's account unless they choose it.
- Credentials stay inside lookd, sealed at rest, shown only as their last 4 characters.
- Works at Tongji (Canvas behind Tongji IAM, which the Look session already keeps signed in) and Fudan (Canvas behind UIS).

## Considered Options
- A. Default to the web session: Canvas's own OpenID Connect / CAS sign-in through the school's SSO, which lookd already renews for Look (Tongji) or repeats with the sealed UIS password (Fudan). Optionally, a token that lookd creates and rotates, or a pasted token.
- B. Only pasted personal access tokens.
- C. OAuth2 with a developer key.

## Decision Outcome
Chosen option: A. It renews on the same path as the Look session, creates nothing on Canvas, and behaves like the student's browser. The automatic token is for students who prefer a token that survives an IAM outage. It lasts 90 days and is rotated 14 days before expiry, or when it is rejected, then revoked on disconnect. The pasted token covers other Canvas sites.

### Consequences
- Good: no expiry to manage in the default mode; Canvas sign-in failures surface as a clear status error and retry on the next sync.
- Good: the same code path serves any school whose Canvas sits behind an SSO that lookd can drive.
- Bad: lookd depends on Canvas's web sign-in redirects and CSRF cookie, which are not a public API and may change.
- Bad: a pasted token still expires or can be revoked; the user is told and must paste a new one.

## Pros and Cons of the Options
- A: renews itself and needs no admin; relies on web sign-in behaviour.
- B: simple, but expires silently or must be created without an expiry by hand, and goes against the API policy for multi-user apps.
- C: the proper long-term flow, but needs each university's admin to issue a key, which a student tool cannot obtain.

## Links
- [Canvas spec](../specs/0011-canvas-and-schools.md)
- [Canvas access tokens API](https://canvas.instructure.com/doc/api/access_tokens.html)
- [Canvas OAuth2 and API policy notes](https://canvas.instructure.com/doc/api/file.oauth.html)
