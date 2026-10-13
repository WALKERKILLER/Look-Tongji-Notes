# Contributing

Thank you for considering contributing to Look Studio. This repository is agent-native: human and AI contributors follow the same governance loop. Look Studio is in development, so expect breaking changes.

## Branches

- `app` is the integration branch for Look Studio. It is an orphan branch of Look-Tongji-Notes and never merges with `main` ([decision 0004](docs/decisions/0004-studio-on-an-orphan-app-branch.md)).
- Work on a short-lived branch from `app`, named by type: `feat/…`, `fix/…`, `docs/…`, `ci/…`, `refactor/…`, `chore/…`. Contributors without write access work on a fork.
- Every change reaches `app` through a pull request. The `app` ruleset blocks deletion and force-pushes, and requires the CI checks `governance (gates)`, `lookd (Go)`, `agent (Node)` and `app (Flutter)` plus an approving review from the code owner @WALKERKILLER ([CODEOWNERS](CODEOWNERS)). CI runs a part's job only when the change touches that part (`app/`, `lookd/`, `agent/`, or the CI workflow); Markdown-only changes run just the gates, and skipped jobs count as passed.
- Releases are tags `studio-vX.Y.Z` on `app`; [release.yml](.github/workflows/release.yml) publishes them as Linux pre-releases.

## Governance loop

1. Read [AGENTS.md](AGENTS.md) and [docs/AGENTS.md](docs/AGENTS.md) before making changes.
2. Write a decision record only when the change selects among meaningful alternatives; risk-boundary changes use an Approved spec in [docs/specs/](docs/specs/).
3. Run the gates before committing; an authorized pre-commit hook enforces the same runner:
   ```sh
   node scripts/run-gates.mjs
   ```
4. Name the regression risk and add or update the smallest test set that proves the affected contract; a fix without reproducible evidence is a rumor.
5. If the change closes a subtle or systemic escaped failure, add a postmortem in [docs/postmortems/](./docs/postmortems/) linked to the permanent guardrail.

## Local checks

Build instructions per platform are in the [README](README.md#build-from-source). Before pushing, run the gates, test and lint commands listed in [AGENTS.md](AGENTS.md#commands); CI runs the same set on Linux.

## Commits and pull requests

- Commit messages and pull request titles use `type(scope): summary`, where type is `feat`, `fix`, `docs`, `ci`, `refactor`, `test` or `chore`, and scope is `app`, `lookd`, `agent`, or omitted for cross-cutting changes. Example: `fix(lookd): resume ASR chunks after restart`.
- Keep one topic per pull request and fill in the [template](.github/pull_request_template.md): what changed, why, affected parts, platforms tested, and verification.
- UI changes include a screenshot or short recording.
- Never commit credentials, local data (`~/LookStudio/`, `~/.local/share/look-studio/`), build outputs, or code copied from GPL/AGPL projects; see the project rules in [AGENTS.md](AGENTS.md#project-rules).
- Pull requests are squash- or rebase-merged by the code owner after approval.

## Decision records

Durable architecture and process decisions use MADR in `docs/decisions/`. Follow the `repo-decisions` skill and [.repo-seed/update-strategy.md](.repo-seed/update-strategy.md) for the format. A superseded record is never rewritten; a new record supersedes it.

## Reviews

Reviewers, human or AI, use the `repo-review` skill ([.agents/skills/repo-review/SKILL.md](.agents/skills/repo-review/SKILL.md)).

## Code of conduct

Be respectful and constructive. Assume good faith.
