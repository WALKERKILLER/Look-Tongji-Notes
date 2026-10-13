import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/app_state.dart';
import 'core/lookd_service.dart';
import 'features/login/login_page.dart';
import 'shell.dart';
import 'theme/prefs.dart';
import 'theme/theme.dart';
import 'theme/tokens.dart';
import 'widgets/states.dart';

class LookApp extends StatelessWidget {
  const LookApp({super.key});

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<UiPrefs>();
    return DynamicColorBuilder(builder: (light, dark) {
      final accent = light?.primary;
      final lightTheme = buildTheme(buildScheme(prefs, Brightness.light, systemAccent: accent), prefs);
      final darkTheme = buildTheme(buildScheme(prefs, Brightness.dark, systemAccent: dark?.primary ?? accent), prefs);
      return MaterialApp(
        title: 'Look Studio',
        debugShowCheckedModeBanner: false,
        theme: lightTheme,
        darkTheme: darkTheme,
        themeMode: prefs.themeMode,
        themeAnimationDuration: Motion.medium2,
        themeAnimationCurve: Motion.standard,
        builder: (context, child) {
          final mq = MediaQuery.of(context);
          return MediaQuery(
            data: mq.copyWith(
              textScaler: TextScaler.linear(prefs.textScale),
              disableAnimations: prefs.reduceMotion || mq.disableAnimations,
            ),
            child: child!,
          );
        },
        home: const RootGate(),
      );
    });
  }
}

/// Splash → daemon error → login → shell, with a fade-through between them.
class RootGate extends StatelessWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context) {
    final daemon = context.watch<LookdService>();
    final app = context.watch<AppState>();
    Widget child;
    if (daemon.state == DaemonState.failed) {
      child = Scaffold(
        key: const ValueKey('failed'),
        body: EmptyState(
          icon: Icons.power_off_rounded,
          title: '后台服务未能启动',
          body: daemon.error,
          action: FilledButton.tonal(onPressed: daemon.restart, child: const Text('重新启动')),
        ),
      );
    } else if (!app.connected || !app.authKnown) {
      child = const Scaffold(key: ValueKey('splash'), body: CenteredLoader(label: '正在启动'));
    } else if (!app.auth.signedIn && app.auth.status != 'needs_password') {
      child = const LoginPage(key: ValueKey('login'));
    } else {
      child = const AppShell(key: ValueKey('shell'));
    }
    return AnimatedSwitcher(
      duration: Motion.long2,
      switchInCurve: Motion.emphasizedDecelerate,
      switchOutCurve: Motion.emphasizedAccelerate,
      transitionBuilder: (c, a) => FadeTransition(
        opacity: a,
        child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(a), child: c),
      ),
      child: child,
    );
  }
}
