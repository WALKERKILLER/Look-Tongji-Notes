# Testing policy

Tests are executable evidence that a meaningful regression becomes visible before delivery. Optimize for risk-adjusted signal over the test's lifetime, not test count, line coverage, or assertion volume. Repository-wide entry commands live in the root [AGENTS.md](../AGENTS.md); this document owns test selection and topology.

## Test selection

Name the behavior or invariant at risk before writing a test. Choose the lowest boundary that can observe it with production-like composition: pure decisions belong in unit tests, module contracts and stateful boundaries in integration tests, and public entry points or cross-system flows in end-to-end tests. One behavior has one primary evidence home; add defense in depth only when a public contract, security boundary, migration, escaped incident, or similarly costly risk justifies the duplication.

| Risk shape | Primary evidence |
|---|---|
| Pure logic, decisions, and state transitions | Focused unit tests at the owning code area |
| Module contracts, persistence, files, queues, or framework composition | Integration tests with real owned modules and only unstable external boundaries replaced |
| Public CLI/API/UI entry points and cross-system flows | End-to-end tests through the shipped entry point with externally inspected results |
| Security boundaries, migrations, and escaped incidents | The lowest sufficient primary test plus narrowly justified defense in depth |

## Test topology

- **Go (`lookd/`)**: `*_test.go` beside the owning package, currently in `internal/asr`, `internal/dl`, `internal/library`, `internal/mineru`, `internal/server` (activity input bounds) and `internal/store`. External services are replaced by `net/http/httptest` servers inside the test; fixtures live in the test file or `t.TempDir()`. Run from `lookd/` with the test command in [AGENTS.md](../AGENTS.md); CI adds `-race`.
- **Flutter (`app/`)**: `app/test/*_test.dart`, run by `flutter test`. `look_markdown_test.dart` covers Markdown/LaTeX normalization (unit) and rendering (widget); `usage_page_test.dart` drives the usage page with a stubbed fetch (pages take an optional fetch function instead of the lookd API); `activity_test.dart` covers heatmap levels and week layout, the tracker's counting rules (injected clock) and the Home card's tooltip and day sheet.
- **Agent (`agent/`)**: colocated `src/*.test.mjs` files run by `npm test` (`node --test`), with fixtures in `os.tmpdir()`; `usage.test.mjs` covers the usage ledger. `npm run check` is a syntax check. The tool guards in `tools.mjs` (note overwrite, transcript coverage, transcript windowing) have no tests yet.
- **Absent tiers**: no HTTP handler tests for `lookd/internal/server` beyond input validation, no app–lookd integration test, and no end-to-end test against the live Tongji, ASR or MinerU services. Live checks are manual (`lookd/cmd/logintest`, `lookd/cmd/probe`); add an integration tier when an API contract regression escapes.

Follow the ecosystem's discoverable convention rather than forcing a universal tree. Colocated unit tests are valid where idiomatic; cross-module and system tests belong in clearly named repository-level roots. Keep a fixture beside the test that owns it and promote it to shared infrastructure only when multiple contracts genuinely share it.

## Evidence rules

- Assert observable outcomes: return values, errors, persisted state, files, process exit status, rendered output, or externally visible side effects. Internal call counts and private ordering are evidence only when they are themselves a contract.
- Test the real entry path where packaging, process setup, configuration, or wiring can fail. A hand-wired harness cannot prove the shipped entry point works.
- Mock only expensive or non-deterministic boundaries such as the network, clock, or an external API; keep owned composition downstream of that boundary real.
- Select representative equivalence classes, boundaries, invalid inputs, state transitions, and recovery points instead of enumerating incidental examples.
- A regression test fails for the escaped behavior before the fix and passes afterward. It proves the cause, not merely that some nearby output changed.
- When a change should preserve a file or state, assert it remains byte-identical or semantically identical as the contract requires.

## Maintenance budget

- Coverage reports locate unobserved code; they are not a target and do not establish test quality.
- Remove or merge tests when their behavior disappears, another test becomes the primary evidence, or they constrain implementation without protecting a contract.
- A flaky test is a broken signal. Fix its uncontrolled boundary or quarantine it with an owner and repair condition; never normalize blind retries.
- Keep the fast path focused enough for local use. Expensive techniques such as fuzzing, mutation, visual regression, load testing, and large environment matrices require a repository risk that pays for their continuing cost.

## When a test is required

Every behavior change adds or updates the smallest test set that proves its affected contract. Every bug fix carries a regression test unless the failure is already deterministically reproduced by an existing test; document that existing evidence when no new test is needed. Documentation-only and mechanical changes use the relevant semantic review and gates rather than manufacturing behavior tests.
