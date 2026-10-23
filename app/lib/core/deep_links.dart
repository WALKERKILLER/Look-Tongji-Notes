import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../features/player/player_page.dart';

/// The app's root navigator, so links from other programs can open screens.
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Receives `lookstudio://` links that the operating system hands to the app
/// (the Linux runner and the Android activity, over the `look/links`
/// channel), for example a timestamp clicked in an exported Obsidian note.
/// Links wait until the main screen is up, then open.
class DeepLinks {
  static const _channel = MethodChannel('look/links');
  static final _pending = <Uri>[];
  static bool _ready = false;

  static Future<void> start() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'open' && call.arguments is String) _receive(call.arguments as String);
    });
    try {
      final initial = await _channel.invokeListMethod<String>('initial') ?? const <String>[];
      initial.forEach(_receive);
    } on MissingPluginException {
      // No native side on this platform yet.
    }
  }

  /// Called once the signed-in shell is showing.
  static void ready() {
    if (_ready) return;
    _ready = true;
    _flush();
  }

  static void _receive(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme != 'lookstudio') return;
    _pending.add(uri);
    _flush();
  }

  static void _flush() {
    final context = rootNavigatorKey.currentContext;
    if (!_ready || context == null) return;
    final links = List.of(_pending);
    _pending.clear();
    for (final uri in links) {
      if (uri.host != 'lecture' || uri.pathSegments.isEmpty) continue;
      final id = uri.pathSegments.first;
      final t = int.tryParse(uri.queryParameters['t'] ?? '');
      if (t != null) {
        seekOrOpen(context, id, t);
      } else {
        Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => PlayerPage(lectureId: id)));
      }
    }
    if (links.isNotEmpty && (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
      windowManager.show();
      windowManager.focus();
    }
  }
}
