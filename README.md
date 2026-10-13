# Look Studio

> 🚧 开发中 / Work in progress — UI, APIs and data layout may change without notice.

Desktop client for Tongji's lecture-recording platform (look.tongji.edu.cn), built on the [Look-Tongji-Notes](https://github.com/WALKERKILLER/Look-Tongji-Notes) skill: browse and download lectures, transcribe them, and write notes with an embedded assistant.

| Directory | Contents |
| --- | --- |
| `app/` | Flutter UI (Material 3) |
| `lookd/` | Go daemon: login, Look API, downloads, transcription, SQLite index |
| `agent/` | Node.js host for the assistant (Pi Agent SDK) |

The app starts `lookd`, and `lookd` starts the agent. The app finds them through `LOOKD_BIN`, `LOOK_AGENT` and `LOOK_NODE`, then next to its executable, then by walking up to `lookd/bin/lookd` and `agent/src/host.mjs` in a source checkout.

## Build from source

Common requirements: Go 1.27, Node.js 22 or newer, Flutter 3.47.7 (stable), and `ffmpeg` on `PATH` for transcription.

```sh
git clone -b app https://github.com/WALKERKILLER/Look-Tongji-Notes.git look-studio
cd look-studio
```

### Linux — supported, built in CI

```sh
# Debian/Ubuntu packages; use your distribution's equivalents elsewhere
sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libmpv-dev ffmpeg
(cd lookd && go build -trimpath -o bin/lookd ./cmd/lookd)
(cd agent && npm ci)
(cd app && flutter build linux --release)
./app/build/linux/x64/release/bundle/look_studio
```

Prebuilt bundles: the `look-studio-linux-bundle` artifact of each CI run, and `studio-v*` pre-releases.

### Windows — experimental, untested

Needs Visual Studio 2022 with "Desktop development with C++". The `windows/` runner is not committed yet, so generate it first. Automatic discovery assumes Unix names, so point the app at the daemon, agent and Node explicitly (PowerShell):

```powershell
cd lookd; go build -trimpath -o bin\lookd.exe .\cmd\lookd; cd ..
cd agent; npm ci; cd ..
cd app; flutter create --platforms=windows .; flutter build windows --release; cd ..
$env:LOOKD_BIN  = "$PWD\lookd\bin\lookd.exe"
$env:LOOK_AGENT = "$PWD\agent\src\host.mjs"
$env:LOOK_NODE  = (Get-Command node).Source
.\app\build\windows\x64\runner\Release\look_studio.exe
```

### macOS — experimental, untested

Needs Xcode and CocoaPods. The `macos/` runner is not committed yet. Flutter's generated runner is sandboxed, which blocks starting `lookd`; set `com.apple.security.app-sandbox` to `false` in `app/macos/Runner/DebugProfile.entitlements` and `Release.entitlements` before building.

```sh
(cd lookd && go build -trimpath -o bin/lookd ./cmd/lookd)
(cd agent && npm ci)
(cd app && flutter create --platforms=macos .)
# edit the two entitlements files as described above
(cd app && flutter build macos --release)
# start from a terminal so the app inherits PATH (Node, ffmpeg)
./app/build/macos/Build/Products/Release/look_studio.app/Contents/MacOS/look_studio
```

### Android — UI only

Needs the Android SDK (`flutter doctor --android-licenses`).

```sh
(cd app && flutter build apk --release)   # app/build/app/outputs/flutter-apk/app-release.apk
```

Gradle ignores `https_proxy`; behind a proxy, pass Java proxy settings, for example `JAVA_TOOL_OPTIONS="-Dhttps.proxyHost=127.0.0.1 -Dhttps.proxyPort=7890"`. The APK contains only the Flutter UI and is signed with the debug key. `lookd` and the agent are not packaged for Android, so the app reports that it cannot find `lookd`.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request; AI agents follow [AGENTS.md](AGENTS.md). Pull requests into `app` need green CI and approval from @WALKERKILLER. Design notes: [docs/overview.md](docs/overview.md) (features) and [docs/architecture.md](docs/architecture.md) (structure).

License: MIT.
