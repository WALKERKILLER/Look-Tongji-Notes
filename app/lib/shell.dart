import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/app_state.dart';
import 'core/plugins.dart';
import 'features/assistant/assistant_panel.dart';
import 'features/assistant/task_inbox.dart';
import 'features/assistant/tasks_page.dart';
import 'features/courses/courses_page.dart';
import 'features/downloads/downloads_page.dart';
import 'features/home/home_page.dart';
import 'features/library/library_page.dart';
import 'features/login/login_page.dart';
import 'features/profile/profile_dialog.dart';
import 'features/schedule/schedule_page.dart';
import 'features/schedule/schedule_store.dart';
import 'features/settings/settings_page.dart';
import 'theme/prefs.dart';
import 'theme/tokens.dart';
import 'widgets/organic_shapes.dart';
import 'widgets/states.dart';
import 'widgets/user_avatar.dart';

class _Dest {
  const _Dest(this.label, this.icon, this.selected, this.screen);
  final String label;
  final IconData icon;
  final IconData selected;
  final String screen;
}

/// Tab indices, shared with pages that switch tabs.
abstract final class Tabs {
  static const home = 0, courses = 1, schedule = 2, downloads = 3, library = 4, tasks = 5, settings = 6;
}

const _dests = [
  _Dest('首页', Icons.home_outlined, Icons.home_rounded, '首页'),
  _Dest('课程', Icons.school_outlined, Icons.school_rounded, '课程列表'),
  _Dest('日程', Icons.event_note_outlined, Icons.event_note_rounded, '日程'),
  _Dest('下载', Icons.download_outlined, Icons.download_rounded, '下载管理'),
  _Dest('资料库', Icons.auto_stories_outlined, Icons.auto_stories_rounded, '资料库'),
  _Dest('定时', Icons.schedule_outlined, Icons.schedule_rounded, '定时任务'),
  _Dest('设置', Icons.tune_outlined, Icons.tune_rounded, '设置'),
];

/// The bottom bar leaves out 定时, reached from 设置 and the assistant there.
const _barTabs = [Tabs.home, Tabs.courses, Tabs.schedule, Tabs.downloads, Tabs.library, Tabs.settings];

/// Lets any page switch tabs (e.g. "see all downloads").
class ShellScope extends InheritedWidget {
  const ShellScope({super.key, required this.goTo, required super.child});
  final void Function(int index) goTo;
  static ShellScope of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<ShellScope>()!;
  @override
  bool updateShouldNotify(ShellScope old) => false;
}

/// Navigation for widgets outside the tab navigators (the assistant panel).
abstract final class ShellNav {
  static void Function(int)? _goTo;
  static List<GlobalKey<NavigatorState>> _keys = const [];

  static void goTo(int tab) => _goTo?.call(tab);

  /// Switches to [tab] and opens [page] on top of it.
  static void push(int tab, Widget page) {
    _goTo?.call(tab);
    if (tab >= _keys.length) return;
    void go() => _keys[tab].currentState?.push(MaterialPageRoute(builder: (_) => page));
    if (_keys[tab].currentState != null) {
      go();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => go());
    }
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  final _navKeys = List.generate(_dests.length, (_) => GlobalKey<NavigatorState>());
  final _built = <int>{0};
  StreamSubscription<String>? _notices;

  @override
  void initState() {
    super.initState();
    ShellNav._goTo = _select;
    ShellNav._keys = _navKeys;
    // Plugin notices (look.notify) show wherever the user is.
    _notices = context.read<PluginStore>().notices.listen((m) {
      if (mounted) showSnack(context, m);
    });
  }

  @override
  void dispose() {
    _notices?.cancel();
    super.dispose();
  }

  Widget _root(int i) => switch (i) {
        Tabs.home => const HomePage(),
        Tabs.courses => const CoursesPage(),
        Tabs.schedule => const SchedulePage(),
        Tabs.downloads => const DownloadsPage(),
        Tabs.library => const LibraryPage(),
        Tabs.tasks => const TasksPage(),
        _ => const SettingsPage(),
      };

  void _select(int i) {
    if (i == _index) {
      _navKeys[i].currentState?.popUntil((r) => r.isFirst);
      return;
    }
    setState(() {
      _index = i;
      _built.add(i);
    });
    context.read<TaskInbox>().viewing = i == Tabs.tasks;
    context.read<ScreenContext>().set({'screen': _dests[i].screen});
  }

  @override
  Widget build(BuildContext context) {
    final sc = context.sizeClass;
    final app = context.watch<AppState>();
    final prefs = context.watch<UiPrefs>();
    final cs = Theme.of(context).colorScheme;
    final downloads = app.activeJobCount;
    final dueSoon = context.watch<ScheduleStore>().dueSoon;
    final unread = context.watch<TaskInbox>().unread;

    // Tabs keep their navigators alive; switching uses an MD3 fade-through.
    final stack = Stack(fit: StackFit.expand, children: [
      for (var i = 0; i < _dests.length; i++)
        if (_built.contains(i))
          _TabSlot(
            key: ValueKey(i),
            active: i == _index,
            child: HeroControllerScope(
              controller: MaterialApp.createMaterialHeroController(),
              child: Navigator(
                key: _navKeys[i],
                onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => _root(i)),
              ),
            ),
          ),
    ]);

    Widget icon(int i, bool sel) {
      final d = _dests[i];
      final ic = Icon(sel ? d.selected : d.icon);
      if (i == Tabs.downloads && downloads > 0) return Badge.count(count: downloads, child: ic);
      if (i == Tabs.schedule && dueSoon > 0) return Badge.count(count: dueSoon, child: ic);
      if (i == Tabs.tasks && unread > 0) return Badge.count(count: unread, child: ic);
      if (i == Tabs.settings && sc == SizeClass.compact && unread > 0) return Badge(child: ic);
      return ic;
    }

    final body = Column(children: [
      if (app.auth.status == 'needs_password') _ReauthBanner(error: app.auth.error),
      Expanded(child: stack),
    ]);

    final content = NavigatorPopHandler(
      onPopWithResult: (_) => _navKeys[_index].currentState?.maybePop(),
      child: ShellScope(goTo: _select, child: body),
    );

    if (sc == SizeClass.compact) {
      return Scaffold(
        body: SafeArea(bottom: false, child: content),
        floatingActionButton: _AssistantFab(compact: true),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _barTabs.contains(_index) ? _barTabs.indexOf(_index) : _barTabs.indexOf(Tabs.settings),
          onDestinationSelected: (b) => _select(_barTabs[b]),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: [
            for (final i in _barTabs) NavigationDestination(icon: icon(i, false), selectedIcon: icon(i, true), label: _dests[i].label),
          ],
        ),
      );
    }

    final docked = sc.index >= SizeClass.expanded.index && prefs.assistantDocked;
    return Scaffold(
      body: Row(children: [
        NavigationRail(
          selectedIndex: _index,
          onDestinationSelected: _select,
          leading: Padding(
            padding: const EdgeInsets.only(top: Space.sm, bottom: Space.xl),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.only(bottom: Space.lg),
                child: const _BrandMark(),
              ),
              if (!docked) _AssistantFab(compact: false),
            ]),
          ),
          trailingAtBottom: true,
          trailing: Padding(
            padding: const EdgeInsets.only(bottom: Space.lg),
            child: Tooltip(
              message: '${userDisplayName(context)} · 个人资料',
              child: InkWell(customBorder: const CircleBorder(), onTap: () => showProfileDialog(context), child: const UserAvatar(size: 40)),
            ),
          ),
          destinations: [
            for (var i = 0; i < _dests.length; i++)
              NavigationRailDestination(icon: icon(i, false), selectedIcon: icon(i, true), label: Text(_dests[i].label)),
          ],
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: docked ? 0 : Space.lg, top: Space.sm, bottom: Space.lg),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Corners.xl),
              child: ColoredBox(color: cs.surfaceContainerLowest, child: content),
            ),
          ),
        ),
        AnimatedSize(
          duration: Motion.medium4,
          curve: Motion.emphasized,
          child: docked
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(Space.sm, Space.sm, Space.lg, Space.lg),
                  child: SizedBox(
                    width: sc.index >= SizeClass.large.index ? 440 : 380,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(Corners.xl),
                      child: ColoredBox(color: cs.surfaceContainerLow, child: const AssistantPanel(docked: true)),
                    ),
                  ),
                )
              : const SizedBox(height: double.infinity),
        ),
      ]),
    );
  }
}

/// Fade-through host for one tab: the incoming tab fades and settles in
/// while the outgoing one leaves immediately (MD3 fade-through, simplified).
class _TabSlot extends StatefulWidget {
  const _TabSlot({super.key, required this.active, required this.child});
  final bool active;
  final Widget child;
  @override
  State<_TabSlot> createState() => _TabSlotState();
}

class _TabSlotState extends State<_TabSlot> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: Motion.medium2, value: widget.active ? 1 : 0);
  late final _fade = CurvedAnimation(parent: _c, curve: const Interval(0.3, 1, curve: Motion.emphasizedDecelerate));
  late final _scale = Tween(begin: 0.97, end: 1.0).animate(CurvedAnimation(parent: _c, curve: Motion.emphasizedDecelerate));

  @override
  void didUpdateWidget(_TabSlot old) {
    super.didUpdateWidget(old);
    if (widget.active == old.active) return;
    if (widget.active) {
      MediaQuery.disableAnimationsOf(context) ? _c.value = 1 : _c.forward(from: 0);
    } else {
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Offstage(
        offstage: !widget.active,
        child: TickerMode(
          enabled: widget.active,
          child: FadeTransition(opacity: _fade, child: ScaleTransition(scale: _scale, child: widget.child)),
        ),
      );
}

/// App mark on the rail: a soft twelve-lobed cookie holding a play glyph.
class _BrandMark extends StatelessWidget {
  const _BrandMark();
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Look Studio',
      child: CustomPaint(
        size: const Size.square(36),
        painter: _BrandPainter(cs.primaryContainer, cs.primary),
        child: SizedBox.square(dimension: 36, child: Icon(Icons.play_arrow_rounded, size: 20, color: cs.onPrimaryContainer)),
      ),
    );
  }
}

class _BrandPainter extends CustomPainter {
  _BrandPainter(this.fill, this.ring);
  final Color fill, ring;
  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawPath(shapePath(shapeRadii(OrganicShape.cookie12), r), Paint()..color = fill);
    canvas.drawCircle(r.topRight.translate(-4, 4), 3.5, Paint()..color = ring);
  }

  @override
  bool shouldRepaint(_BrandPainter o) => o.fill != fill || o.ring != ring;
}

class _AssistantFab extends StatelessWidget {
  const _AssistantFab({required this.compact});
  final bool compact;

  void _open(BuildContext context) {
    final sc = context.sizeClass;
    if (sc.index >= SizeClass.expanded.index) {
      context.read<UiPrefs>().update((p) => p.assistantDocked = true);
      return;
    }
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const Scaffold(body: SafeArea(child: AssistantPanel(docked: false))),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.select<AppState, bool>((a) => a.agentReady);
    final fab = FloatingActionButton(
      heroTag: 'assistant',
      tooltip: '助手',
      onPressed: () => _open(context),
      child: Icon(busy ? Icons.auto_awesome_rounded : Icons.auto_awesome_outlined),
    );
    return compact ? fab : fab;
  }
}

class _ReauthBanner extends StatelessWidget {
  const _ReauthBanner({required this.error});
  final String error;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.errorContainer,
      child: InkWell(
        onTap: () => showDialog(context: context, builder: (_) => const Dialog(child: SizedBox(width: 420, child: LoginForm(dialog: true)))),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
          child: Row(children: [
            Icon(Icons.lock_clock_outlined, color: cs.onErrorContainer),
            const SizedBox(width: Space.md),
            Expanded(
              child: Text('登录已过期，自动续期未成功。点此重新登录。', style: TextStyle(color: cs.onErrorContainer)),
            ),
            Icon(Icons.chevron_right_rounded, color: cs.onErrorContainer),
          ]),
        ),
      ),
    );
  }
}
