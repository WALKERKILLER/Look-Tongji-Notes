import 'dart:io';

/// Opens a file or folder with the platform's default handler.
Future<bool> openPath(String path) async {
  try {
    final r = Platform.isLinux
        ? await Process.run('xdg-open', [path])
        : Platform.isMacOS
            ? await Process.run('open', [path])
            : Platform.isWindows
                ? await Process.run('explorer', [path])
                : null;
    return r != null && r.exitCode == 0;
  } catch (_) {
    return false;
  }
}
