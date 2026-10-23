import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/hitokoto.dart';
import '../../core/models.dart';
import '../../core/profile.dart';
import '../../shell.dart';
import '../../theme/tokens.dart';
import '../../widgets/course_visuals.dart';
import '../../widgets/organic_shapes.dart';
import '../../widgets/states.dart';
import '../../widgets/user_avatar.dart';
import '../activity/activity_page.dart';
import '../courses/course_card.dart';
import '../courses/course_page.dart';
import '../notifications/notification_center.dart';
import '../player/player_page.dart';
import '../profile/profile_dialog.dart';
import '../schedule/schedule_page.dart';
import '../schedule/schedule_store.dart';
import '../schedule/schedule_widgets.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Lecture> _recent = [];
  Map<String, dynamic>? _lib;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = context.read<AppState>().events.listen((e) {
      if (e['type'] == 'lecture_changed' || e['type'] == 'notes_changed') _load();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final api = context.read<AppState>().api;
    try {
      final r = jsonList(await api.get('/api/recent'));
      final lib = await api.get('/api/library') as Map;
      if (!mounted) return;
      setState(() {
        _recent = r.map((e) => Lecture((e as Map).cast<String, dynamic>())).toList();
        _lib = lib.cast<String, dynamic>();
      });
    } catch (_) {}
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 5) return '夜深了';
    if (h < 11) return '早上好';
    if (h < 13) return '中午好';
    if (h < 18) return '下午好';
    return '晚上好';
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final compact = context.isCompact;
    final pad = compact ? Space.lg : Space.xl;
    final latestTerm = app.courses.isEmpty ? '' : app.courses.map((c) => c.term).reduce((a, b) => a.compareTo(b) > 0 ? a : b);
    final termCourses = app.courses.where((c) => c.term == latestTerm && !c.hidden).toList()
      ..sort((a, b) => b.lastLearnAt.compareTo(a.lastLearnAt));
    final active = app.sortedJobs.where((j) => j.active).take(3).toList();
    final now = DateTime.now();

    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([app.loadCourses(sync: true), _load()]);
      },
      child: CustomScrollView(slivers: [
        SliverToBoxAdapter(
          child: ContentWidth(
            child: Padding(
              padding: EdgeInsets.fromLTRB(pad, compact ? Space.xl : Space.xxl, pad, Space.lg),
              child: _Welcome(greeting: _greeting(), now: now, compact: compact),
            ),
          ),
        ),
        if (context.watch<ScheduleStore>().upcoming().isNotEmpty) ...[
          _header(context, '接下来', pad, action: TextButton(onPressed: () => ShellScope.of(context).goTo(Tabs.schedule), child: const Text('日程'))),
          SliverToBoxAdapter(
            child: ContentWidth(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: pad),
                child: UpcomingSchedule(onOpen: (d) {
                  context.read<ScheduleFocus>().value = d;
                  ShellScope.of(context).goTo(Tabs.schedule);
                }),
              ),
            ),
          ),
        ],
        _header(context, '学习足迹', pad,
            action: TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ActivityPage())), child: const Text('统计'))),
        SliverToBoxAdapter(child: ContentWidth(child: Padding(padding: EdgeInsets.symmetric(horizontal: pad), child: const ActivityCard()))),
        if (_recent.isNotEmpty) ...[
          _header(context, '继续观看', pad),
          SliverToBoxAdapter(
            child: ContentWidth(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: pad - 4),
                child: SizedBox(
                  height: 200,
                  child: CarouselView(
                    itemExtent: 280,
                    shrinkExtent: 180,
                    itemSnapping: true,
                    backgroundColor: cs.surfaceContainer,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Corners.xl)),
                    onTap: (i) => Navigator.of(context, rootNavigator: true)
                        .push(MaterialPageRoute(builder: (_) => PlayerPage(lectureId: _recent[i].id))),
                    children: [for (final l in _recent) _ContinueCard(lecture: l, course: app.course(l.courseId))],
                  ),
                ),
              ),
            ),
          ),
        ],
        if (active.isNotEmpty) ...[
          _header(context, '正在下载', pad, action: TextButton(onPressed: () => ShellScope.of(context).goTo(Tabs.downloads), child: const Text('全部'))),
          SliverToBoxAdapter(
            child: ContentWidth(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: pad),
                child: Card(
                  child: Column(children: [
                    for (final j in active)
                      ListTile(
                        leading: Icon(_kindIcon(j.kind)),
                        title: Text(j.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Padding(padding: const EdgeInsets.only(top: Space.xs), child: JobProgressLine(job: j)),
                      ),
                  ]),
                ),
              ),
            ),
          ),
        ],
        _header(context, latestTerm.isEmpty ? '课程' : '本学期课程', pad,
            action: TextButton(onPressed: () => ShellScope.of(context).goTo(Tabs.courses), child: const Text('全部课程'))),
        if (app.coursesLoading && app.courses.isEmpty)
          const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(Space.xxl), child: CenteredLoader()))
        else if (app.coursesError != null && app.courses.isEmpty)
          SliverToBoxAdapter(child: ErrorState(error: app.coursesError!, onRetry: () => app.loadCourses(sync: true)))
        else
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: pad),
            sliver: SliverToBoxAdapter(
              child: ContentWidth(
                child: LayoutBuilder(builder: (context, c) {
                  final cols = (c.maxWidth / 300).floor().clamp(1, 4);
                  final items = termCourses.take(cols * 2).toList();
                  return Wrap(spacing: Space.md, runSpacing: Space.md, children: [
                    for (final course in items)
                      SizedBox(
                        width: (c.maxWidth - Space.md * (cols - 1)) / cols,
                        child: CourseCard(course: course, onTap: () => _openCourse(context, course)),
                      ),
                  ]);
                }),
              ),
            ),
          ),
        if (_lib != null) ...[
          _header(context, '课程库', pad),
          SliverToBoxAdapter(child: ContentWidth(child: Padding(padding: EdgeInsets.symmetric(horizontal: pad), child: _LibraryStats(lib: _lib!)))),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: Space.huge)),
      ]),
    );
  }

  Widget _header(BuildContext context, String title, double pad, {Widget? action}) => SliverToBoxAdapter(
        child: ContentWidth(
          child: Padding(
            padding: EdgeInsets.fromLTRB(pad, Space.xl, pad - Space.sm, Space.md),
            child: Row(children: [
              Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
              ?action,
            ]),
          ),
        ),
      );

  void _openCourse(BuildContext context, Course c) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => CoursePage(courseId: c.id)));
}

IconData _kindIcon(String k) => switch (k) {
      'video' => Icons.movie_outlined,
      'slides' => Icons.slideshow_outlined,
      'courseware' => Icons.attach_file_rounded,
      'transcript' => Icons.subject_rounded,
      'parse' => Icons.document_scanner_outlined,
      _ => Icons.download_outlined,
    };

/// Greeting header: the user's avatar and nickname with a line of 一言.
class _Welcome extends StatelessWidget {
  const _Welcome({required this.greeting, required this.now, required this.compact});
  final String greeting;
  final DateTime now;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final name = userDisplayName(context);
    final showQuote = context.select<UserProfile, bool>((p) => p.showQuote);
    final avatar = compact ? 56.0 : 72.0;
    final gap = compact ? Space.lg : Space.xl;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        _AvatarButton(size: avatar),
        SizedBox(width: gap),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${now.month}月${now.day}日 · 周${'一二三四五六日'[now.weekday - 1]}',
                style: tt.labelLarge?.copyWith(color: cs.primary, letterSpacing: 0.4)),
            const SizedBox(height: Space.xxs),
            Text.rich(
              TextSpan(children: [
                TextSpan(text: '$greeting，', style: TextStyle(color: cs.onSurfaceVariant)),
                TextSpan(text: name),
              ]),
              style: compact ? tt.headlineMedium : tt.displaySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ]),
        ),
        // The navigation rail carries the bell on wider windows.
        if (compact) const NotificationBell(),
      ]),
      AnimatedSize(
        duration: Motion.medium4,
        curve: Motion.emphasized,
        alignment: Alignment.topLeft,
        child: showQuote
            ? Padding(padding: const EdgeInsets.only(top: Space.md), child: _QuoteLine(lead: avatar, gap: gap))
            : const SizedBox(width: double.infinity),
      ),
    ]);
  }
}

class _AvatarButton extends StatefulWidget {
  const _AvatarButton({required this.size});
  final double size;
  @override
  State<_AvatarButton> createState() => _AvatarButtonState();
}

class _AvatarButtonState extends State<_AvatarButton> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) => Tooltip(
        message: '编辑个人资料',
        waitDuration: const Duration(milliseconds: 500),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            onTap: () => showProfileDialog(context),
            child: AnimatedRotation(
              turns: _hover ? -0.02 : 0,
              duration: Motion.medium2,
              curve: Motion.emphasized,
              child: AnimatedScale(
                scale: _hover ? 1.06 : 1,
                duration: Motion.medium2,
                curve: Motion.emphasized,
                child: UserAvatar(size: widget.size),
              ),
            ),
          ),
        ),
      );
}

/// One line of 一言 set into the header grid: an organic quote mark under the
/// avatar (tap for another line; it morphs while loading) and the text under
/// the greeting.
class _QuoteLine extends StatefulWidget {
  const _QuoteLine({required this.lead, required this.gap});
  final double lead, gap;
  @override
  State<_QuoteLine> createState() => _QuoteLineState();
}

class _QuoteLineState extends State<_QuoteLine> with SingleTickerProviderStateMixin {
  Quote? _q = Hitokoto.current;
  bool _loading = false;
  bool _hover = false;
  late final _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void initState() {
    super.initState();
    if (_q == null) {
      Hitokoto.cached().then((c) {
        if (mounted && _q == null && c != null) setState(() => _q = c);
      });
    }
    _load();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  Future<void> _load({bool refresh = false}) async {
    if (_loading) return;
    setState(() => _loading = true);
    if (!MediaQuery.disableAnimationsOf(context)) _spin.repeat();
    final q = await Hitokoto.get(types: context.read<UserProfile>().quoteTypes, refresh: refresh);
    if (!mounted) return;
    // Let the mark finish its current cycle so it settles back to rest.
    _spin.animateTo(1, duration: _spin.duration! * (1 - _spin.value)).then((_) => _spin.value = 0);
    setState(() {
      _q = q;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final q = _q;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        width: widget.lead,
        child: Center(
          child: Tooltip(
            message: '换一句',
            waitDuration: const Duration(milliseconds: 500),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _hover = true),
              onExit: (_) => setState(() => _hover = false),
              child: GestureDetector(
                onTap: () => _load(refresh: true),
                child: AnimatedScale(
                  scale: _hover ? 1.08 : 1,
                  duration: Motion.medium2,
                  curve: Motion.emphasized,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: _hover ? 1 : 0),
                    duration: Motion.long2,
                    curve: Motion.emphasized,
                    builder: (_, h, _) => AnimatedBuilder(
                      animation: _spin,
                      builder: (_, _) => CustomPaint(
                        size: const Size.square(40),
                        painter: _QuoteMarkPainter(
                          morph: math.max(h * 0.35, math.sin(_spin.value * math.pi)),
                          turn: _spin.value + h * 0.04,
                          fill: Color.lerp(cs.tertiaryContainer, cs.tertiary, _loading ? 1 : h)!,
                        ),
                        child: SizedBox.square(
                          dimension: 40,
                          child: Icon(Icons.format_quote_rounded, size: 20, color: Color.lerp(cs.onTertiaryContainer, cs.onTertiary, _loading ? 1 : h)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      SizedBox(width: widget.gap),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: AnimatedSwitcher(
            duration: Motion.medium4,
            switchInCurve: Motion.emphasizedDecelerate,
            switchOutCurve: Motion.emphasizedAccelerate,
            transitionBuilder: (c, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(position: Tween(begin: const Offset(0, 0.12), end: Offset.zero).animate(a), child: c),
            ),
            layoutBuilder: (cur, prev) => Stack(alignment: Alignment.topLeft, children: [...prev, ?cur]),
            child: q == null
                ? const SizedBox(key: ValueKey(''), height: 40)
                : Column(
                    key: ValueKey(q.text),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(q.text, style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w400, color: cs.onSurface, height: 1.55, letterSpacing: 0.2)),
                      if (q.source.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: Space.xxs),
                          child: Text(q.source, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                        ),
                    ],
                  ),
          ),
        ),
      ),
    ]);
  }
}

class _QuoteMarkPainter extends CustomPainter {
  _QuoteMarkPainter({required this.morph, required this.turn, required this.fill});
  final double morph, turn;
  final Color fill;
  @override
  void paint(Canvas canvas, Size size) {
    final radii = morphRadii(OrganicShape.cookie6, OrganicShape.softBurst, morph.clamp(0.0, 1.0));
    canvas.drawPath(shapePath(radii, Offset.zero & size, rotation: turn * math.pi * 2 / 3), Paint()..color = fill);
  }

  @override
  bool shouldRepaint(_QuoteMarkPainter o) => o.morph != morph || o.turn != turn || o.fill != fill;
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.lecture, required this.course});
  final Lecture lecture;
  final Course? course;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final dur = lecture.durationS * 1000;
    final p = dur > 0 ? (lecture.positionMs / dur).clamp(0.0, 1.0) : 0.0;
    final scheme = course == null ? cs : courseScheme(context, course!);
    final fallback = course == null ? ColoredBox(color: scheme.primaryContainer) : CourseArt(course: course!, layout: 3);
    // Carousel items shrink while scrolling; hide secondary text when narrow.
    return LayoutBuilder(builder: (context, box) {
      final roomy = box.maxWidth > 220;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: Stack(fit: StackFit.expand, children: [
            lecture.thumb.isNotEmpty ? Image.network(lecture.thumb, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback) : fallback,
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.center, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black45]),
              ),
            ),
            Positioned(
              left: Space.md,
              bottom: Space.sm,
              child: Container(
                width: 36,
                height: 36,
                decoration: ShapeDecoration(color: scheme.primaryContainer, shape: const StarBorder(points: 8, innerRadiusRatio: 0.86, pointRounding: 0.6, valleyRounding: 0.4)),
                child: Icon(Icons.play_arrow_rounded, size: 22, color: scheme.onPrimaryContainer),
              ),
            ),
            if (roomy)
              Positioned(
                right: Space.md,
                bottom: Space.md,
                child: Text('${fmtClock(lecture.positionMs)} / ${fmtClock(dur)}',
                    style: tt.labelSmall?.copyWith(color: Colors.white, fontFeatures: const [FontFeature.tabularFigures()])),
              ),
          ]),
        ),
        LinearProgressIndicator(value: p, minHeight: 3, color: scheme.primary, backgroundColor: scheme.primaryContainer, borderRadius: BorderRadius.zero),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.md, Space.md),
          child: Row(children: [
            if (course != null) ...[CourseGlyph(course: course!, size: 22), const SizedBox(width: Space.sm)],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(course?.title ?? '', style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(lecture.shortTitle, style: tt.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
          ]),
        ),
      ]);
    });
  }
}

class _LibraryStats extends StatelessWidget {
  const _LibraryStats({required this.lib});
  final Map<String, dynamic> lib;
  @override
  Widget build(BuildContext context) {
    final st = (lib['stats'] as Map?) ?? {};
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final items = [
      ('${st['local_lectures'] ?? 0}', '节已存本地'),
      (fmtBytes((st['bytes'] ?? 0) as num), '占用空间'),
      ('${st['segments'] ?? 0}', '句转写'),
      ('${st['notes'] ?? 0}', '篇笔记'),
    ];
    return Card(
      color: cs.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: Space.xxl, runSpacing: Space.lg, children: [
            for (final (v, l) in items)
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(v, style: tt.headlineSmall?.copyWith(color: cs.primary)),
                Text(l, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ]),
          ]),
          const SizedBox(height: Space.lg),
          Row(children: [
            Icon(Icons.folder_outlined, size: 16, color: cs.onSurfaceVariant),
            const SizedBox(width: Space.sm),
            Expanded(child: Text('${lib['root']}', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant), overflow: TextOverflow.ellipsis)),
          ]),
        ]),
      ),
    );
  }
}
