# Look Studio

> 🚧 开发中 / Work in progress — UI, APIs and data layout may change without notice.

Desktop client for Tongji's lecture-recording platform (look.tongji.edu.cn), built on the [Look-Tongji-Notes](https://github.com/WALKERKILLER/Look-Tongji-Notes) skill: browse and download lectures, transcribe them, and write notes with an embedded assistant.

| Directory | Contents |
| --- | --- |
| `app/` | Flutter UI (Material 3) |
| `lookd/` | Go daemon: login, Look API, downloads, transcription, SQLite index |
| `agent/` | Node.js host for the assistant (Pi Agent SDK) |

## Build

Requires Go 1.27, Node.js 22+, Flutter 3.47 and ffmpeg; on Linux also GTK 3 and libmpv.

```sh
(cd lookd && go build -o bin/lookd ./cmd/lookd)
(cd agent && npm ci)
(cd app && flutter run -d linux)
```

More: [docs/overview.md](docs/overview.md). CI runs on every push and pull request to `app`; tags `studio-v*` publish a Linux pre-release.

License: MIT.
