<img src="app/branding/icon-512.png" width="96" alt="Look Studio icon">

# Look Studio

> 🚧 开发中 / Work in progress — UI, APIs and data layout may change without notice.

Desktop client for Tongji's lecture-recording platform (look.tongji.edu.cn), built on the [Look-Tongji-Notes](https://github.com/WALKERKILLER/Look-Tongji-Notes) skill: browse and download lectures, transcribe them, and write notes with an embedded assistant.

| Directory | Contents |
| --- | --- |
| `app/` | Flutter UI (Material 3) |
| `lookd/` | Go daemon: login, Look API, downloads, transcription, SQLite index |
| `agent/` | Node.js host for the assistant (Pi Agent SDK) |

The app starts `lookd`, and `lookd` starts the agent. The app finds them through `LOOKD_BIN`, `LOOK_AGENT` and `LOOK_NODE`, then next to its executable (`Contents/Resources/agent` in the macOS app), then by walking up to `lookd/bin/lookd` and `agent/src/host.mjs` in a source checkout.

## Download

Each `studio-v*` release on the [releases page](https://github.com/WALKERKILLER/Look-Tongji-Notes/releases) carries:

| Platform | Files |
| --- | --- |
| Linux x64 and arm64 | `.deb` (Debian, Ubuntu), `.rpm` (Fedora, openSUSE), `.pkg.tar.zst` (Arch: `sudo pacman -U`), `.AppImage`, `.tar.gz` |
| Windows x64 | `-setup.exe` (per-user install, no admin rights) and a portable `.zip` |
| macOS (Apple silicon and Intel) | `.dmg` and `.zip` |

Install `ffmpeg` for transcription and Node.js 22+ for the assistant (or let the app install the assistant's runtime). The deb, rpm and Arch packages and the plain archive need GTK 3, libmpv 2 and glibc 2.39 or newer (Ubuntu 24.04, Debian 13, Fedora 40, Arch and later); the AppImage carries its own libmpv and runs from Ubuntu 22.04 on.

The builds are not code-signed yet. Windows SmartScreen may warn: choose "More info" → "Run anyway". On macOS, open the app once with right-click → Open, or run `xattr -dr com.apple.quarantine "/Applications/Look Studio.app"`.

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

Prebuilt bundles: the `look-studio-linux-bundle` artifact of each CI run, and the release packages above. `app/linux/packaging/package.sh` builds the same packages locally (it needs `nfpm` and `linuxdeploy` for the deb, rpm, Arch and AppImage formats).

### Windows — built for releases, lightly tested

Needs Visual Studio 2022 with "Desktop development with C++" (PowerShell):

```powershell
cd lookd; go build -trimpath -o bin\lookd.exe .\cmd\lookd; cd ..
cd agent; npm ci; cd ..
cd app; flutter build windows --release; cd ..
.\app\build\windows\x64\runner\Release\look_studio.exe
```

From a source checkout the app finds `lookd\bin\lookd.exe` and `agent\src\host.mjs` by itself, and Node.js on `PATH` or in `Program Files\nodejs`.

### macOS — built for releases, lightly tested

Needs Xcode and CocoaPods. The runner is not sandboxed, because the app starts `lookd`, which reads and writes `~/LookStudio`.

```sh
(cd lookd && go build -trimpath -o bin/lookd ./cmd/lookd)
(cd agent && npm ci)
(cd app && flutter build macos --release)
open "app/build/macos/Build/Products/Release/Look Studio.app"
```

Node.js is found on `PATH`, in `/usr/local/bin` or in `/opt/homebrew/bin`.

### Android — arm64 and x86_64, Android 7+

Needs the Android SDK and NDK (`flutter doctor --android-licenses`), Go and Python 3. `prepare.py` downloads the pinned Termux proot build and builds `lookd` for the APK; on first run the app downloads an Ubuntu base system and runs `lookd` and the assistant inside it (see [decision 0013](docs/decisions/0013-android-runs-lookd-in-a-proot-ubuntu-workspace.md)).

```sh
python3 app/android/workspace/prepare.py --abi arm64-v8a,x86_64
(cd app && flutter build apk --release --split-per-abi --target-platform android-arm64,android-x64)
# app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk, app-x86_64-release.apk
```

Without `app/android/key.properties` (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`) the APK is signed with the debug key, and installing a build signed with another key needs an uninstall first, which deletes the app's library. Release APKs are attached to `studio-v*` releases.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request; AI agents follow [AGENTS.md](AGENTS.md). Pull requests into `app` need green CI and approval from @WALKERKILLER. Design notes: [docs/overview.md](docs/overview.md) (features) and [docs/architecture.md](docs/architecture.md) (structure).

License: MIT.
