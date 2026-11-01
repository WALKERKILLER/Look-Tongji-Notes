# Study workspace build dependencies

This reference describes the additional runtime dependencies of the native study workspace. The source builds directly with the toolchains in the [development guide](development.md); no installed application, private runner, local signing key or staging overlay is required.

## PDF rendering

On macOS, compile [study-pdf.swift](../scripts/desktop/study-pdf.swift) using `swiftc -O -framework PDFKit -framework AppKit` and place the resulting `look-study-pdf` executable beside `lookd`. The helper is not yet integrated into the upstream release workflow. A maintainer must add both architecture builds and bundle the helper before the application signing step. PDFKit is provided by macOS. Development builds need the same helper beside their daemon executable.

Linux and Android's Ubuntu workspace use the `pdfinfo`, `pdftoppm` and `pdftotext` executables from Poppler. Android workspace setup installs `poppler-utils`; existing workspaces can install it from Settings → Diagnostics. Linux users must install their distribution's Poppler tools. Conversion has page, pixel, byte and time limits; source PDFs remain in the lecture library. Windows PDF conversion and native packaging acceptance are pending; imported images, text and already-rendered synchronized pages do not require PDF conversion.

## macOS packaging integration

From the repository root, after creating `lookd/bin`, build a universal helper:

```sh
for arch in arm64 x86_64; do
  xcrun swiftc -O -target "$arch-apple-macos11.0" -framework PDFKit -framework AppKit scripts/desktop/study-pdf.swift -o "lookd/bin/look-study-pdf-$arch"
done
lipo -create -output lookd/bin/look-study-pdf lookd/bin/look-study-pdf-arm64 lookd/bin/look-study-pdf-x86_64
```

Copy `lookd/bin/look-study-pdf` into the built application’s `Contents/MacOS` beside `lookd` before the existing signing step. An ordinary release without this step cannot import or render new PDFs on macOS. This contribution does not modify GitHub Actions workflow files; release integration remains a maintainer prerequisite.

## Android stylus and folder access

The Android build includes AndroidX motion prediction and Huawei's Pencil Engine API through their official Maven repositories. Device support is optional: predictions are transient and never saved; unsupported devices retain ordinary Flutter ink input. The system folder picker grants access only to the chosen sync tree. No private signing material or personal Syncthing configuration is included.

## Validation boundary

The contributor's macOS and Huawei Android deployment exercised the study canvas, native PDF helper, folder synchronization and persisted folder permission. That deployment used separately packaged test applications. Those observations do not establish that the upstream release workflow or this rebased contribution has completed native builds on every platform. Windows and Linux device acceptance remain pending. The pull request reports checks actually run on its own revision.
