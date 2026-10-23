import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/open_path.dart';
import '../../theme/tokens.dart';
import '../../widgets/course_visuals.dart';
import '../../widgets/report_screen.dart';
import '../../widgets/states.dart';
import '../player/player_page.dart';
import '../../l10n/l10n.dart';

class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key});
  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  int _view = 0; // 0 tasks, 1 local files

  /// Selection mode: long-press a job or use 选择任务; the toolbar then acts
  /// on the picked jobs only.
  bool _selecting = false;
  final _picked = <String>{};

  static bool _pickable(Job j) => j.active || j.state == 'paused' || j.state == 'failed';

  void _toggle(Job j) => setState(() {
        _selecting = true;
        if (!_picked.remove(j.id)) _picked.add(j.id);
      });

  void _endSelection() => setState(() {
        _selecting = false;
        _picked.clear();
      });

  Future<void> _clearFinished() async {
    final app = context.read<AppState>();
    var files = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          icon: const Icon(Icons.cleaning_services_outlined),
          title: Text(l10n.downloadsClearTitle),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l10n.downloadsClearBody),
            const SizedBox(height: Space.md),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: files,
              onChanged: (v) => set(() => files = v ?? false),
              title: Text(l10n.downloadsClearAlsoFiles),
              subtitle: Text(l10n.downloadsClearAlsoFilesHint),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.commonCancel)),
            FilledButton(
              style: files ? FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error, foregroundColor: Theme.of(context).colorScheme.onError) : null,
              onPressed: () => Navigator.pop(context, true),
              child: Text(files ? l10n.downloadsClearAndDelete : l10n.downloadsClearRecords),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      final freed = await app.clearFinished(files: files);
      if (mounted) showSnack(context, files ? l10n.downloadsClearedFreed(fmtBytes(freed)) : l10n.downloadsCleared);
    } catch (e) {
      if (mounted) showSnack(context, l10n.downloadsClearFailed(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final compact = context.isCompact;
    final pad = compact ? Space.lg : Space.xl;
    final jobs = app.sortedJobs;
    final active = jobs.where((j) => j.active || j.state == 'paused').toList();
    final failed = jobs.where((j) => j.state == 'failed').toList();
    final done = jobs.where((j) => j.state == 'done' || j.state == 'canceled').toList();
    final speed = jobs.where((j) => j.state == 'running').fold<int>(0, (s, j) => s + j.speed);
    final running = jobs.where((j) => j.state == 'running').length;
    final pausable = jobs.where((j) => j.active).length;
    final paused = jobs.where((j) => j.state == 'paused').length;
    final pickable = jobs.where(_pickable).toList();
    _picked.retainAll({for (final j in pickable) j.id});
    final selecting = _selecting && _view == 0 && pickable.isNotEmpty;
    final picked = [for (final j in pickable) if (_picked.contains(j.id)) j];

    final header = SliverToBoxAdapter(
      child: ContentWidth(
        child: Padding(
          padding: EdgeInsets.fromLTRB(pad, compact ? Space.xl : Space.xxl, pad, Space.md),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l10n.commonDownload, style: compact ? tt.headlineMedium : tt.displaySmall),
            const SizedBox(height: Space.xs),
            AnimatedSwitcher(
              duration: Motion.short4,
              child: Text(
                key: ValueKey(running > 0),
                running > 0
                    ? l10n.downloadsRunningSummary(running, fmtSpeed(speed))
                    : pausable > 0
                        ? l10n.downloadsWaiting(pausable)
                        : paused > 0
                            ? l10n.downloadsPausedSummary(paused)
                            : l10n.downloadsNoneRunning,
                style: tt.bodyLarge?.copyWith(color: running > 0 ? cs.primary : cs.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: Space.lg),
            Wrap(spacing: Space.sm, runSpacing: Space.sm, alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, children: [
              SegmentedButton<int>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: 0, icon: const Icon(Icons.downloading_rounded), label: Text(jobs.isEmpty ? l10n.commonTasks : l10n.commonTasksCount(jobs.length))),
                  ButtonSegment(value: 1, icon: Icon(Icons.inventory_2_outlined), label: Text(l10n.commonDownloaded)),
                ],
                selected: {_view},
                onSelectionChanged: (v) => setState(() => _view = v.first),
              ),
              if (_view == 0 && pickable.isNotEmpty && !selecting)
                TextButton.icon(onPressed: () => setState(() => _selecting = true), icon: const Icon(Icons.checklist_rounded, size: 18), label: Text(l10n.downloadsSelectJobs)),
            ]),
          ]),
        ),
      ),
    );

    return ReportScreen(
      value: {'screen': l10n.screenDownloads, 'view': _view == 0 ? l10n.commonTasks : l10n.commonDownloaded},
      child: _view == 1
          ? _LocalView(header: header, pad: pad)
          : CustomScrollView(slivers: [
              header,
              if (selecting)
                PinnedHeaderSliver(
                  child: ContentWidth(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(pad - Space.xs, Space.xs, pad - Space.xs, Space.sm),
                      child: _SelectionBar(
                        count: picked.length,
                        allPicked: picked.length == pickable.length,
                        showRetry: failed.isNotEmpty,
                        can: {
                          if (picked.any((j) => j.active)) 'pause',
                          if (picked.any((j) => j.state == 'paused')) 'resume',
                          if (picked.any((j) => j.state == 'failed')) 'retry',
                          if (picked.any((j) => j.active || j.state == 'paused')) 'cancel',
                        },
                        onClose: _endSelection,
                        onAll: () => setState(() => picked.length == pickable.length ? _picked.clear() : _picked.addAll(pickable.map((j) => j.id))),
                        onAction: (a) => _bulkPicked(a, picked),
                      ),
                    ),
                  ),
                ),
              if (jobs.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.download_rounded,
                    title: l10n.downloadsEmpty,
                    body: l10n.downloadsEmptyBody,
                  ),
                ),
              ..._section(context, l10n.downloadsSectionActive, active, pad, selecting: selecting, actions: [
                TextButton.icon(onPressed: pausable > 0 ? () => _bulk('pause') : null, icon: const Icon(Icons.pause_rounded, size: 18), label: Text(l10n.downloadsPauseAll)),
                TextButton.icon(onPressed: paused > 0 ? () => _bulk('resume') : null, icon: const Icon(Icons.play_arrow_rounded, size: 18), label: Text(l10n.downloadsResumeAll)),
              ]),
              ..._section(context, l10n.commonFailed, failed, pad, selecting: selecting, actions: [
                TextButton.icon(onPressed: () => _bulk('retry'), icon: const Icon(Icons.refresh_rounded, size: 18), label: Text(l10n.downloadsRetryAll)),
              ]),
              ..._section(context, l10n.commonDone, done, pad, selecting: selecting, actions: [
                TextButton.icon(onPressed: _clearFinished, icon: const Icon(Icons.cleaning_services_outlined, size: 18), label: Text(l10n.downloadsClearDone)),
              ]),
              const SliverToBoxAdapter(child: SizedBox(height: Space.huge)),
            ]),
    );
  }

  Future<void> _bulk(String action, {List<String>? ids}) async {
    final app = context.read<AppState>();
    try {
      final n = await app.bulkJobs(action, ids: ids);
      final verb = {'pause': l10n.commonPaused, 'resume': l10n.downloadsResumed, 'retry': l10n.downloadsRetried, 'cancel': l10n.commonCancelled}[action]!;
      if (mounted && n > 0) showSnack(context, l10n.downloadsBulkDone(verb, n));
    } catch (e) {
      if (mounted) showSnack(context, l10n.commonActionFailed(e));
    }
  }

  /// Runs a toolbar action on the picked jobs it applies to.
  Future<void> _bulkPicked(String action, List<Job> picked) async {
    final ids = [
      for (final j in picked)
        if (switch (action) { 'pause' => j.active, 'resume' => j.state == 'paused', 'retry' => j.state == 'failed', _ => j.active || j.state == 'paused' }) j.id,
    ];
    if (ids.isEmpty) return;
    if (action == 'cancel') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.stop_circle_outlined),
          title: Text(l10n.downloadsCancelTitle(ids.length)),
          content: Text(l10n.downloadsCancelBody),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.downloadsKeep)),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.downloadsCancelConfirm)),
          ],
        ),
      );
      if (ok != true) return;
    }
    await _bulk(action, ids: ids);
    if (mounted) _endSelection();
  }

  List<Widget> _section(BuildContext context, String title, List<Job> list, double pad, {required bool selecting, List<Widget> actions = const []}) {
    if (list.isEmpty) return const [];
    final cs = Theme.of(context).colorScheme;
    return [
      SliverToBoxAdapter(
        child: ContentWidth(
          child: Padding(
            padding: EdgeInsets.fromLTRB(pad, Space.lg, pad - Space.sm, Space.xs),
            child: Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.sm),
                child: Text('$title · ${list.length}', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: cs.onSurfaceVariant)),
              ),
              // The toolbar takes over while picking jobs.
              if (!selecting) Wrap(children: actions),
            ]),
          ),
        ),
      ),
      SliverList.builder(
        itemCount: list.length,
        itemBuilder: (context, i) {
          final j = list[i];
          return ContentWidth(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: pad, vertical: 2),
              child: _JobTile(
                key: ValueKey(j.id),
                job: j,
                selecting: selecting,
                picked: _picked.contains(j.id),
                onPick: _pickable(j) ? () => _toggle(j) : null,
              ),
            ),
          );
        },
      ),
    ];
  }
}

/// Confirms and deletes local files; shows the freed space.
Future<void> confirmDeleteFiles(BuildContext context, {required String what, required Future<int> Function() run}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.delete_forever_outlined),
      title: Text(l10n.downloadsDeleteFilesTitle),
      content: Text(l10n.downloadsDeleteFilesBody(what)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.commonCancel)),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error, foregroundColor: Theme.of(context).colorScheme.onError),
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.commonDelete),
        ),
      ],
    ),
  );
  if (ok != true) return;
  try {
    final freed = await run();
    if (context.mounted) showSnack(context, l10n.downloadsDeletedFreed(fmtBytes(freed)));
  } catch (e) {
    if (context.mounted) showSnack(context, l10n.commonDeleteFailed(e));
  }
}

class _LocalItem {
  _LocalItem(Map m)
      : lectureId = '${m['lecture_id']}',
        courseId = '${m['course_id']}',
        courseTitle = '${m['course_title'] ?? ''}',
        lecture = '${m['lecture'] ?? ''}',
        date = '${m['date'] ?? ''}',
        kind = '${m['kind']}',
        bytes = (m['bytes'] as num?)?.toInt() ?? 0,
        files = (m['files'] as num?)?.toInt() ?? 0;
  final String lectureId, courseId, courseTitle, lecture, date, kind;
  final int bytes, files;
}

const _kindOrder = ['video', 'slides', 'courseware', 'transcript'];

/// Everything on disk, grouped by course then lecture, with per-kind delete.
class _LocalView extends StatefulWidget {
  const _LocalView({required this.header, required this.pad});
  final Widget header;
  final double pad;
  @override
  State<_LocalView> createState() => _LocalViewState();
}

class _LocalViewState extends State<_LocalView> {
  List<_LocalItem>? _items;
  Object? _error;
  String _filter = '';
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = context.read<AppState>().events.listen((e) {
      if (e['type'] == 'lecture_changed') _load();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = jsonList(await context.read<AppState>().api.get('/api/local'));
      if (mounted) setState(() => _items = r.map((e) => _LocalItem(e as Map)).toList());
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _delete(String lectureId, List<String> kinds, String what) => confirmDeleteFiles(
        context,
        what: what,
        run: () async {
          final app = context.read<AppState>();
          var freed = 0;
          for (final k in kinds) {
            freed += await app.removeAsset(lectureId, k);
          }
          await _load();
          return freed;
        },
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final pad = widget.pad;
    final items = _items;
    if (items == null) {
      return CustomScrollView(slivers: [
        widget.header,
        SliverFillRemaining(hasScrollBody: false, child: _error != null ? ErrorState(error: _error!, onRetry: _load) : const CenteredLoader()),
      ]);
    }
    final total = items.fold<int>(0, (s, i) => s + i.bytes);
    final byKind = {for (final k in _kindOrder) k: items.where((i) => i.kind == k).fold<int>(0, (s, i) => s + i.bytes)};
    final shown = _filter.isEmpty ? items : items.where((i) => i.kind == _filter).toList();
    // course -> lecture -> items
    final courses = <String, Map<String, List<_LocalItem>>>{};
    for (final i in shown) {
      courses.putIfAbsent(i.courseId, () => {}).putIfAbsent(i.lectureId, () => []).add(i);
    }
    final kindColor = {'video': cs.primary, 'slides': cs.tertiary, 'courseware': cs.secondary, 'transcript': cs.outline};

    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(slivers: [
        widget.header,
        if (items.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(icon: Icons.inventory_2_outlined, title: l10n.downloadsLocalEmpty, body: l10n.downloadsLocalEmptyBody),
          )
        else ...[
          SliverToBoxAdapter(
            child: ContentWidth(
              child: Padding(
                padding: EdgeInsets.fromLTRB(pad, Space.sm, pad, Space.md),
                child: Card(
                  margin: EdgeInsets.zero,
                  color: cs.surfaceContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(Space.xl),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(fmtBytes(total), style: tt.headlineMedium?.copyWith(color: cs.onSurface)),
                        const SizedBox(width: Space.sm),
                        Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(l10n.homeStatStorage, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant))),
                      ]),
                      const SizedBox(height: Space.md),
                      // Stacked usage bar by kind.
                      ClipRRect(
                        borderRadius: BorderRadius.circular(Corners.full),
                        child: SizedBox(
                          height: 10,
                          child: Row(children: [
                            for (final k in _kindOrder)
                              if (byKind[k]! > 0)
                                Expanded(
                                  flex: math.max(1, (byKind[k]! * 1000 / math.max(total, 1)).round()),
                                  child: Container(margin: const EdgeInsets.only(right: 2), color: kindColor[k]),
                                ),
                          ]),
                        ),
                      ),
                      const SizedBox(height: Space.md),
                      Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
                        for (final k in _kindOrder)
                          if (byKind[k]! > 0)
                            FilterChip(
                              avatar: CircleAvatar(radius: 5, backgroundColor: kindColor[k]),
                              label: Text('${kindLabels[k]} ${fmtBytes(byKind[k]!)}'),
                              selected: _filter == k,
                              showCheckmark: false,
                              onSelected: (v) => setState(() => _filter = v ? k : ''),
                            ),
                      ]),
                    ]),
                  ),
                ),
              ),
            ),
          ),
          for (final c in courses.entries) ...[
            SliverToBoxAdapter(
              child: ContentWidth(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(pad, Space.lg, pad, Space.sm),
                  child: _CourseHeading(courseId: c.key, fallback: c.value.values.first.first.courseTitle, bytes: c.value.values.expand((l) => l).fold(0, (s, i) => s + i.bytes)),
                ),
              ),
            ),
            SliverList.builder(
              itemCount: c.value.length,
              itemBuilder: (context, i) {
                final entry = c.value.entries.elementAt(i);
                final list = entry.value..sort((a, b) => _kindOrder.indexOf(a.kind) - _kindOrder.indexOf(b.kind));
                final first = list.first;
                return ContentWidth(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: pad, vertical: 2),
                    child: Card(
                      margin: EdgeInsets.zero,
                      color: cs.surfaceContainer,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(Corners.md),
                        onTap: list.any((x) => x.kind == 'video')
                            ? () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => PlayerPage(lectureId: entry.key)))
                            : null,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.sm, Space.md),
                          child: Row(children: [
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text([first.date, first.lecture].where((s) => s.isNotEmpty).join(' · '), style: tt.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                                const SizedBox(height: Space.sm),
                                Wrap(spacing: Space.xs, runSpacing: Space.xs, children: [
                                  for (final it in list)
                                    InputChip(
                                      visualDensity: VisualDensity.compact,
                                      avatar: CircleAvatar(radius: 4, backgroundColor: kindColor[it.kind]),
                                      label: Text('${kindLabels[it.kind] ?? it.kind} · ${fmtBytes(it.bytes)}'),
                                      deleteIcon: const Icon(Icons.close_rounded, size: 16),
                                      deleteButtonTooltipMessage: l10n.downloadsDeleteKindFiles(kindLabels[it.kind] ?? ''),
                                      onDeleted: () => _delete(it.lectureId, [it.kind], l10n.downloadsLectureKind(kindLabels[it.kind] ?? it.kind, fmtBytes(it.bytes))),
                                    ),
                                ]),
                              ]),
                            ),
                            MenuAnchor(
                              menuChildren: [
                                if (canOpenFolders)
                                  MenuItemButton(
                                    leadingIcon: const Icon(Icons.folder_open_outlined),
                                    onPressed: () => revealLecture(context, entry.key),
                                    child: Text(l10n.commonShowInFolder),
                                  ),
                                MenuItemButton(
                                  leadingIcon: Icon(Icons.delete_forever_outlined, color: cs.error),
                                  onPressed: () => _delete(entry.key, [for (final x in list) x.kind],
                                      l10n.downloadsLectureAllFiles(fmtBytes(list.fold(0, (s, x) => s + x.bytes)))),
                                  child: Text(l10n.downloadsDeleteAllFiles, style: TextStyle(color: cs.error)),
                                ),
                              ],
                              builder: (context, m, _) => IconButton(
                                tooltip: l10n.commonMore,
                                onPressed: () => m.isOpen ? m.close() : m.open(),
                                icon: const Icon(Icons.more_vert_rounded),
                              ),
                            ),
                          ]),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ],
        const SliverToBoxAdapter(child: SizedBox(height: Space.huge)),
      ]),
    );
  }
}

class _CourseHeading extends StatelessWidget {
  const _CourseHeading({required this.courseId, required this.fallback, required this.bytes});
  final String courseId, fallback;
  final int bytes;
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final course = context.select<AppState, Course?>((a) => a.course(courseId));
    return Row(children: [
      if (course != null) ...[CourseGlyph(course: course, size: 28), const SizedBox(width: Space.md)],
      Expanded(child: Text(course?.title ?? fallback, style: tt.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis)),
      Text(fmtBytes(bytes), style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
    ]);
  }
}

/// Opens a lecture's folder in the system file manager.
Future<void> revealLecture(BuildContext context, String lectureId) async {
  try {
    final r = await context.read<AppState>().api.get('/api/lectures/$lectureId') as Map;
    final dir = (r['lecture'] as Map)['dir']?.toString() ?? '';
    final root = r['library_root']?.toString() ?? '';
    final ok = dir.isNotEmpty && await openPath(p.join(root, dir));
    if (!ok && context.mounted) showSnack(context, l10n.commonCannotOpenFolder);
  } catch (e) {
    if (context.mounted) showSnack(context, '$e');
  }
}

class _JobTile extends StatelessWidget {
  const _JobTile({super.key, required this.job, this.selecting = false, this.picked = false, this.onPick});
  final Job job;
  final bool selecting, picked;

  /// Toggles the job in the selection; null for jobs that can't be picked.
  final VoidCallback? onPick;

  IconData get _icon => switch (job.kind) {
        'video' => Icons.movie_outlined,
        'slides' => Icons.slideshow_outlined,
        'courseware' => Icons.attach_file_rounded,
        'parse' => Icons.document_scanner_outlined,
        'transcript' => Icons.subject_rounded,
        _ => Icons.download_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final course = context.select<AppState, Course?>((a) => a.course(job.courseId));
    final failed = job.state == 'failed';
    final done = job.state == 'done';
    final pickMode = selecting && onPick != null;
    final Widget lead = pickMode
        ? AnimatedContainer(
            key: const ValueKey('pick'),
            duration: Motion.short4,
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: picked ? cs.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(picked ? Corners.md : Corners.full),
              border: picked ? null : Border.all(color: cs.outline, width: 2),
            ),
            child: picked ? Icon(Icons.check_rounded, color: cs.onPrimary) : null,
          )
        : Container(
            key: const ValueKey('kind'),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: done ? cs.tertiaryContainer : failed ? cs.errorContainer : cs.secondaryContainer,
              borderRadius: BorderRadius.circular(Corners.md),
            ),
            child: Icon(done ? Icons.download_done_rounded : _icon,
                color: done ? cs.onTertiaryContainer : failed ? cs.onErrorContainer : cs.onSecondaryContainer),
          );

    return Semantics(
      selected: pickMode ? picked : null,
      child: Card(
        color: picked ? cs.secondaryContainer : failed ? cs.errorContainer.withValues(alpha: 0.4) : cs.surfaceContainer,
        margin: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(Corners.md),
          // While picking, a tap only picks; finished jobs ignore it.
          onTap: selecting
              ? onPick
              : done && job.kind == 'video'
                  ? () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => PlayerPage(lectureId: job.lectureId)))
                  : null,
          onLongPress: selecting ? null : onPick,
          child: Padding(
            padding: EdgeInsets.fromLTRB(Space.lg, Space.md, pickMode ? Space.lg : Space.sm, Space.md),
            child: Row(children: [
              AnimatedSwitcher(duration: Motion.short4, child: lead),
              const SizedBox(width: Space.lg),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(job.title, style: tt.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    [kindLabels[job.kind] ?? job.kind, if (course != null) course.title].join(' · '),
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (job.active || job.state == 'paused') ...[
                    const SizedBox(height: Space.sm),
                    _JobProgress(job: job),
                  ] else if (failed) ...[
                    const SizedBox(height: Space.xs),
                    Text(job.error, style: tt.bodySmall?.copyWith(color: cs.error), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ] else if (done && job.totalBytes > 0)
                    Text(fmtBytes(job.totalBytes), style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                ]),
              ),
              if (!pickMode) ...[
                const SizedBox(width: Space.sm),
                if (job.state == 'running' || job.state == 'queued')
                  IconButton(tooltip: l10n.commonPause, onPressed: () => app.jobAction(job.id, 'pause'), icon: const Icon(Icons.pause_rounded)),
                if (job.state == 'paused')
                  IconButton(tooltip: l10n.commonResume, onPressed: () => app.jobAction(job.id, 'resume'), icon: const Icon(Icons.play_arrow_rounded)),
                if (failed) IconButton(tooltip: l10n.commonRetry, onPressed: () => app.jobAction(job.id, 'retry'), icon: const Icon(Icons.refresh_rounded)),
                if (done && canOpenFolders) IconButton(tooltip: l10n.commonShowInFolder, onPressed: () => revealLecture(context, job.lectureId), icon: const Icon(Icons.folder_open_outlined)),
                if (job.active || job.state == 'paused')
                  IconButton(tooltip: l10n.commonCancel, onPressed: () => app.jobAction(job.id, 'cancel'), icon: const Icon(Icons.close_rounded))
                else
                  MenuAnchor(
                    menuChildren: [
                      MenuItemButton(
                        leadingIcon: const Icon(Icons.playlist_remove_rounded),
                        onPressed: () => app.jobAction(job.id, 'remove'),
                        child: Text(l10n.downloadsRemoveRecordOnly),
                      ),
                      if (done)
                        MenuItemButton(
                          leadingIcon: Icon(Icons.delete_forever_outlined, color: cs.error),
                          onPressed: () => confirmDeleteFiles(
                            context,
                            what: l10n.downloadsJobFiles(job.title, kindLabels[job.kind] ?? job.kind, job.totalBytes > 0 ? l10n.downloadsSizeSuffix(fmtBytes(job.totalBytes)) : ''),
                            run: () => app.removeJobFiles(job.id),
                          ),
                          child: Text(l10n.downloadsDeleteRecordAndFiles, style: TextStyle(color: cs.error)),
                        ),
                    ],
                    builder: (context, m, _) => IconButton(
                      tooltip: l10n.commonDelete,
                      onPressed: () => m.isOpen ? m.close() : m.open(),
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// The bar and status line of an unfinished job. Only a running job is drawn
/// in the accent colour; waiting and paused jobs keep their progress on a
/// muted bar, and the bar only sweeps while lookd works without knowing the
/// size yet.
class _JobProgress extends StatelessWidget {
  const _JobProgress({required this.job});
  final Job job;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final running = job.state == 'running';
    final retryAt = job.state == 'queued' ? job.retryAt : null;
    final known = job.totalBytes > 0 || job.progress > 0;
    final percent = (job.progress * 100).floor();
    final (IconData icon, String label) = switch (job.state) {
      'running' => (Icons.arrow_downward_rounded, job.stage.isNotEmpty ? job.stage : l10n.downloadsStateRunning),
      'queued' when retryAt != null => (Icons.wifi_off_rounded, l10n.downloadsStateRetrying(fmtClockTime(retryAt))),
      'paused' => (Icons.pause_rounded, l10n.commonPaused),
      _ => (Icons.schedule_rounded, l10n.commonQueued),
    };
    final tone = running ? cs.primary : retryAt != null ? cs.error : cs.onSurfaceVariant;
    final details = [
      label,
      if (running && job.speed > 0) fmtSpeed(job.speed),
      if (job.totalBytes > 0) l10n.downloadsSizeProgress(fmtBytes(job.doneBytes), fmtBytes(job.totalBytes)),
      if (running && job.conns > 1) l10n.downloadsConnections(job.conns),
    ];
    const figures = [FontFeature.tabularFigures()];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TweenAnimationBuilder<double>(
        tween: Tween(end: job.progress),
        duration: Motion.medium2,
        builder: (_, v, _) => LinearProgressIndicator(
          value: running && !known ? null : v,
          color: running ? cs.primary : retryAt != null ? cs.error : cs.outline,
          backgroundColor: running ? null : cs.surfaceContainerHighest,
          stopIndicatorColor: running ? null : cs.outline,
          borderRadius: BorderRadius.circular(Corners.full),
          semanticsLabel: label,
          semanticsValue: known ? l10n.downloadsPercent(percent) : null,
        ),
      ),
      const SizedBox(height: Space.xs),
      Row(children: [
        Icon(icon, size: 14, color: tone),
        const SizedBox(width: Space.xs),
        Expanded(
          child: Text(details.join(' · '),
              maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.labelSmall?.copyWith(color: retryAt != null ? cs.error : cs.onSurfaceVariant, fontFeatures: figures)),
        ),
        if (known) ...[
          const SizedBox(width: Space.sm),
          Text(l10n.downloadsPercent(percent), style: tt.labelMedium?.copyWith(color: tone, fontFeatures: figures)),
        ],
      ]),
    ]);
  }
}

/// Floating toolbar for the picked jobs (M3 Expressive floating toolbar):
/// actions that don't apply to any picked job stay visible but disabled.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.allPicked,
    required this.showRetry,
    required this.can,
    required this.onClose,
    required this.onAll,
    required this.onAction,
  });
  final int count;
  final bool allPicked, showRetry;
  final Set<String> can;
  final VoidCallback onClose, onAll;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Material(
      color: cs.secondaryContainer,
      elevation: 3,
      shadowColor: cs.shadow,
      surfaceTintColor: Colors.transparent,
      shape: const StadiumBorder(),
      child: Padding(
        padding: const EdgeInsets.all(Space.xs),
        child: IconButtonTheme(
          data: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: cs.onSecondaryContainer)),
          child: LayoutBuilder(builder: (context, box) {
            final labels = box.maxWidth >= 640;
            Widget act(String a, IconData icon, String label) {
              final on = can.contains(a) ? () => onAction(a) : null;
              return labels
                  ? TextButton.icon(onPressed: on, style: TextButton.styleFrom(foregroundColor: cs.onSecondaryContainer), icon: Icon(icon, size: 20), label: Text(label))
                  : IconButton(tooltip: label, onPressed: on, icon: Icon(icon));
            }

            return Row(children: [
              IconButton(tooltip: l10n.downloadsExitSelection, onPressed: onClose, icon: const Icon(Icons.close_rounded)),
              const SizedBox(width: Space.xs),
              Expanded(
                child: Text(l10n.downloadsSelectedCount(count),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.titleSmall?.copyWith(color: cs.onSecondaryContainer)),
              ),
              IconButton(
                tooltip: allPicked ? l10n.downloadsSelectNone : l10n.commonSelectAll,
                onPressed: onAll,
                icon: Icon(allPicked ? Icons.deselect_rounded : Icons.select_all_rounded),
              ),
              act('pause', Icons.pause_rounded, l10n.commonPause),
              act('resume', Icons.play_arrow_rounded, l10n.commonResume),
              if (showRetry) act('retry', Icons.refresh_rounded, l10n.commonRetry),
              act('cancel', Icons.stop_circle_outlined, l10n.downloadsCancelConfirm),
            ]);
          }),
        ),
      ),
    );
  }
}
