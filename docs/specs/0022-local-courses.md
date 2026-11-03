# Local courses

Artifact-Version: 1
Status: Implemented

The user authorized creating courses outside the school catalog and importing the downloaded operating-system course on 2026-10-30.

## Intent

Let a person create a named course, import local videos as separate lessons, and study them with the existing player, canvas, notes and playback history.

## Contract

Local courses use the reserved `local-` ID namespace and the `local` term. School synchronization and recording polling skip their identities. School refresh retains them. They belong to the currently selected library and follow its existing school-profile isolation.

The human course screen creates an empty course and can append selected video files. Uploads stream into temporary files, are limited to 4 GiB per video, and must contain a readable video track and a positive duration. A failed upload publishes no lesson; successful earlier files remain available and the UI names the failed file. The original files remain intact. Names never become filesystem paths supplied by a request. Source files and manifests live within the library, and the SQLite index can be rebuilt from them. Imported lessons keep selection order without inventing class dates.

The authenticated API exposes `POST /api/local-courses` with a required `title` and optional `teacher`, and `POST /api/courses/{id}/local-videos?name=...` with raw file bytes. Both clients declare the contract; general assistant tools receive no creation or import capability. Local playback and lesson refresh do not request campus media. Unsupported extensions, empty/invalid video, path-like filenames, oversized bodies and non-local target courses are rejected. Import requires the existing ffprobe dependency.

## Plan

Implement library-owned manifests and atomic lesson publication, authenticated HTTP adapters, course creation and import UI, and the native feature overlay. Package and validate the local canvas application, then import the six downloaded lessons.

## Verification

Exercise the registered authenticated API with a real generated video: course creation, video import, Range playback, no campus requests, failure cleanup, school-course rejection, and rebuild from an empty index. Drive the creation dialog and partial-upload recovery in Flutter tests. Verify the native staged build and the installed app with the real six videos.

## Evidence

- [Registered API integration](../../lookd/internal/server/local_courses_test.go) verifies authentication, empty-course creation, real-video import, ordered lessons, idempotent retry, Range playback, campus-independent local reads, validation failures, size rejection, symlink rejection, refresh retention and rebuild from an empty index. The test passes in both the working source and the staged native source with the race detector.
- [Flutter dialog tests](../../app/test/local_course_test.dart) verify required naming, file order, partial failure recovery and the local-course label. The native selection of local-course, downloads, study-module and library-review tests passes all 14 cases; the native agent suite passes all 75 cases. All six governance gates pass.
- The installed canvas test package uses version code `2026103001`. The six real operating-system videos are imported through the same library implementation, and their SHA-256 values match the original files. The native UI displays one independent course and six ordered lessons, retains school courses after refresh, renders the first video in both layouts, and pauses after 49 seconds of playback.
- The broader native Go run passes server, store and jobs packages but reports a failure in `TestObsidianWritesStayInsideAfterSwap`. Running that test against the untouched pinned base `632120458a9aefe44ab1297168660144bd2fbc77` reproduces the same failure; this change does not modify the Obsidian implementation or that test.
