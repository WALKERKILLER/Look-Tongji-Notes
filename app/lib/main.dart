import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/activity_tracker.dart';
import 'core/app_state.dart';
import 'core/deep_links.dart';
import 'core/lookd_service.dart';
import 'core/plugins.dart';
import 'core/profile.dart';
import 'features/assistant/assistant_controller.dart';
import 'features/assistant/task_inbox.dart';
import 'features/schedule/schedule_store.dart';
import 'features/schedule/schedule_widgets.dart';
import 'theme/prefs.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final desktop = Platform.isLinux || Platform.isWindows || Platform.isMacOS;
  if (desktop) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(size: Size(1320, 860), minimumSize: Size(380, 560), title: 'Look Studio', center: true),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }
  final prefs = await UiPrefs.load();
  final profile = await UserProfile.load();
  final daemon = LookdService();
  unawaited(daemon.start());
  final app = AppState(daemon);
  unawaited(app.init());
  ActivityTracker.instance = ActivityTracker(app);
  final screen = ScreenContext();
  final players = PlayerHub();

  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: prefs),
      ChangeNotifierProvider.value(value: profile),
      ChangeNotifierProvider.value(value: daemon),
      ChangeNotifierProvider.value(value: app),
      ChangeNotifierProvider.value(value: screen),
      ChangeNotifierProvider.value(value: players),
      ChangeNotifierProvider(create: (_) => AssistantController(app, screen, players)),
      ChangeNotifierProvider(create: (_) => ScheduleStore(app)),
      ChangeNotifierProvider(create: (_) => TaskInbox(app)),
      ChangeNotifierProvider(create: (_) => PluginStore(app)),
      ChangeNotifierProvider(create: (_) => ScheduleFocus()),
    ],
    child: const LookApp(),
  ));
  unawaited(DeepLinks.start());
}
