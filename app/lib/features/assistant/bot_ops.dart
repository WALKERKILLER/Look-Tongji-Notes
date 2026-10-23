import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app.dart';
import '../../core/app_state.dart';
import '../../shell.dart';
import '../../theme/prefs.dart';
import '../activity/activity_page.dart';
import '../courses/course_page.dart';
import '../library/note_reader.dart';
import '../player/lecture_player.dart';
import '../player/player_page.dart';
import '../schedule/schedule_widgets.dart';
import '../settings/settings_page.dart';
import '../usage/usage_page.dart';
import 'bot_page.dart';
import '../../l10n/l10n.dart';

// The app side of the bot operating the app (details.app of its tools,
// docs/specs/0007-resident-bot-and-course-agents.md): navigation, the open
// player and preferences.

final kOpenTargets = <String, String>{
  'home': l10n.screenHome,
  'courses': l10n.commonCourses,
  'course': l10n.commonCourses,
  'lecture': l10n.commonLecture,
  'note': l10n.commonNotes,
  'schedule': l10n.commonSchedule,
  'downloads': l10n.commonDownload,
  'library': l10n.screenLibrary,
  'tasks': l10n.commonScheduledTasks,
  'plugins': l10n.commonPlugins,
  'settings': l10n.commonSettings,
  'activity': l10n.commonActivity,
  'usage': l10n.commonUsage,
  'bot': 'Bot',
};

const _tabTargets = {
  'home': Tabs.home,
  'courses': Tabs.courses,
  'schedule': Tabs.schedule,
  'downloads': Tabs.downloads,
  'library': Tabs.library,
  'tasks': Tabs.tasks,
  'plugins': Tabs.plugins,
  'settings': Tabs.settings,
};

/// A short label for an operation's chip.
String appOpLabel(Map<String, dynamic> op) => switch (op['op']) {
      'open' => l10n.botOpened(kOpenTargets[op['target']] ?? op['target']),
      'player' => switch (op['action']) {
          'play' => l10n.botResumed,
          'pause' => l10n.botPaused,
          'seek' => l10n.botSeeked,
          _ => l10n.botRateSet(op['rate']),
        },
      _ => '${op['label'] ?? l10n.commonDone}',
    };

/// Runs operations and remembers where the user was, for 返回.
abstract final class BotOps {
  static int? _backTab;
  static int? _pushedTab;
  static bool _rootPushed = false;
  static Map<String, dynamic>? _lastOpen;

  /// Whether the last opened page can be left with [back].
  static bool get canGoBack => _backTab != null;

  /// Whether [op] opened the page [back] would leave (older chips cannot).
  static bool canGoBackFrom(Map<String, dynamic> op) => canGoBack && mapEquals(op, _lastOpen);

  static void run(BuildContext context, Map<String, dynamic> op) {
    switch (op['op']) {
      case 'open':
        _open(context, op);
      case 'player':
        final h = context.read<PlayerHub>().value;
        if (h is! LecturePlayer) return;
        switch (op['action']) {
          case 'play':
            h.player.play();
          case 'pause':
            h.player.pause();
          case 'seek':
            h.seekTo(((op['seconds'] as num?) ?? 0).round() * 1000);
          case 'speed':
            h.setRate(((op['rate'] as num?) ?? 1).toDouble());
        }
      case 'prefs':
        final set = (op['set'] as Map?)?.cast<String, dynamic>();
        if (set != null && set.isNotEmpty) context.read<UiPrefs>().applyJson(set);
    }
  }

  static void _open(BuildContext context, Map<String, dynamic> op) {
    final target = '${op['target']}';
    _lastOpen = Map.of(op);
    _backTab = ShellNav.current;
    _pushedTab = null;
    _rootPushed = false;
    final tab = _tabTargets[target];
    // Tabs sit under full-screen routes (the compact assistant, a sheet, the
    // player): close them so the page shows, as the chat's buttons do.
    if (tab != null || target == 'course' || target == 'note') rootNavigator.currentState?.popUntil((r) => r.isFirst);
    if (tab != null) {
      ShellNav.goTo(tab);
      final day = DateTime.tryParse('${op['day'] ?? ''}');
      if (target == 'schedule' && day != null) context.read<ScheduleFocus>().value = day;
      final section = op['section'];
      if (target == 'settings' && section is String) SettingsNav.open(section);
      return;
    }
    void pushTab(int t, Widget page) {
      ShellNav.push(t, page);
      _pushedTab = t;
    }

    void pushRoot(Widget page) {
      rootNavigator.currentState?.push(MaterialPageRoute(builder: (_) => page));
      _rootPushed = true;
    }

    switch (target) {
      case 'course':
        pushTab(Tabs.courses, CoursePage(courseId: '${op['course_id']}'));
      case 'note':
        pushTab(Tabs.library, NotePage(noteId: '${op['note_id']}'));
      case 'lecture':
        final t = (op['t'] as num?)?.round();
        pushRoot(PlayerPage(lectureId: '${op['lecture_id']}', startMs: t == null ? null : t * 1000));
      case 'activity':
        pushRoot(const ActivityPage());
      case 'usage':
        pushRoot(const UsagePage());
      case 'bot':
        pushRoot(const BotPage());
    }
  }

  /// Leaves the page the bot opened and returns to the tab the user was on.
  static void back() {
    final tab = _backTab;
    if (tab == null) return;
    if (_rootPushed) rootNavigator.currentState?.maybePop();
    if (_pushedTab != null) ShellNav.pop(_pushedTab!);
    if (tab != ShellNav.current) ShellNav.goTo(tab);
    _backTab = null;
    _pushedTab = null;
    _rootPushed = false;
    _lastOpen = null;
  }
}
