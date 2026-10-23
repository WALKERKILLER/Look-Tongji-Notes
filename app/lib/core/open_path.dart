import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import 'android_bridge.dart';

/// Whether folders can be shown in a file manager. Android apps keep their
/// files private, so there is none to show them in.
bool get canOpenFolders => !Platform.isAndroid;

/// Opens a file or folder with the platform's default handler. On Android
/// files open in another app, web addresses in the browser, folders not at
/// all.
Future<bool> openPath(String path) async {
  if (Platform.isAndroid) {
    final uri = Uri.tryParse(path);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) return launchUrl(uri, mode: LaunchMode.externalApplication);
    return AndroidBridge.openFile(p.normalize(path));
  }
  path = p.normalize(path);
  try {
    if (Platform.isWindows) {
      // explorer.exe exits with 1 even when it opened the path.
      await Process.start('explorer', [path], mode: ProcessStartMode.detached);
      return FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound;
    }
    final r = Platform.isLinux
        ? await Process.run('xdg-open', [path])
        : Platform.isMacOS
            ? await Process.run('open', [path])
            : null;
    return r != null && r.exitCode == 0;
  } catch (_) {
    return false;
  }
}

/// Shows a file or folder selected in the system file manager: Finder on
/// macOS, Explorer on Windows, and on Linux whichever manager implements
/// org.freedesktop.FileManager1 (Files, Dolphin, Nemo, Thunar…), falling
/// back to opening the parent folder.
Future<bool> revealPath(String path) async {
  path = p.normalize(path);
  if (Platform.isAndroid) return AndroidBridge.openFile(path);
  try {
    if (Platform.isMacOS) return (await Process.run('open', ['-R', path])).exitCode == 0;
    if (Platform.isWindows) {
      await Process.start('explorer', ['/select,', path], mode: ProcessStartMode.detached);
      return FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound;
    }
    if (Platform.isLinux) {
      final r = await Process.run('dbus-send', [
        '--session',
        '--print-reply',
        '--dest=org.freedesktop.FileManager1',
        '--type=method_call',
        '/org/freedesktop/FileManager1',
        'org.freedesktop.FileManager1.ShowItems',
        'array:string:${Uri.file(path)}',
        'string:',
      ]);
      if (r.exitCode == 0) return true;
    }
  } catch (_) {
    // No D-Bus tools; fall through.
  }
  return openPath(FileSystemEntity.isDirectorySync(path) ? path : p.dirname(path));
}
