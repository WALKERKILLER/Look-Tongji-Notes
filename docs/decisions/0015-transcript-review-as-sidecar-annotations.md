# Transcript review as sidecar annotations

## Status
Accepted
Class: architecture

## Context and Problem Statement
ASR errors in technical lectures need context-sensitive suggestions without turning a model's guess into the teacher's words. Users need the original transcript for playback, search and comparison, including after re-transcription.

## Decision Drivers
- Preserve the original transcript and timestamps.
- Make uncertainty and evidence visible beside the suspected word.
- Keep annotations portable and detect stale results.
- Reuse the configured model pipeline without expanding chat-tool permissions.

## Considered Options
- Replace transcript text with model output.
- Store a separate corrected transcript.
- Store typed annotations bound to the original transcript fingerprint.

## Decision Outcome
Use typed annotations in a lecture-local JSON sidecar. Bind each review to the full transcript fingerprint and each suggestion to an exact, unique original span in its segment. The UI inserts a parenthetical guess after that span. A stale review remains available as a status but is not rendered against changed text. The host runs a bounded review workflow through the existing model pipeline; ordinary agent tools keep their existing write boundary.

## Pros and Cons of the Options
- Replacement is simple to read, but loses the original evidence and can alter teacher meaning and search results.
- A second transcript preserves an original copy, but duplicates the whole document and makes individual guesses difficult to inspect or dismiss.
- Sidecar annotations retain uncertainty, references and original text with small writes. They require span validation and explicit invalidation after re-transcription.

## Links
- [Feature contract](../specs/0018-library-and-transcript-review.md)
- [Existing assistant boundaries](../specs/0007-resident-bot-and-course-agents.md)
