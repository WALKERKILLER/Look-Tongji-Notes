import 'package:flutter/services.dart';

/// The Android side of the app: MainActivity's "look/android" channel.
abstract final class AndroidBridge {
  static const _ch = MethodChannel('look/android');
  static Map<String, dynamic>? _info;

  /// nativeLibraryDir, filesDir, cacheDir, abi, sdk.
  static Future<Map<String, dynamic>> info() async => _info ??= (await _ch.invokeMapMethod<String, dynamic>('info'))!;

  /// Copies an asset the APK carries (android/app/src/main/assets) to [dest].
  static Future<void> extractAsset(String name, String dest) => _ch.invokeMethod('extractAsset', {'name': name, 'dest': dest});

  /// Opens a file in another app; false when none can show it.
  static Future<bool> openFile(String path) async => await _ch.invokeMethod<bool>('openFile', {'path': path}) ?? false;

  /// Offers a file to other apps (save to Files, send to a drive…).
  static Future<void> share(String path, {String? title}) => _ch.invokeMethod('share', {'path': path, 'title': title});

  /// Asks where to save a copy of [path] with the system's document
  /// screen; false when cancelled.
  static Future<bool> saveAs(String path, {required String name, required String mime}) async =>
      await _ch.invokeMethod<bool>('saveAs', {'path': path, 'name': name, 'mime': mime}) ?? false;

  /// Keeps the app running in the background with a notification.
  static Future<void> keepAlive(bool on, {String? text}) => _ch.invokeMethod('keepAlive', {'on': on, 'text': text});
}
