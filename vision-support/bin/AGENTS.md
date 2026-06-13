<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-06-13 | Updated: 2026-06-13 -->

# bin

## Purpose
Contains the npm CLI entry point and postinstall script for the vision-support package. The CLI entry (`cli.mjs`) resolves the main script location and forwards all arguments to `scripts/vision.mjs`. The postinstall script (`postinstall.mjs`) automatically copies skill files to known agent skill directories after `npm install -g vision-support`.

## Key Files

| File | Description |
|------|-------------|
| `cli.mjs` | CLI entry point invoked via `vision-support` command; resolves and delegates to `scripts/vision.mjs` |
| `postinstall.mjs` | Npm postinstall hook that installs skill files to `.agents/skills`, `.pi/agent/skills`, and `.claude/skills` |

## Subdirectories

*None*

## For AI Agents

### Working In This Directory
These files are entry points only -- they do not contain core logic. Actual vision-support logic lives in `../scripts/vision.mjs`. When modifying the CLI, ensure argument forwarding preserves quoting and handles edge cases (empty args, special characters). The postinstall script must remain idempotent and fail silently to avoid breaking npm install.

### Testing Requirements
Test the CLI by running `node bin/cli.mjs --help` from the package root or via `npm link` then `vision-support`. Verify postinstall by running `node bin/postinstall.mjs` and checking target skill directories.

### Common Patterns
- ES module (`import`/`export`) syntax throughout
- `process.argv.slice(2)` for argument forwarding
- `execFileSync` with `stdio: "inherit"` for subprocess delegation
- Silent failure (empty catch) in postinstall to avoid breaking npm
- Directory resolution via `import.meta.url` + `fileURLToPath`

## Dependencies

### Internal
- `../scripts/vision.mjs` -- main script invoked by `cli.mjs`
- `../SKILL.md`, `../config.example.json`, `../references/` -- files copied by postinstall

### External
- Node.js built-ins: `path`, `fs`, `os`, `child_process`, `url`
