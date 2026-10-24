# Android app

Artifact-Version: 1
Status: Draft

## Intent

Students want Look Studio on their Android phones with the same features as the desktop: downloads, transcription, notes, sync and every assistant (conversations, the resident bot, course agents, scheduled tasks, plugins). The desktop design depends on lookd (Go) and the agent host (Node.js and the Pi SDK) running as ordinary Linux processes, which Android does not offer to apps. Scope: run the unchanged lookd and agent in a private Ubuntu workspace started with proot, a first-run setup for it, Android adaptations of file and system interactions, and size-conscious release APKs. Non-goals: root, a terminal for the user, Google Play distribution, iOS, armeabi-v7a and 32-bit devices, background work while the app is swiped away.

Constraints: no code from AGPL projects (RikkaHub, Kelivo) — only their published approach is followed; GPL and LGPL binaries ship unmodified with their notice and source links; downloads are pinned by SHA-256; nothing leaves the app's private storage unless the user exports it.

## Contract

- **Native programs.** Android 10+ executes app files only from the native library folder, so the APK carries, per ABI (`arm64-v8a`, `x86_64`), Termux's `proot` 5.1.107.101 as `libproot.so` and its loader as `libproot_loader.so`, `libtalloc.so` (2.5.0; the `DT_NEEDED` entry in `libproot.so` is renamed from `libtalloc.so.2`), `libandroid-shmem.so` (0.7), and lookd for `linux/<arch>` (static, `-trimpath -s -w`, `timetzdata`) as `liblookd.so`. `useLegacyPackaging` extracts them at install; `PROOT_LOADER` points into the folder so the loader can execute. `android/workspace/prepare.py` downloads the debs from a Termux mirror, checks their SHA-256 and writes these files and the agent's sources (`assets/look/agent.tgz`, `agent.sha256`, `NOTICE`); they are build outputs outside Git.
- **Workspace.** First run shows 准备 Linux 工作区: the user picks a mirror (清华大学, 中国科学技术大学, Ubuntu 官方) and the app downloads `ubuntu-base-24.04.5-base-<arm64|amd64>.tar.gz`, verifies its SHA-256, unpacks it with `liblookd.so unpack <archive> <dir> <sha256>` (modes, symlinks and hard links kept, entries escaping the folder refused, progress `PROGRESS <bytes>` and `DONE` on stdout) into `files/ubuntu`, and writes DNS servers, hosts, apt sources for the chosen mirror and `.look-workspace`. Steps and download progress are shown; a failure shows its reason and 重试, keeping finished steps. Until the marker exists the daemon state is `setup`.
- **Guest processes.** Every guest command runs as `libproot.so --kill-on-exit --link2symlink -0 -r files/ubuntu -b /dev -b /proc -b /sys -b /system [-b /apex] -b <filesDir> -b <nativeDir>:/opt/look -w /root /usr/bin/env -i HOME=/root LANG=C.UTF-8 TZ=<phone zone> TERM PATH SSL_CERT_DIR=<Android CA folders> … <command>`. The app's files folder has the same path inside and out, so paths lookd reports open in the app; native programs appear at `/opt/look` because the real folder name contains `=`, which `env` would read as an assignment. lookd starts as `/opt/look/liblookd.so -exit-on-stdin-eof -data files/look-data -library files/LookStudio -agent files/agent/src/host.mjs` with `LOOKD_TOKEN` and `LOOK_DEVICE=<maker model>` (the device name in sync manifests and backups). Exits are restarted with backoff; after five the app shows the failure and 重新启动.
- **Assistant.** The agent's sources are unpacked from the APK into `files/agent` when their SHA-256 changes. Node.js and the npm dependencies are installed by the existing runtime setup ([spec 0008](0008-assistant-runtime-setup.md)) inside the guest, so all assistants, tools and plugins run as on desktop Linux. ffmpeg for transcription installs from 设置 → 诊断 (apt in the guest).
- **Android adaptations.** A foreground service (`dataSync`, a low-priority notification such as 正在处理 2 个下载或转写任务 or 正在同步数据) keeps the app and lookd running while downloads or transcriptions are queued or running, or a sync runs. Folder pickers become a path dialog, since the system picker returns `content://` addresses lookd cannot use; 打开文件夹 actions are hidden; files open through a `FileProvider` with the system chooser; backups are written through the system save dialog (`ACTION_CREATE_DOCUMENT`); cleartext HTTP is allowed only to `127.0.0.1` and `localhost`. Layouts use the existing compact size class (navigation bar, assistant FAB, phone variants of pages).
- **Pruning (amends [spec 0008](0008-assistant-runtime-setup.md), desktop included).** After unpacking Node.js the runtime setup deletes `include/`, `share/doc` and `CHANGELOG.md`; after `npm ci` it deletes TypeScript declarations (`*.d.ts`, `*.d.mts`, `*.d.cts`) and source maps (`*.js.map`, `*.mjs.map`, `*.cjs.map`, `*.ts.map`, `*.mts.map`, `*.cts.map`, `*.css.map`) under the agent's `node_modules`, and logs the space freed. `lookd prune <node_modules>…` applies the same rule to the agent bundled in desktop release packages. Measured on the emulator: Node.js 231 → 150 MB, agent 230 → 123 MB.
- **Release APKs.** `flutter build apk --release --split-per-abi --target-platform android-arm64,android-x64 --obfuscate --split-debug-info=<dir>`; one APK per ABI. Signed with the release key from `android/key.properties` when present, otherwise the debug key (updates then need a reinstall).

## Plan

1. `lookd/internal/rootfs` and the `unpack` command; `prepare.py`; Gradle packaging and signing.
2. App: `core/workspace.dart`, `core/android_bridge.dart`, `core/lookd_service.dart` (workspace launch), `features/setup/workspace_setup_page.dart`, `core/background_work.dart`, Android guards in pickers and file actions; `MainActivity.kt`, `WorkspaceService.kt`, manifest and resources.
3. CI: an Android job in the release workflow.
4. Docs: overview, architecture, testing; decision [0013](../decisions/0013-android-runs-lookd-in-a-proot-ubuntu-workspace.md).

## Verification

- `cd lookd && go test ./internal/rootfs` — unpacking, escapes, links, checksum.
- `cd lookd && go test ./internal/agentenv` — `TestPruneKeepsCode`.
- `cd app && flutter analyze && flutter test` — `test/workspace_test.dart` (proot command line, phone-size setup page), `test/webdav_page_test.dart` (phone widths).
- Manual on an emulator or phone: install the APK, prepare the workspace from a mirror, reach the login page; install the assistant runtime and run a chat with a tool call; sync to a WebDAV server both ways; export a backup; check times are local.

## Evidence

Pending until implementation is approved.
