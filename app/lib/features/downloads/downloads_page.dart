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

class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key});
  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  int _view = 0; // 0 tasks, 1 local files

  Future<void> _clearFinished() async {
    final app = context.read<AppState>();
    var files = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          icon: const Icon(Icons.cleaning_services_outlined),
          title: const Text('清除已完成的任务'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('任务记录会被清除。已下载的文件默认保留在课程库中。'),
            const SizedBox(height: Space.md),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: files,
              onChanged: (v) => set(() => files = v ?? false),
              title: const Text('同时删除已下载的文件'),
              subtitle: const Text('视频、PPT、课件和文字稿会从磁盘移除，不可恢复'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
            FilledButton(
              style: files ? FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error, foregroundColor: Theme.of(context).colorScheme.onError) : null,
              onPressed: () => Navigator.pop(context, true),
              child: Text(files ? '清除并删除文件' : '清除记录'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      final freed = await app.clearFinished(files: files);
      if (mounted) showSnack(context, files ? '已清除，释放 ${fmtBytes(freed)}' : '已清除任务记录');
    } catch (e) {
      if (mounted) showSnack(context, '清除失败：$e');
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

    final header = SliverToBoxAdapter(
      child: ContentWidth(
        child: Padding(
          padding: EdgeInsets.fromLTRB(pad, compact ? Space.xl : Space.xxl, pad, Space.md),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('下载', style: compact ? tt.headlineMedium : tt.displaySmall),
            const SizedBox(height: Space.xs),
            AnimatedSwitcher(
              duration: Motion.short4,
              child: Text(
                key: ValueKey(running > 0),
                running > 0 ? '$running 个任务进行中 · ${fmtSpeed(speed)}' : active.isEmpty ? '没有进行中的任务' : '${active.length} 个任务等待中',
                style: tt.bodyLarge?.copyWith(color: running > 0 ? cs.primary : cs.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: Space.lg),
            Row(children: [
              SegmentedButton<int>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: 0, icon: const Icon(Icons.downloading_rounded), label: Text(jobs.isEmpty ? '任务' : '任务 ${jobs.length}')),
                  const ButtonSegment(value: 1, icon: Icon(Icons.inventory_2_outlined), label: Text('已下载')),
                ],
                selected: {_view},
                onSelectionChanged: (v) => setState(() => _view = v.first),
              ),
              const Spacer(),
              if (_view == 0 && pausable > 0)
                TextButton.icon(onPressed: () => _bulk('pause'), icon: const Icon(Icons.pause_rounded, size: 18), label: const Text('全部暂停')),
              if (_view == 0 && paused > 0)
                TextButton.icon(onPressed: () => _bulk('resume'), icon: const Icon(Icons.play_arrow_rounded, size: 18), label: Text('全部继续 $paused')),
              AnimatedSwitcher(
                duration: Motion.short4,
                child: _view == 0 && done.isNotEmpty
                    ? TextButton.icon(onPressed: _clearFinished, icon: const Icon(Icons.cleaning_services_outlined, size: 18), label: const Text('清除已完成'))
                    : const SizedBox.shrink(),
              ),
            ]),
          ]),
        ),
      ),
    );

    return ReportScreen(
      value: {'screen': '下载管理', 'view': _view == 0 ? '任务' : '已下载'},
      child: _view == 1
          ? _LocalView(header: header, pad: pad)
          : CustomScrollView(slivers: [
              header,
              if (jobs.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.download_rounded,
                    title: '还没有下载',
                    body: '在课程里选择课次，点下载按钮。视频、PPT、课件和文字稿会按课程整理到课程库。',
                  ),
                ),
              ..._section(context, '进行中', active, pad),
              ..._section(context, '失败', failed, pad, action: TextButton.icon(onPressed: () => _bulk('retry'), icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('全部重试'))),
              ..._section(context, '已完成', done, pad),
              const SliverToBoxAdapter(child: SizedBox(height: Space.huge)),
            ]),
    );
  }

  Future<void> _bulk(String action) async {
    final app = context.read<AppState>();
    try {
      final n = await app.bulkJobs(action);
      if (mounted && n > 0) showSnack(context, '${const {'pause': '已暂停', 'resume': '已继续', 'retry': '已重试'}[action]} $n 个任务');
    } catch (e) {
      if (mounted) showSnack(context, '操作失败：$e');
    }
  }

  List<Widget> _section(BuildContext context, String title, List<Job> list, double pad, {Widget? action}) {
    if (list.isEmpty) return const [];
    return [
      SliverToBoxAdapter(
        child: ContentWidth(
          child: Padding(
            padding: EdgeInsets.fromLTRB(pad, Space.lg, pad - Space.sm, action == null ? Space.sm : 0),
            child: Row(children: [
              Expanded(
                child: Text('$title · ${list.length}', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
              ?action,
            ]),
          ),
        ),
      ),
      SliverList.builder(
        itemCount: list.length,
        itemBuilder: (context, i) => ContentWidth(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: pad, vertical: 2),
            child: _JobTile(key: ValueKey(list[i].id), job: list[i]),
          ),
        ),
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
      title: const Text('删除文件？'),
      content: Text('将从磁盘删除$what，不可恢复。需要时可以重新下载。'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error, foregroundColor: Theme.of(context).colorScheme.onError),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('删除'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  try {
    final freed = await run();
    if (context.mounted) showSnack(context, '已删除，释放 ${fmtBytes(freed)}');
  } catch (e) {
    if (context.mounted) showSnack(context, '删除失败：$e');
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
          const SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(icon: Icons.inventory_2_outlined, title: '本地还没有文件', body: '下载完成的视频、PPT、课件和文字稿会出现在这里。'),
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
                        Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('占用空间', style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant))),
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
                                      deleteButtonTooltipMessage: '删除${kindLabels[it.kind] ?? ''}文件',
                                      onDeleted: () => _delete(it.lectureId, [it.kind], '这节课的${kindLabels[it.kind] ?? it.kind}（${fmtBytes(it.bytes)}）'),
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
                                    child: const Text('在文件夹中显示'),
                                  ),
                                MenuItemButton(
                                  leadingIcon: Icon(Icons.delete_forever_outlined, color: cs.error),
                                  onPressed: () => _delete(entry.key, [for (final x in list) x.kind],
                                      '这节课的全部文件（${fmtBytes(list.fold(0, (s, x) => s + x.bytes))}）'),
                                  child: Text('删除全部文件', style: TextStyle(color: cs.error)),
                                ),
                              ],
                              builder: (context, m, _) => IconButton(
                                tooltip: '更多',
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
    if (!ok && context.mounted) showSnack(context, '没能打开文件夹');
  } catch (e) {
    if (context.mounted) showSnack(context, '$e');
  }
}

class _JobTile extends StatelessWidget {
  const _JobTile({super.key, required this.job});
  final Job job;

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
    final retryAt = job.state == 'queued' ? job.retryAt : null;
    final stateText = switch (job.state) {
      'running' => job.stage.isNotEmpty ? job.stage : '下载中',
      'queued' when retryAt != null => '网络中断 · ${fmtClockTime(retryAt)} 自动重试',
      'queued' when job.progress > 0 => '排队中 · 将从 ${(job.progress * 100).round()}% 继续',
      'queued' => '排队中',
      'paused' => '已暂停',
      'failed' => '失败',
      'done' => '已完成',
      'canceled' => '已取消',
      _ => job.state,
    };
    final sizeText = job.totalBytes > 0 ? '${fmtBytes(job.doneBytes)} / ${fmtBytes(job.totalBytes)}' : '';

    return Card(
      color: failed ? cs.errorContainer.withValues(alpha: 0.4) : cs.surfaceContainer,
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(Corners.md),
        onTap: done && job.kind == 'video'
            ? () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => PlayerPage(lectureId: job.lectureId)))
            : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.sm, Space.md),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: done ? cs.tertiaryContainer : failed ? cs.errorContainer : cs.secondaryContainer,
                borderRadius: BorderRadius.circular(Corners.md),
              ),
              child: Icon(done ? Icons.download_done_rounded : _icon,
                  color: done ? cs.onTertiaryContainer : failed ? cs.onErrorContainer : cs.onSecondaryContainer),
            ),
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
                  TweenAnimationBuilder<double>(
                    tween: Tween(end: job.progress),
                    duration: Motion.medium2,
                    builder: (_, v, _) => LinearProgressIndicator(
                      value: job.state == 'queued' && job.progress == 0 ? null : v,
                      borderRadius: BorderRadius.circular(4),
                      color: job.state == 'paused' ? cs.outline : null,
                    ),
                  ),
                  const SizedBox(height: Space.xs),
                  Row(children: [
                    Text(stateText, style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                    if (job.conns > 1) Text(' · ${job.conns} 路并发', style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                    const Spacer(),
                    if (sizeText.isNotEmpty) Text(sizeText, style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant, fontFeatures: const [FontFeature.tabularFigures()])),
                    if (job.state == 'running' && job.speed > 0)
                      Text('  ${fmtSpeed(job.speed)}', style: tt.labelSmall?.copyWith(color: cs.primary, fontFeatures: const [FontFeature.tabularFigures()])),
                  ]),
                ] else if (failed) ...[
                  const SizedBox(height: Space.xs),
                  Text(job.error, style: tt.bodySmall?.copyWith(color: cs.error), maxLines: 2, overflow: TextOverflow.ellipsis),
                ] else if (done && job.totalBytes > 0)
                  Text(fmtBytes(job.totalBytes), style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
              ]),
            ),
            const SizedBox(width: Space.sm),
            if (job.state == 'running' || job.state == 'queued')
              IconButton(tooltip: '暂停', onPressed: () => app.jobAction(job.id, 'pause'), icon: const Icon(Icons.pause_rounded)),
            if (job.state == 'paused')
              IconButton(tooltip: '继续', onPressed: () => app.jobAction(job.id, 'resume'), icon: const Icon(Icons.play_arrow_rounded)),
            if (failed) IconButton(tooltip: '重试', onPressed: () => app.jobAction(job.id, 'retry'), icon: const Icon(Icons.refresh_rounded)),
            if (done && canOpenFolders) IconButton(tooltip: '在文件夹中显示', onPressed: () => revealLecture(context, job.lectureId), icon: const Icon(Icons.folder_open_outlined)),
            if (job.active || job.state == 'paused')
              IconButton(tooltip: '取消', onPressed: () => app.jobAction(job.id, 'cancel'), icon: const Icon(Icons.close_rounded))
            else
              MenuAnchor(
                menuChildren: [
                  MenuItemButton(
                    leadingIcon: const Icon(Icons.playlist_remove_rounded),
                    onPressed: () => app.jobAction(job.id, 'remove'),
                    child: const Text('仅移除记录'),
                  ),
                  if (done)
                    MenuItemButton(
                      leadingIcon: Icon(Icons.delete_forever_outlined, color: cs.error),
                      onPressed: () => confirmDeleteFiles(
                        context,
                        what: '「${job.title}」的${kindLabels[job.kind] ?? job.kind}文件${job.totalBytes > 0 ? '（${fmtBytes(job.totalBytes)}）' : ''}',
                        run: () => app.removeJobFiles(job.id),
                      ),
                      child: Text('删除记录和文件', style: TextStyle(color: cs.error)),
                    ),
                ],
                builder: (context, m, _) => IconButton(
                  tooltip: '删除',
                  onPressed: () => m.isOpen ? m.close() : m.open(),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
