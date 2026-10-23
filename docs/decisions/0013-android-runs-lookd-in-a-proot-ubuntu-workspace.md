# Android runs lookd and the agent in a proot Ubuntu workspace

## Status
Proposed
Class: feature

## Context and Problem Statement
The Android app should offer what the desktop offers ([draft spec: Android app](../specs/draft-android-app.md)), including every assistant. On desktop the app starts lookd, a Go program, which supervises a Node.js agent host built on the Pi SDK; the agent installs npm packages, plugins may start programs, and transcription runs sherpa-onnx and ffmpeg. Android apps cannot run arbitrary Linux programs: since Android 10 an app may execute files only from its native library folder, there is no glibc, and there is no Node.js. How should the phone run this stack?

## Decision Drivers
- Every assistant, tool and plugin works as on desktop, without a second implementation.
- No root, no separate terminal app, nothing system-wide.
- A reasonable APK size and first-run download, with mirrors that work in China.
- No AGPL code (RikkaHub and Kelivo are AGPL-3.0); GPL binaries only as unmodified, separately noticed programs.

## Considered Options
- An Ubuntu base system run with proot from the native library folder; lookd and Node.js run inside unchanged.
- lookd built for `GOOS=android` as a native library plus a Node.js build for Android (nodejs-mobile or Termux's).
- A thin client: the phone only talks to lookd on the user's computer.
- Rewriting the agent host for the phone (Dart or Kotlin).

## Decision Outcome
Chosen option: proot with an Ubuntu base. The APK carries Termux's proot, its loader and libraries, and lookd as `lib*.so` files that Android extracts and lets the app execute; `PROOT_LOADER` in the same folder sidesteps the W^X rule for the loader, and proot maps guest programs instead of executing them from app storage, which is the approach RikkaHub and other proot-based apps publish. On first run the app downloads the 30 MB Ubuntu base from a chosen mirror, verified by SHA-256. Inside, glibc programs work as on desktop Linux: the existing runtime setup installs official Node.js builds and the agent's npm dependencies, apt installs ffmpeg, and plugins find a normal shell. The app's files folder is bound at the same path so paths cross the boundary unchanged.

### Consequences
- Good: one code path for lookd, the agent and plugins on desktop Linux and Android; desktop fixes reach the phone.
- Good: the APK stays near 25 MB per ABI; Node.js and the agent's packages (about 280 MB on disk once headers, declarations and source maps are pruned) download only when the assistant is set up.
- Trade-off: proot intercepts system calls with ptrace, so process start and file-heavy work are slower than native; lookd's Go code is unaffected between calls.
- Trade-off: the Ubuntu workspace takes about 140 MB, and ffmpeg is a separate apt install.
- Trade-off: proot behaviour can depend on the Android kernel and vendor; the setup reports failures and the app keeps the log.
- Trade-off: the shipped proot is GPL-2.0 and talloc LGPL; the APK carries a NOTICE with source links and the binaries stay unmodified apart from the talloc soname entry.

## Pros and Cons of the Options
### proot with an Ubuntu base
- Good: unchanged Linux binaries, npm packages with native parts, apt for tools.
- Bad: slower system calls, an extra first-run download.

### Native Android builds of lookd and Node.js
- Good: no ptrace overhead, smaller footprint.
- Bad: nodejs-mobile lags Node.js releases and cannot spawn a separate node; Termux's Node.js expects Termux's prefix; npm packages with prebuilt Linux binaries and plugins that start programs break; two build matrices to maintain.

### Thin client to the desktop
- Good: tiny app.
- Bad: useless away from the computer, needs networking between devices and exposes lookd beyond localhost.

### Rewriting the agent host
- Good: native performance.
- Bad: the Pi SDK, tools and plugins are JavaScript; a rewrite forks every feature.

## Links
- [Draft spec: Android app](../specs/draft-android-app.md)
- [Spec 0008: assistant runtime setup](../specs/0008-assistant-runtime-setup.md)
- [termux/proot](https://github.com/termux/proot) and [Termux proot package](https://github.com/termux/termux-packages/tree/master/packages/proot)
- [Android 10 behaviour change: execute permission for app home](https://developer.android.com/about/versions/10/behavior-changes-10#execute-permission)
- [RikkaHub (AGPL-3.0, approach only)](https://github.com/rikkahub/rikkahub)
- [Ubuntu base images](https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release/)
