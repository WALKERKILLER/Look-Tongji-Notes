# Development

English is the working language of this repository. This document covers contributor setup, daily workflow, and the commands that matter. Commands live in the root [AGENTS.md](../AGENTS.md); durable decision rationale lives in [docs/decisions](../docs/decisions/).

## Prerequisites

- Git
- Go 1.27 (pinned by `lookd/go.mod`), Node.js 22 or newer (CI uses 24), Flutter 3.47.7 stable and ffmpeg; Linux desktop builds also need clang, cmake, ninja, pkg-config and the GTK 3 and libmpv headers (the package list is in [ci.yml](../.github/workflows/ci.yml)).

## Daily workflow

1. Pull, branch, or stack per the repository's branching convention (see [CONTRIBUTING.md](../CONTRIBUTING.md)).
2. Make the change; update the applicable spec, durable decisions, docs, and the smallest sufficient behavior evidence in the same change.
3. Run the relevant gates:
   ```sh
   node scripts/run-gates.mjs
   ```
   An authorized pre-commit capability enforces the same runner; run it early even when no hook is installed.
4. Run the test command: `(cd lookd && go test -count=1 -race ./...) && (cd app && flutter test)`
5. Run the lint command: `(cd lookd && test -z "$(gofmt -l .)" && go vet ./...) && (cd agent && npm run check) && (cd app && flutter analyze --no-fatal-infos)`
6. Commit with a message that states the why; include a decision record reference when one changed.

## Source attribution

When an implementation is materially derived from a paper, article, community post, benchmark, research report, or copied/adapted code, preserve that provenance at the closest stable repository location:

- For a local algorithm, formula, constant, workaround, or behavior, add a nearby `Source:` comment with a descriptive title, a stable URL or DOI, and what the implementation derived from it.
- For a cross-cutting design, link the implementation entry point to the owning decision record and list the external sources in that record's `## Links` section.
- For generated, vendored, copied, or adapted material, retain the source header or metadata and satisfy the applicable copyright, license, and NOTICE requirements; a citation does not replace license compliance.
- For mutable community pages, include the relevant version or section and an access date when it helps future readers recover the cited evidence.

Routine language idioms and standard-library usage do not need citations. A pull request, issue, prompt, or chat transcript may supplement repository provenance but is never its only home because it can become detached from the implementation.

Example:

```text
// Source: "Exponential Backoff and Jitter" — https://aws.amazon.com/blogs/architecture/exponential-backoff-and-jitter/
// Derived: full jitter prevents synchronized retries.
```

## Working tree

Seeded governance files (AGENTS.md, CLAUDE.md, docs/, scripts/, .agents/skills/, .github/, CONTRIBUTING.md, LICENSE, .editorconfig, .gitattributes, .repo-seed/) are owned by the repo-seed skill's manifest. Hand-edit them only with intent; the manifest records their hash and the update mode preserves your edits.

## Editing docs

Follow [docs/AGENTS.md](AGENTS.md): one home per fact, tutorials vs references, hygiene checklist.
