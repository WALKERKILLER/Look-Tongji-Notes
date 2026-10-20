# Assistant runtime setup

Artifact-Version: 1
Status: Approved

## Intent
The assistant needs Node.js 22 or later and the agent's npm dependencies, which include the Pi SDK. Release packages bundle the dependencies but not Node.js, and a development checkout has neither until someone runs `npm ci`. Without them the assistant panel only says that the assistant did not start, and the user has to install things by hand.

Outcome: when either is missing, the app offers one button that sets the runtime up inside Look Studio's private data directory and starts the assistant, with progress and a clear error when a step fails.

This downloads and runs executables, so the sources are fixed (two mirrors of the official Node.js builds and npm registry), every archive is checked against the release's published SHA-256 sums, package install scripts are disabled, and nothing is installed system-wide.

Non-goals: installing or updating a system Node.js, upgrading the agent's dependencies (the lockfile decides), custom mirror URLs, automatic updates of the managed Node.js.

## Contract

### State
`GET /api/agent/runtime` →
```json
{"node": {"path", "version", "source": "flag|managed|none", "ok"},
 "deps": {"ok", "dir"},
 "install": {"state": "idle|running|done|failed", "step", "progress", "error", "log": []}}
```
- `node.ok`: the binary runs and reports major version ≥ 22.
- `deps.ok`: `<agent dir>/node_modules/@earendil-works/pi-coding-agent/package.json` exists (agent dir = the directory above `src/host.mjs`).
- `install.log`: the last 40 lines of install output; it holds no credentials (none are used).

### Install
`POST /api/agent/runtime/install {mirror: "npmmirror"|"official"}` starts the install in the background and returns the state; another mirror value → 400; 409 while an install runs.
1. Node.js, skipped when `node.ok`:
   - resolve: read `index.json` from the mirror (`https://npmmirror.com/mirrors/node/` or `https://nodejs.org/dist/`) and pick the newest release whose major version is 24 and that is marked LTS;
   - download `node-<version>-<os>-<arch>.tar.gz` (`linux`, `darwin`; `x64`, `arm64`) or `node-<version>-win-x64.zip` into `<data>/runtime/.download/`, reporting progress;
   - verify its SHA-256 against `SHASUMS256.txt` of the same release; a missing or different sum fails the install and deletes the file;
   - extract into a temporary directory under `<data>/runtime/` and rename it to `<data>/runtime/node-<version>`. Entries with absolute paths, `..`, or links pointing outside the directory are refused; only regular files, directories and in-tree symlinks are written;
   - record `{node, version}` in `<data>/runtime/runtime.json`.
2. Dependencies, skipped when `deps.ok`: run `npm ci --omit=dev --ignore-scripts --no-audit --no-fund --registry <registry>` in the agent directory with the chosen Node.js first in `PATH` (registry `https://registry.npmmirror.com` or `https://registry.npmjs.org`), at most 10 minutes. A read-only agent directory fails with a message naming it.
3. Restart the agent host with the chosen Node.js.
- Each step updates `install` and publishes `runtime` on the event bus. A failure keeps what earlier steps installed and can be retried.

### Startup
lookd uses `-node` when given (`source: flag`); otherwise the Node.js recorded in `runtime.json` when it exists (`managed`). The agent supervisor can be restarted with another binary; a supervisor that had no Node.js waits for one instead of exiting.

### App
- When the assistant is not running because Node.js or the dependencies are missing, the assistant panel shows a card 安装助手运行环境: what will be installed and where, the source (国内镜像 default, 官方源), 开始安装, then a step list (Node.js, 依赖, 启动) with a progress bar, the log in an expandable section, and 重试 on failure.
- 设置 → 助手 shows 运行环境: Node.js version and source, dependencies, and 修复 (the same install).

## Plan
1. lookd: `internal/runtime` (resolve, download, verify, extract, npm, state), routes, supervisor restart and wait, startup fallback.
2. Clients: `api.dart` and `lookd.mjs` route list; app card and settings tile.

## Verification
- `go test`: version resolution from an `index.json`; checksum mismatch refused and the file removed; extraction refusing `..`, absolute paths and escaping links; deps step command line and timeout with a fake npm; state transitions and 409; supervisor restart after waiting without Node.js.
- Widget test: the install card's steps, progress and failure.
- Live: with `LOOK_NODE` pointing nowhere and no system Node.js on `PATH`, the app installs Node.js into the data directory and the assistant starts.

## Evidence
Pending until implementation.
