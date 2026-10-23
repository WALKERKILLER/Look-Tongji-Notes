import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/app_state.dart';
import 'core/deep_links.dart';
import 'core/lookd_service.dart';
import 'features/assistant/tasks_page.dart';
import 'features/login/login_page.dart';
import 'features/setup/workspace_setup_page.dart';
import 'shell.dart';
import 'theme/prefs.dart';
import 'theme/theme.dart';
import 'theme/tokens.dart';
import 'widgets/states.dart';
import 'l10n/l10n.dart';

/// App-wide snackbars and navigation for events that arrive on any screen.
final rootMessenger = GlobalKey<ScaffoldMessengerState>();
final rootNavigator = rootNavigatorKey;

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
        onGenerateTitle: (context) => l10n.appTitle,
        debugShowCheckedModeBanner: false,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        scaffoldMessengerKey: rootMessenger,
        navigatorKey: rootNavigator,
        theme: lightTheme,
        darkTheme: darkTheme,
        themeMode: prefs.themeMode,
        themeAnimationDuration: Motion.medium2,
        themeAnimationCurve: Motion.standard,
        builder: (context, child) {
          l10n = AppLocalizations.of(context);
          final mq = MediaQuery.of(context);
          return MediaQuery(
            data: mq.copyWith(
              textScaler: TextScaler.linear(prefs.textScale),
              disableAnimations: prefs.reduceMotion || mq.disableAnimations,
            ),
            child: TaskRunListener(messenger: rootMessenger, navigator: rootNavigator, child: child!),
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
    if (daemon.state == DaemonState.setup) {
      child = const WorkspaceSetupPage(key: ValueKey('setup'));
    } else if (daemon.state == DaemonState.failed) {
      child = Scaffold(
        key: const ValueKey('failed'),
        body: EmptyState(
          icon: Icons.power_off_rounded,
          title: l10n.appDaemonFailed,
          body: daemon.error,
          action: FilledButton.tonal(onPressed: daemon.restart, child: Text(l10n.appRestart)),
        ),
      );
    } else if (!app.connected || !app.authKnown) {
      child = Scaffold(key: ValueKey('splash'), body: CenteredLoader(label: l10n.commonStarting));
    } else if (!app.auth.signedIn && app.auth.status != 'needs_password') {
      child = const LoginPage(key: ValueKey('login'));
    } else {
      child = const AppShell(key: ValueKey('shell'));
      WidgetsBinding.instance.addPostFrameCallback((_) => DeepLinks.ready());
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
