# repo-seed update strategy

The manifest is the authority for seeded ownership, capability state, governance paths, external sources of truth, and progressive artifact enforcement. Re-run the repo-seed skill to upgrade this layer; do not hand-copy upstream files.

## File ownership

- An untouched managed file may refresh from the current seed.
- A user-modified or user-owned file is preserved unless the user explicitly authorizes replacement or a merge.
- A file absent from the manifest is user content and is never overwritten or deleted automatically.
- A deleted managed file is not silently restored.
- Record-only updates hashes and adds newly introduced Core files that already exist; it does not edit governed files.

## Capability state

Capability state is `enabled`, `external`, `deferred`, or `declined`. Enabled capabilities remain managed when a later run omits legacy `--extensions` flags. Deferred or declined recommendations store a normalized assessment hash and are not raised again until relevant facts or assessment rules change. Existing equivalent systems are registered as `external`, not duplicated.

Core capability state includes `baseline`, `spec`, `decisions`, and `postmortems`. Baseline remains enabled in every managed repository; artifact capabilities may be repository-owned (`enabled`) or point to an adopted source (`external`). Core is never deferred or declined.

Read-only audits and dry-runs require no additional authority. Enabling a capability, installing a hook, changing governance policy or source-of-truth, connecting an external system, or removing capability files requires explicit user authorization.

## Adoption and paths

`governance.paths` records repository-specific architecture, testing, decision, Spec, and postmortem homes. `governance.externalSources` records authoritative systems outside those paths. Verifiers and generated links read this configuration so adoption does not force a migration or create a second authority.

## Artifact policy

New or materially changed Specs and postmortems use Artifact-Version 1. `artifactPolicy.legacy` may grandfather an existing unversioned record only at its recorded path and hash; editing that record requires migration to the current format.

## Safety

repo-seed never reads secrets, commits, pushes, changes remote services, installs hooks without authorization, overwrites custom hooks, or deletes user files.
