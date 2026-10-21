import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../theme/prefs.dart';
import '../../theme/tokens.dart';
import '../../widgets/course_visuals.dart';
import '../../widgets/report_screen.dart';
import '../../widgets/states.dart';
import '../assistant/assistant_panel.dart';
import '../player/player_page.dart';
import '../plugins/plugin_views.dart';
import 'courses_page.dart';
import 'download_sheet.dart';

class CoursePage extends StatefulWidget {
  const CoursePage({super.key, required this.courseId});
  final String courseId;
  @override
  State<CoursePage> createState() => _CoursePageState();
}

class _CoursePageState extends State<CoursePage> {
  Course? _course;
  List<Lecture> _lectures = [];
  Object? _error;
  bool _loading = true;
  bool _syncing = false;
  final Set<String> _sel = {};
  StreamSubscription? _sub;

  bool get _selecting => _sel.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _course = context.read<AppState>().course(widget.courseId);
    _load();
    _sub = context.read<AppState>().events.listen((e) {
      final d = e['data'];
      if (e['type'] == 'lecture_changed' && d is Map && d['course_id'] == widget.courseId) _load(quiet: true);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load({bool sync = false, bool quiet = false}) async {
    if (sync) setState(() => _syncing = true);
    try {
      final r = await context.read<AppState>().api.get('/api/courses/${widget.courseId}/lectures', sync ? {'sync': '1'} : null) as Map;
      if (!mounted) return;
      setState(() {
        _course = Course((r['course'] as Map).cast<String, dynamic>());
        _lectures = jsonList(r['lectures']).map((e) => Lecture((e as Map).cast<String, dynamic>())).toList();
        _error = null;
      });
    } catch (e) {
      if (mounted && !quiet) setState(() => _error = e);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _syncing = false;
        });
      }
    }
  }

  void _open(Lecture l) => Navigator.of(context, rootNavigator: true)
      .push(MaterialPageRoute(builder: (_) => PlayerPage(lectureId: l.id)))
      .then((_) => _load(quiet: true));

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final course = app.course(widget.courseId) ?? _course;
    final base = Theme.of(context);
    final s = course == null ? base.colorScheme : courseScheme(context, course);
    final tt = base.textTheme;
    final compact = context.isCompact;
    final pad = compact ? Space.lg : Space.xl;

    final prefs = context.watch<UiPrefs>();
    final newestFirst = prefs.lecturesNewestFirst;
    // Lectures are numbered from the first to the last, whichever way they are shown.
    final ordered = [..._lectures]..sort((a, b) => a.beginAt != b.beginAt ? a.beginAt - b.beginAt : a.id.compareTo(b.id));
    final ordinal = {for (final (i, l) in ordered.indexed) l.id: i + 1};
    final list = newestFirst ? ordered.reversed.toList() : ordered;
    final playable = list.where((l) => l.hasPlayback).toList();
    final local = list.where((l) => l.assets.isNotEmpty).length;
    // Resume where the student left off: the last lecture with progress if
    // unfinished, else the next playable one; first lecture when untouched.
    final chrono = ordered.where((l) => l.hasPlayback).toList();
    Lecture? resume;
    final lastIdx = chrono.lastIndexWhere((l) => l.positionMs > 0);
    if (lastIdx < 0) {
      resume = chrono.isEmpty ? null : chrono.first;
    } else {
      final l = chrono[lastIdx];
      final done = l.durationS > 0 && l.positionMs >= l.durationS * 900;
      resume = done ? (lastIdx + 1 < chrono.length ? chrono[lastIdx + 1] : null) : l;
    }
    // Interleave month headings with lectures.
    final rows = <Object>[];
    String? month;
    for (final l in list) {
      final d = l.begin;
      final m = d == null ? '未排期' : '${d.year}年${d.month}月';
      if (m != month) rows.add(m);
      month = m;
      rows.add(l);
    }

    return ReportScreen(
      value: {'screen': '课程详情', 'course_id': widget.courseId, if (course != null) 'course': course.title},
      child: Theme(
        data: base.copyWith(colorScheme: base.colorScheme.copyWith(primary: s.primary, primaryContainer: s.primaryContainer, onPrimaryContainer: s.onPrimaryContainer, secondaryContainer: s.secondaryContainer, onSecondaryContainer: s.onSecondaryContainer)),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: CustomScrollView(slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: base.colorScheme.surfaceContainerLowest,
              title: AnimatedSwitcher(
                duration: Motion.short4,
                child: _selecting ? Text('已选 ${_sel.length} 节', key: const ValueKey(1)) : const SizedBox.shrink(key: ValueKey(0)),
              ),
              leading: _selecting ? IconButton(onPressed: () => setState(_sel.clear), icon: const Icon(Icons.close_rounded)) : null,
              actions: _selecting
                  ? [
                      TextButton(
                        onPressed: () => setState(() => _sel.length == playable.length ? _sel.clear() : _sel.addAll(playable.map((l) => l.id))),
                        child: Text(_sel.length == playable.length ? '取消全选' : '全选'),
                      ),
                    ]
                  : [
                      if (course != null)
                        Padding(
                          padding: const EdgeInsets.only(right: Space.xs),
                          child: FilledButton.tonalIcon(
                            onPressed: () => openCourseAssistant(context, widget.courseId, course.title),
                            icon: const Icon(Icons.forum_outlined, size: 18),
                            label: const Text('课程助手'),
                          ),
                        ),
                      IconButton(
                        tooltip: '刷新课表',
                        onPressed: _syncing ? null : () => _load(sync: true),
                        icon: _syncing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)) : const Icon(Icons.sync_rounded),
                      ),
                      if (course != null) PluginMenuButton(surface: 'course.menu', exportScope: 'course', context_: {'course_id': widget.courseId}),
                      if (course != null)
                        Builder(
                          builder: (ctx) => IconButton(
                            tooltip: '更多',
                            onPressed: () {
                              final box = ctx.findRenderObject() as RenderBox;
                              showCourseMenu(context, course, box.localToGlobal(box.size.bottomCenter(Offset.zero)));
                            },
                            icon: const Icon(Icons.more_vert_rounded),
                          ),
                        ),
                      const SizedBox(width: Space.sm),
                    ],
            ),
            if (course != null)
              SliverToBoxAdapter(
                child: ContentWidth(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(pad, 0, pad, Space.lg),
                    child: _Header(
                      course: course,
                      scheme: s,
                      lectures: list.length,
                      local: local,
                      resume: resume,
                      resumeStarted: resume != null && resume.positionMs > 0,
                      onResume: resume == null ? null : () => _open(resume!),
                    ),
                  ),
                ),
              ),
            if (_loading)
              const SliverFillRemaining(hasScrollBody: false, child: CenteredLoader(label: '正在读取课表'))
            else if (_error != null && list.isEmpty)
              SliverFillRemaining(hasScrollBody: false, child: ErrorState(error: _error!, onRetry: () => _load(sync: true)))
            else ...[
              SliverToBoxAdapter(
                child: ContentWidth(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(pad, Space.sm, pad - Space.sm, Space.sm),
                    child: Row(children: [
                      Text('${list.length} 节课', style: tt.titleMedium),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () => prefs.update((p) => p.lecturesNewestFirst = !newestFirst),
                        icon: AnimatedRotation(
                          turns: newestFirst ? 0 : 0.5,
                          duration: Motion.medium2,
                          curve: Motion.emphasized,
                          child: const Icon(Icons.arrow_downward_rounded, size: 18),
                        ),
                        label: Text(newestFirst ? '最新在前' : '第一节在前'),
                      ),
                      TextButton.icon(
                        onPressed: playable.isEmpty
                            ? null
                            : () {
                                // Start with the lectures that have nothing downloaded; when all have something, with all of them.
                                final missing = playable.where((l) => l.assets.isEmpty);
                                setState(() => _sel.addAll((missing.isEmpty ? playable : missing).map((l) => l.id)));
                              },
                        icon: const Icon(Icons.checklist_rounded, size: 18),
                        label: const Text('批量下载'),
                      ),
                    ]),
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(pad, 0, pad, 120),
                sliver: SliverList.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, i) {
                    final row = rows[i];
                    if (row is String) {
                      return ContentWidth(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(Space.xs, i == 0 ? 0 : Space.lg, 0, Space.sm),
                          child: Row(children: [
                            Text(row, style: tt.labelLarge?.copyWith(color: s.primary, letterSpacing: 0.3)),
                            const SizedBox(width: Space.md),
                            Expanded(child: Divider(height: 1, color: base.colorScheme.outlineVariant.withValues(alpha: 0.6))),
                          ]),
                        ),
                      );
                    }
                    final l = row as Lecture;
                    return ContentWidth(
                      child: _LectureTile(
                        key: ValueKey(l.id),
                        lecture: l,
                        ordinal: ordinal[l.id]!,
                        selecting: _selecting,
                        selected: _sel.contains(l.id),
                        onTap: () {
                          if (_selecting) {
                            if (l.hasPlayback) setState(() => _sel.contains(l.id) ? _sel.remove(l.id) : _sel.add(l.id));
                          } else if (l.hasPlayback) {
                            _open(l);
                          }
                        },
                        onLongPress: l.hasPlayback ? () => setState(() => _sel.add(l.id)) : null,
                        onDownload: () => showDownloadSheet(context, [l.id], title: l.shortTitle),
                      ),
                    );
                  },
                ),
              ),
            ],
          ]),
          floatingActionButton: AnimatedScale(
            scale: _selecting ? 1 : 0,
            duration: Motion.medium2,
            curve: _selecting ? Motion.emphasizedDecelerate : Motion.emphasizedAccelerate,
            child: FloatingActionButton.extended(
              heroTag: null,
              onPressed: !_selecting
                  ? null
                  : () async {
                      final ids = _sel.toList();
                      await showDownloadSheet(context, ids);
                      if (mounted) setState(_sel.clear);
                    },
              icon: const Icon(Icons.download_rounded),
              label: Text('下载 ${_sel.length} 节'),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatefulWidget {
  const _Header({
    required this.course,
    required this.scheme,
    required this.lectures,
    required this.local,
    this.resume,
    this.resumeStarted = false,
    this.onResume,
  });
  final Course course;
  final ColorScheme scheme;
  final int lectures, local;
  final Lecture? resume;
  final bool resumeStarted;
  final VoidCallback? onResume;

  @override
  State<_Header> createState() => _HeaderState();
}

class _HeaderState extends State<_Header> with SingleTickerProviderStateMixin {
  // One full turn every 90 s: barely perceptible, gives the art a breathing quality.
  late final _spin = AnimationController(vsync: this, duration: const Duration(seconds: 90));
  bool _hover = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _spin.stop();
    } else if (!_spin.isAnimating) {
      _spin.repeat();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final course = widget.course;
    final scheme = widget.scheme;
    final tt = Theme.of(context).textTheme;
    final teachers = course.teachers.isNotEmpty ? course.teachers.join('、') : course.teacher;
    final compact = context.isCompact;
    final art = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Hero(
        tag: 'art-${course.id}',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Corners.xl),
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: _hover ? 1 : 0),
            duration: Motion.long4,
            curve: Motion.emphasized,
            builder: (_, t, _) => AnimatedBuilder(
              animation: _spin,
              builder: (_, _) => CourseArt(course: course, t: t, spin: _spin.value),
            ),
          ),
        ),
      ),
    );
    final info = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(course.title, style: (compact ? tt.headlineSmall : tt.headlineMedium)?.copyWith(color: scheme.onSurface)),
      if (course.alias.isNotEmpty) Text(course.rawTitle, style: tt.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
      const SizedBox(height: Space.sm),
      Text([if (teachers.isNotEmpty) teachers, if (course.college.isNotEmpty) course.college, course.termLabel].join(' · '),
          style: tt.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
      const SizedBox(height: Space.lg),
      Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
        _Pill(icon: Icons.play_lesson_outlined, text: '${widget.lectures} 节', scheme: scheme),
        _Pill(icon: Icons.download_done_rounded, text: '本地 ${widget.local} 节', scheme: scheme),
        _Pill(icon: Icons.trending_up_rounded, text: '学习进度 ${(course.progress * 100).round()}%', scheme: scheme),
      ]),
      if (widget.resume != null) ...[
        const SizedBox(height: Space.lg),
        FilledButton.icon(
          onPressed: widget.onResume,
          style: FilledButton.styleFrom(backgroundColor: scheme.primary, foregroundColor: scheme.onPrimary),
          icon: Icon(widget.resumeStarted ? Icons.play_circle_rounded : Icons.play_arrow_rounded),
          label: Text(
            '${widget.resumeStarted ? '继续学习' : '开始学习'} · ${widget.resume!.date.isNotEmpty ? widget.resume!.date : widget.resume!.shortTitle}'
            '${widget.resumeStarted ? ' ${fmtClock(widget.resume!.positionMs)}' : ''}',
          ),
        ),
      ],
    ]);
    return Container(
      padding: const EdgeInsets.all(Space.sm),
      decoration: BoxDecoration(
        color: Color.alphaBlend(scheme.primary.withValues(alpha: 0.04), scheme.surfaceContainerLow),
        borderRadius: BorderRadius.circular(Corners.xlIncreased + Space.xs),
      ),
      child: compact
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(height: 150, child: art),
              Padding(padding: const EdgeInsets.fromLTRB(Space.md, Space.lg, Space.md, Space.md), child: info),
            ])
          : IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: Padding(padding: const EdgeInsets.all(Space.xl), child: Align(alignment: Alignment.centerLeft, child: info))),
                ConstrainedBox(constraints: const BoxConstraints(minHeight: 180), child: SizedBox(width: 300, child: art)),
              ]),
            ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.text, required this.scheme});
  final IconData icon;
  final String text;
  final ColorScheme scheme;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(Corners.full)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: scheme.onSecondaryContainer),
          const SizedBox(width: 4),
          Text(text, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onSecondaryContainer)),
        ]),
      );
}

class _LectureTile extends StatefulWidget {
  const _LectureTile({
    super.key,
    required this.lecture,
    required this.ordinal,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onDownload,
  });
  final Lecture lecture;
  final int ordinal;
  final bool selecting, selected;
  final VoidCallback onTap, onDownload;
  final VoidCallback? onLongPress;

  @override
  State<_LectureTile> createState() => _LectureTileState();
}

class _LectureTileState extends State<_LectureTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final l = widget.lecture;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final app = context.watch<AppState>();
    final active = ['video', 'slides', 'courseware', 'transcript'].map((k) => app.jobFor(l.id, k)).whereType<Job>().where((j) => j.active).toList();
    final d = l.begin;
    final watched = l.durationS > 0 && l.positionMs > 0 ? (l.positionMs / (l.durationS * 1000)).clamp(0.0, 1.0) : 0.0;
    final disabled = !l.hasPlayback;

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xs),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedContainer(
          duration: Motion.medium1,
          curve: Motion.emphasized,
          decoration: BoxDecoration(
            color: widget.selected
                ? cs.secondaryContainer
                : _hover && !disabled
                    ? cs.surfaceContainerHigh
                    : cs.surfaceContainer,
            borderRadius: BorderRadius.circular(widget.selected ? Corners.xl : Corners.lg),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(Corners.lg),
              onTap: widget.onTap,
              onLongPress: widget.onLongPress,
              child: Opacity(
                opacity: disabled ? 0.55 : 1,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.sm, Space.md),
                  child: Row(children: [
                    AnimatedSwitcher(
                      duration: Motion.short4,
                      transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                      child: widget.selecting
                          ? SizedBox(
                              key: const ValueKey('cb'),
                              width: 52,
                              child: Checkbox(value: widget.selected, onChanged: disabled ? null : (_) => widget.onTap()),
                            )
                          : _DateBlock(key: const ValueKey('date'), date: d),
                    ),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(l.shortTitle, style: tt.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text(
                          [
                            '第 ${widget.ordinal} 节',
                            fmtLectureDate(d),
                            if (l.durationS > 0) fmtDuration(l.durationS),
                            if (l.room.isNotEmpty) l.room,
                            if (disabled) (l.upcoming ? '未开始' : '暂无回放'),
                          ].join(' · '),
                          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (l.assets.isNotEmpty || l.segments > 0) ...[
                          const SizedBox(height: Space.xs),
                          AssetBadges(assets: l.assets, segments: l.segments),
                        ],
                        if (watched > 0) ...[
                          const SizedBox(height: Space.sm),
                          SizedBox(width: 120, child: LinearProgressIndicator(value: watched, minHeight: 3, borderRadius: BorderRadius.circular(2))),
                        ],
                        AnimatedSize(
                          duration: Motion.medium2,
                          curve: Motion.emphasized,
                          child: active.isEmpty
                              ? const SizedBox(width: double.infinity)
                              : Padding(
                                  padding: const EdgeInsets.only(top: Space.sm),
                                  child: Column(children: [for (final j in active) JobProgressLine(job: j)]),
                                ),
                        ),
                      ]),
                    ),
                    if (!widget.selecting && !disabled) ...[
                      IconButton(tooltip: '下载', onPressed: widget.onDownload, icon: const Icon(Icons.download_outlined)),
                      IconButton.filledTonal(tooltip: '播放', onPressed: widget.onTap, icon: const Icon(Icons.play_arrow_rounded)),
                    ],
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DateBlock extends StatelessWidget {
  const _DateBlock({super.key, required this.date});
  final DateTime? date;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      width: 52,
      height: 56,
      decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(Corners.md)),
      child: date == null
          ? Icon(Icons.event_outlined, color: cs.onPrimaryContainer)
          : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('${date!.month}月', style: tt.labelSmall?.copyWith(color: cs.onPrimaryContainer)),
              Text('${date!.day}', style: tt.titleLarge?.copyWith(color: cs.onPrimaryContainer, height: 1.1, fontWeight: FontWeight.w600)),
            ]),
    );
  }
}
