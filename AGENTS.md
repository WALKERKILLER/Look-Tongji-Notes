# AGENTS.md

Look Studio is a work-in-progress desktop client for Tongji's lecture-recording platform (look.tongji.edu.cn): a Flutter UI in `app/`, a Go daemon in `lookd/`, and a Node.js assistant host in `agent/`. It lives on the `app` branch of Look-Tongji-Notes; `main` holds the skill and shares no history with this branch.

## Repository governance

This repository's governance layer is managed by repo-seed; product code remains repository-owned. [`.repo-seed/manifest.json`](.repo-seed/manifest.json) is authoritative for managed files, capability state, governance paths, external sources of truth, and the installed repo-seed version.

Route governance work explicitly:

- Change or pull-request review must use `repo-review`.
- A durable choice with meaningful alternatives must use `repo-decisions`.
- New complexity, delivery, ownership, security, release, or incident signals must use `repo-governance`.
- Seeding, adoption, governance-layer upgrades, or upstream repair must use the global `repo-seed` skill. If it is unavailable, stop and ask rather than hand-copying upstream governance.
- Ordinary implementation follows this file and the linked project documents without invoking repo-seed again.

If automatic skill activation is unavailable, read the linked resident `SKILL.md` directly and follow it.

## Repository layout

See [docs/architecture.md](docs/architecture.md) for the module map and seams. Directories named there are the canonical layout; anything else is user code.

## Code readability

Write code for human readers. Keep the primary logic path visible; introduce an abstraction only when it hides more complexity than its indirection adds; choose names that reveal domain meaning, effects, and cost; use one repository term per concept; and keep behavior within its owning boundary.

## Commands

- Test: `(cd lookd && go test -count=1 -race ./...) && (cd agent && npm test) && (cd app && flutter test)`
- Lint: `(cd lookd && test -z "$(gofmt -l .)" && go vet ./...) && (cd agent && npm run check) && (cd app && flutter analyze --no-fatal-infos)`
- Gates: `node scripts/run-gates.mjs`

Run relevant tests while working and the shared gate runner before every commit. CI or an installed pre-commit hook may repeat the exhaustive matrix.

## Governance loop (hard rules)

1. Run the gates before every commit; install the optional pre-commit capability only with user authorization.
2. Record a decision in [docs/decisions/](docs/decisions/) when a change chooses among meaningful alternatives whose rationale may be revisited; decisions are not a change log.
3. Risk-boundary changes start from an Approved spec in [docs/specs/](docs/specs/); routine changes are exempt.
4. A subtle, systemic, or costly escaped failure earns a postmortem in [docs/postmortems/](docs/postmortems/) linked to a permanent guardrail.
5. Implementation materially derived from an external source retains provenance at the closest stable repository location; follow [docs/development.md](docs/development.md#source-attribution).
6. The only upgrade channel for the seeded governance layer is re-running the repo-seed skill. Never hand-edit seeded files to "match upstream"; re-run the skill instead.

## Project rules

- Credentials stay inside lookd: the Tongji session and password, the MinerU token and provider API keys are never logged, committed, or returned by an API (the MinerU token only as its last 4 characters). User data under `~/LookStudio/` and `~/.local/share/look-studio/` never enters the repository.
- Course agents and chats write only notes, schedule marks, outlines and quizzes. The resident bot also keeps memory files and operates the app as [spec 0007](docs/specs/0007-resident-bot-and-course-agents.md) defines: downloads, file deletion, scheduled tasks, plugin switches and download, transcription or model settings run only when the user applies a card. Note overwrite and transcript-coverage guards in `agent/src/tools.mjs`, the memory guard in `agent/src/memory.mjs` and the card operations in `agent/src/operate.mjs` change only through an Approved spec.
- Do not copy code from GPL/AGPL projects; reimplement from protocols and documentation with provenance, and keep third-party asset `NOTICE` files.
- A lookd route or JSON field change updates both clients (`app/lib/core/api.dart`, `agent/src/lookd.mjs`) in the same change.

## Security rules

- Never `git commit` or `git push` unless the user explicitly asks.
- Never modify files outside the seeded paths (AGENTS.md, CLAUDE.md, docs/, scripts/, .agents/skills/, .github/, CONTRIBUTING.md, LICENSE, .editorconfig, .gitattributes, .repo-seed/) without asking.
- Never read `.env` files or other secrets.

## Documentation

Follow [docs/AGENTS.md](docs/AGENTS.md): one home per fact, tutorials vs references, hygiene checklist.

## Decisions

Durable architecture and process decisions use MADR in `docs/decisions/`. Status flows Proposed → Accepted → Superseded by NNNN. A superseded record is never rewritten into its opposite.

## Governance evolution

Use the `repo-governance` skill when complexity, delivery, ownership, security, release, or incident signals change. Read-only audits and dry-runs are autonomous. Ask before enabling a capability, installing a hook, changing policy/source-of-truth, or connecting an external system. Raise blocking recommendations before implementation and advisory recommendations in the handoff; do not repeat a declined recommendation until its assessment hash changes.

## Testing

Follow [docs/testing.md](docs/testing.md). Name the regression risk, then choose the smallest test set at the lowest sufficiently real boundary; verify observable outcomes rather than implementation details.

## Skills

- [`.agents/skills/repo-review`](.agents/skills/repo-review/SKILL.md) — semantic review policy (instantiated per project) before merging.
- [`.agents/skills/repo-decisions`](.agents/skills/repo-decisions/SKILL.md) — how to write and update decision records.
- [`.agents/skills/repo-governance`](.agents/skills/repo-governance/SKILL.md) — progressive capability assessment, authorization, and upgrades.

## Enabled optional capabilities

- CI is an existing mechanism (`ci` capability: external). [.github/workflows/ci.yml](.github/workflows/ci.yml) runs the gates on every push and pull request to `app`, and the Go, Node and Flutter checks only for the parts a change touches (Markdown-only changes skip them); publishing a `studio-v*` release or pre-release builds Linux, Windows and macOS packages and attaches them through [.github/workflows/release.yml](.github/workflows/release.yml).
- Path-level owners live in [CODEOWNERS](CODEOWNERS). The `app` branch ruleset requires an approving code-owner review (@WALKERKILLER) and green CI checks on every pull request.
