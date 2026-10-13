# Look Studio lives on an orphan `app` branch

## Status
Accepted
Class: process

## Context and Problem Statement
Look Studio (Flutter app, Go daemon, Node agent host) grew out of the Look-Tongji-Notes skill but shares none of its code: it only reads and exports the skill's file formats. It needed a home in the upstream repository while still in development, without disturbing the skill's `main` branch, its CI, or its releases.

## Decision Drivers
- The skill on `main` keeps working and releasing unchanged.
- Studio CI, branch rules and releases apply only to Studio code.
- The working directory used for development is the repository root, so tools and agents see one project.

## Considered Options
- An orphan `app` branch with Studio at the repository root.
- A `studio/` subdirectory on a branch from `main`.
- A separate repository.

## Decision Outcome
Chosen option: an orphan `app` branch with Studio at the root. The branch has its own workflows (`.github/workflows/ci.yml`, `release.yml`), its own ruleset, and release tags prefixed `studio-v` so they never collide with skill tags.

### Consequences
- Good: `main` and its workflows are untouched; Studio checks run only for Studio changes.
- Good: paths in docs, CI and governance are rooted at the Studio tree.
- Trade-off: the branch shares no history with `main`, so it cannot be merged there; moving Studio onto `main` later means a new decision.

## Pros and Cons of the Options
### Orphan `app` branch at the root
- Good: isolation of history, CI and rules; simple paths.
- Bad: unrelated histories; repository-level settings (default branch, README on the home page) still show the skill.

### `studio/` subdirectory branched from `main`
- Good: a later merge into `main` is possible.
- Bad: mixes skill and Studio files; `main` workflows and path filters must account for both.

### Separate repository
- Good: complete isolation.
- Bad: the owner asked for a branch in the upstream repository.

## Links
- [Look-Tongji-Notes](https://github.com/WALKERKILLER/Look-Tongji-Notes) — upstream repository; the skill lives on `main`.
