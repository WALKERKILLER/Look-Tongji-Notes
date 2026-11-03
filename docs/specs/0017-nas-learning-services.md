# NAS learning services in Studio

Artifact-Version: 1
Status: Implemented

Approved by the user in this chat on 2026-10-24: “按完整规格接入，包含两个手动运行按钮（推荐）”。

## Intent

Expose the user's existing NAS course downloader, lecture subscriber, deadline calendar and homework worker through the Fudan Studio interface. NAS owns background execution; Studio presents courses, source material, deadlines, generation progress and deliverables. The integration reuses the existing services and their schedules instead of creating another scheduler. The architecture choice is recorded in [0015](../decisions/0014-nas-services-through-a-local-bridge.md).

## Contract

### Course workspace

The course page presents recordings, shared course material, deadlines and homework together. Course identity uses an explicit mapping of local course code, Canvas course ID and iCourse course ID. Course mappings are explicit and editable; ambiguous matches are left for correction. Material can belong to a whole course without being assigned to a fictitious lecture. The bridge reads the configured Syncthing semester folder; existing source files remain the canonical copies.

The material list includes file type, source, last observed modification and availability. Supported files open through the authenticated local backend. HTML source is rendered as text or in a restricted sandbox; scripts cannot execute in the app origin. File access resolves real paths within configured semester/calendar roots, rejects symlinks escaping those roots and excludes hidden working directories and credentials. The bridge does not expose arbitrary host paths or an arbitrary shell interface.

### Calendar and homework

Deadline cards use existing calendar event IDs and preserve Asia/Shanghai timestamps and source links. A deadline imported from NAS and the same Canvas assignment appear once, with explicit source identifiers. Generation status and platform submission status remain independent fields. A ready PDF does not imply submission; a successful worker scan does not imply every job succeeded.

Homework cards show queued, running, ready, needs-input, failed, existing and platform-submitted states where supplied by the NAS worker. Each card can open its original requirement, report Markdown/PDF, code directory and related lecture material. Missing or not-yet-synchronized output files are marked unavailable; the UI never invents success or an output link. Existing protected reports remain protected by the worker.

### Service bridge

The local Go daemon owns an SSH subprocess transport using the user's existing configured NAS alias. The browser receives only typed, filtered data. An explicit remote reader obtains service state, timer metadata, safe health fields and a read-only SQLite query of the homework queue; it never exports credentials, full environment variables, raw task payloads or Codex event logs. Requests are bounded, cancellable and serialized as needed; SSH uses batch mode and existing host verification. No new public NAS port is opened.

Every response reports its observation time and source. Cached snapshots remain visible when NAS is unavailable, with a stale/offline label. Service liveness, last scan outcome and per-job outcome are shown separately. The local bridge polls only while the app is running; existing NAS timers continue independently.

### Human-initiated operations

The approved full scope adds two buttons: scan/run the existing homework batch and request calendar refresh. The existing worker limits, locks, protected outputs and retry rules remain authoritative. A homework batch may process up to two eligible jobs, as the deployed worker defines; the UI states the scope before dispatch and does not claim single-assignment execution. A command acknowledgement means accepted, not completed; the UI follows health/state changes until a terminal result or unknown outcome.

Only fixed allowlisted service operations are dispatched, with no browser-provided command text or unit names. The bridge prevents duplicate in-flight dispatches and never automatically retries an ambiguous start. No live generation is initiated as a verification step without the user's specific instruction to run that batch. Homework submission, changing timers, installing packages, deleting outputs, email delivery and unrelated NAS services are outside this contract. The existing NAS worker generates drafts and observes submission status; it does not submit assignments.

The user approved both fixed operations. The existing automatic schedules continue on NAS.

### Assistant access

The Studio assistant can list mapped course material, read bounded text excerpts, query deadlines and inspect sanitized homework status after a model is configured. NAS collection itself does not send documents to an additional model. Model-visible references retain source file/page or lecture/time identifiers. Assistant tools cannot invoke NAS execution commands. Provider configuration and the existing note protections remain unchanged.

## Plan

Add a local NAS bridge with typed snapshot and optional dispatch endpoints; update both Flutter and agent clients. Add a course-level material adapter and explicit course mapping. Integrate deadline and homework cards into existing course/schedule screens, with a service-status page for observation time and next run. Document local setup and source attribution without copying external service implementations. Deliver read paths first, then the approved fixed operations.

## Verification

Test parsers against redacted fixtures containing independent generation/submission states, a successful scan with a failed job, ambiguous courses, midnight deadlines, offline/stale snapshots and missing artifacts. Test real-path and symlink escapes, HTML isolation, root exclusions, oversized results and cancellation. If dispatch is approved, test allowlists, duplicate requests and ambiguous timeouts with a fake transport. Assert display/read routes never start a remote process that generates or submits work. Use existing NAS state for live read-only verification, compare counts and identifiers with the source, and inspect the Flutter web views with real course material. Run relevant Go race tests, Flutter tests, agent checks and repository gates.

## Evidence

Implementation is in [nasbridge](../../lookd/internal/nasbridge/bridge.go), its embedded [deployment probe](../../lookd/internal/nasbridge/probe.py), the [authenticated server adapter](../../lookd/internal/server/nas.go), the [Flutter workspace](../../app/lib/features/nas/nas_page.dart), and the read-only `nas` tool group in [agent tools](../../agent/src/tools.mjs). Course pages and the home screen link to the workspace. The original schedule merges NAS deadlines by Canvas identity and refuses writes to NAS-owned entries. The Fudan shell remains usable with an expired campus session; protected recording access still requires campus authentication. The loopback build uses versioned JavaScript and revalidated static assets to avoid stale browser code.

On 2026-10-24, live read-only validation returned seven explicitly linked current-term courses, 676 indexed files, 12 jobs, 12 deadlines, and four service observations. Three ready jobs had synchronized Markdown/PDF reports. Their PDF endpoints returned valid partial PDF responses. The operation-system course filter returned four deadlines. The Flutter web workspace displayed actual queue data, opened a report, and showed both fixed operation buttons with service/timer state. No real NAS batch or calendar refresh was launched for verification.

The owning [Go bridge tests](../../lookd/internal/nasbridge/bridge_test.go) and [server tests](../../lookd/internal/server/nas_test.go) pass with the race detector, covering stale snapshots, allowlisted dispatch, concurrent duplicate requests, unknown outcomes, bounded/cancelled transport, Unicode excerpts, root exclusions, symlink escapes, inert HTML, manifest-only report links, missing outputs, midnight timestamps, course filtering and calendar deduplication/write refusal. [Flutter tests](../../app/test/nas_test.dart) cover independent statuses, read-only browsing, confirmation/cancellation for both actions and offline/narrow-layout behavior. The Flutter suite passed 77 tests; the agent suite passed 57 tests including [NAS tool scope](../../agent/src/nas.test.mjs). Analyzer findings are four existing info-level notices; no new analyzer errors or warnings. Web release compilation, agent syntax checks and repository gates pass.

The bridge targets the existing personal deployment schema. Offline remote-state caching is in memory; synchronized files persist independently. Text reading is bounded to the first 12000 characters and the UI can open the full source file. PDF/Office parsing and NAS-wide full-text indexing are not included; model-backed assistant use still requires provider configuration. Usage and configuration are documented in [Fudan setup](../nas-services.md).
