import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/open_path.dart';
import '../../theme/tokens.dart';
import '../../widgets/look_markdown.dart' show openPlainLink;
import '../../widgets/states.dart';
import '../../l10n/l10n.dart';

Map<String, dynamic> _map(Object? v) => v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};
List<Map<String, dynamic>> _maps(Object? v) => jsonList(v).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
DateTime? _time(Object? v) => DateTime.tryParse('${v ?? ''}')?.toLocal();

String _due(DateTime d) => l10n.dateMonthDayTime(d.month, d.day, d.hour.toString().padLeft(2, '0'), d.minute.toString().padLeft(2, '0'));

String _plain(String html) => html
    .replaceAll(RegExp(r'<br\s*/?>|</p>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'<[^>]*>'), '')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll(RegExp(r'\n\s*\n+'), '\n')
    .trim();

/// Assignment state, worded for a student.
({String label, IconData icon, bool alert}) assignmentState(Map<String, dynamic> a) {
  final due = _time(a['due_at']);
  final sub = _map(a['submission']);
  if (sub['workflow_state'] == 'graded') return (label: sub['score'] != null ? l10n.assignmentGradedScore(sub['score']) : l10n.assignmentGraded, icon: Icons.task_alt_rounded, alert: false);
  if (a['done'] == true) return (label: l10n.commonDone, icon: Icons.check_circle_outline_rounded, alert: false);
  if (due != null && due.isBefore(DateTime.now())) return (label: l10n.assignmentMissing, icon: Icons.error_outline_rounded, alert: true);
  if (due != null) return (label: l10n.assignmentTimeLeft(fmtUntil(due)), icon: Icons.radio_button_unchecked_rounded, alert: due.difference(DateTime.now()).inHours < 24);
  return (label: l10n.assignmentNoDue, icon: Icons.radio_button_unchecked_rounded, alert: false);
}

/// The Canvas side of a Look course: open assignments and shortcuts to all
/// assignments, files and announcements. Hidden when no Canvas course is
/// linked to it.
class CanvasCourseSection extends StatefulWidget {
  const CanvasCourseSection({super.key, required this.courseId, this.api, this.events});
  final String courseId;
  final ApiCall? api;
  final Stream<Map<String, dynamic>>? events;
  @override
  State<CanvasCourseSection> createState() => _CanvasCourseSectionState();
}

class _CanvasCourseSectionState extends State<CanvasCourseSection> {
  List<Map<String, dynamic>> _details = [];
  StreamSubscription? _sub;

  ApiCall get _call => widget.api ?? context.read<AppState>().api.call;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = (widget.events ?? context.read<AppState>().events).listen((e) {
      final what = _map(e['data'])['what'];
      if (e['type'] == 'canvas_changed' && what != 'syncing') _load();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final st = _map(_map(await _call('GET', '/api/canvas'))['status']);
      final linked = _maps(st['courses']).where((c) => c['look_course'] == widget.courseId);
      final out = <Map<String, dynamic>>[];
      for (final c in linked) {
        out.add(_map(await _call('GET', '/api/canvas/courses/${c['id']}')));
      }
      if (mounted) setState(() => _details = out);
    } catch (_) {
      // Canvas is optional; the course page works without it.
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: Motion.medium2,
      curve: Motion.emphasized,
      alignment: Alignment.topCenter,
      child: Column(children: [for (final d in _details) _CanvasCard(detail: d, api: widget.api)]),
    );
  }
}

class _CanvasCard extends StatelessWidget {
  const _CanvasCard({required this.detail, this.api});
  final Map<String, dynamic> detail;
  final ApiCall? api;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final c = _map(detail['course']);
    final id = '${c['id']}';
    final name = '${c['name']}';
    final now = DateTime.now();
    final as = _maps(detail['assignments']);
    final open = as.where((a) => a['done'] != true && (_time(a['due_at'])?.isAfter(now) ?? false)).toList()
      ..sort((a, b) => _time(a['due_at'])!.compareTo(_time(b['due_at'])!));
    final anns = _maps(detail['announcements']);
    void sheet(int tab) => showCanvasCourseSheet(context, id, name, tab: tab, api: api);
    return Padding(
      padding: const EdgeInsets.only(top: Space.md),
      child: Material(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(Corners.xl),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.sm, Space.md),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(Icons.cloud_sync_outlined, size: 20, color: cs.primary),
              const SizedBox(width: Space.sm),
              Expanded(child: Text('Canvas · $name', style: tt.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
              Text(open.isEmpty ? l10n.canvasNoOpenAssignments : l10n.assignmentOpenCount(open.length), style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(width: Space.sm),
            ]),
            for (final a in open.take(3))
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.only(left: Space.xxs, right: Space.sm),
                visualDensity: VisualDensity.compact,
                leading: Icon(assignmentState(a).icon, size: 20, color: assignmentState(a).alert ? cs.error : cs.onSurfaceVariant),
                title: Text('${a['name']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(l10n.assignmentDue(_due(_time(a['due_at'])!), assignmentState(a).label),
                    style: assignmentState(a).alert ? TextStyle(color: cs.error) : null),
                onTap: () => openPlainLink(context, '${a['html_url'] ?? ''}'),
              ),
            const SizedBox(height: Space.xs),
            Wrap(spacing: Space.sm, runSpacing: Space.xs, children: [
              ActionChip(avatar: const Icon(Icons.assignment_outlined, size: 18), label: Text(l10n.canvasAssignmentsTab(as.length)), onPressed: () => sheet(0)),
              ActionChip(avatar: const Icon(Icons.folder_outlined, size: 18), label: Text(l10n.assetCourseware), onPressed: () => sheet(1)),
              ActionChip(avatar: const Icon(Icons.campaign_outlined, size: 18), label: Text(l10n.canvasAnnouncementsTab(anns.length)), onPressed: () => sheet(2)),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// All of a Canvas course: assignments, files (download into the course
/// folder) and recent announcements. A side dialog on wide windows, a
/// bottom sheet on compact ones.
Future<void> showCanvasCourseSheet(BuildContext context, String canvasId, String name, {int tab = 0, ApiCall? api}) {
  final body = CanvasCourseView(canvasId: canvasId, name: name, tab: tab, api: api);
  if (!context.isCompact) {
    return showDialog(
      context: context,
      useRootNavigator: true,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Corners.xl)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640, maxHeight: 720), child: body),
      ),
    );
  }
  return showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => SizedBox(height: MediaQuery.sizeOf(c).height * 0.85, child: body),
  );
}

class CanvasCourseView extends StatefulWidget {
  const CanvasCourseView({super.key, required this.canvasId, required this.name, this.tab = 0, this.api, this.libraryRoot});
  final String canvasId;
  final String name;
  final int tab;
  final ApiCall? api;
  final String? libraryRoot;
  @override
  State<CanvasCourseView> createState() => _CanvasCourseViewState();
}

class _CanvasCourseViewState extends State<CanvasCourseView> {
  Map<String, dynamic>? _detail;
  List<Map<String, dynamic>>? _files;
  Object? _error, _filesError;
  final _downloading = <String>{};
  final _saved = <String, String>{}; // file id -> library path

  ApiCall get _call => widget.api ?? context.read<AppState>().api.call;
  String get _root => widget.libraryRoot ?? context.read<AppState>().daemon.libraryRoot;

  @override
  void initState() {
    super.initState();
    _load();
    _loadFiles();
  }

  Future<void> _load() async {
    try {
      final d = _map(await _call('GET', '/api/canvas/courses/${widget.canvasId}'));
      if (mounted) setState(() => _detail = d);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _loadFiles() async {
    setState(() => _filesError = null);
    try {
      final fs = _maps(await _call('GET', '/api/canvas/courses/${widget.canvasId}/files'));
      if (mounted) setState(() => _files = fs);
    } catch (e) {
      if (mounted) setState(() => _filesError = e);
    }
  }

  Future<void> _download(Map<String, dynamic> f) async {
    final id = '${f['id']}';
    setState(() => _downloading.add(id));
    try {
      final body = {'course': widget.canvasId};
      final path = '/api/canvas/files/$id/download';
      final r = _map(await (widget.api != null ? _call('POST', path, body) : context.read<AppState>().api.post(path, body, const Duration(minutes: 10))));
      if (!mounted) return;
      setState(() => _saved[id] = '${r['path']}');
      showSnack(context, l10n.canvasSavedToCourse, action: l10n.commonShowInFolder, onAction: () => revealPath('$_root/${r['path']}'));
    } catch (e) {
      if (mounted) showSnack(context, l10n.commonDownloadFailed(e));
    } finally {
      if (mounted) setState(() => _downloading.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final d = _detail;
    return DefaultTabController(
      length: 3,
      initialIndex: widget.tab,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.xl, Space.lg, Space.lg, 0),
          child: Row(children: [
            Expanded(child: Text(widget.name, style: tt.titleLarge, maxLines: 2, overflow: TextOverflow.ellipsis)),
            if (!context.isCompact) IconButton(tooltip: l10n.commonClose, onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
          ]),
        ),
        TabBar(tabs: [Tab(text: l10n.commonAssignments), Tab(text: l10n.assetCourseware), Tab(text: l10n.canvasAnnouncement)]),
        Expanded(
          child: d == null
              ? (_error != null ? ErrorState(error: _error!, onRetry: _load) : const CenteredLoader())
              : TabBarView(children: [_assignments(context, d), _filesTab(context), _announcements(context, d)]),
        ),
      ]),
    );
  }

  Widget _assignments(BuildContext context, Map<String, dynamic> d) {
    final cs = Theme.of(context).colorScheme;
    final as = _maps(d['assignments']);
    if (as.isEmpty) return EmptyState(icon: Icons.assignment_outlined, title: l10n.canvasNoAssignments, body: l10n.canvasNoAssignmentsBody);
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      itemCount: as.length,
      itemBuilder: (_, i) {
        final a = as[i];
        final s = assignmentState(a);
        final due = _time(a['due_at']);
        final pts = a['points_possible'];
        return ListTile(
          leading: Icon(s.icon, color: s.alert ? cs.error : (a['done'] == true ? cs.primary : cs.onSurfaceVariant)),
          title: Text('${a['name']}'),
          subtitle: Text([if (due != null) l10n.assignmentDueShort(_due(due)), if (pts is num && pts > 0) l10n.assignmentPoints(pts), s.label].join(' · '),
              style: s.alert ? TextStyle(color: cs.error) : null),
          trailing: const Icon(Icons.open_in_new_rounded, size: 18),
          onTap: () => openPlainLink(context, '${a['html_url'] ?? ''}'),
        );
      },
    );
  }

  Widget _filesTab(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fs = _files;
    if (fs == null) return _filesError != null ? ErrorState(error: _filesError!, onRetry: _loadFiles) : CenteredLoader(label: l10n.canvasLoadingFiles);
    if (fs.isEmpty) return EmptyState(icon: Icons.folder_off_outlined, title: l10n.canvasNoFiles, body: l10n.canvasNoFilesBody);
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      itemCount: fs.length,
      itemBuilder: (_, i) {
        final f = fs[i];
        final id = '${f['id']}';
        final locked = f['locked_for_user'] == true;
        final saved = _saved[id];
        final size = (f['size'] as num?) ?? 0;
        final updated = _time(f['updated_at']);
        return ListTile(
          leading: Icon(_fileIcon('${f['display_name']}'), color: cs.onSurfaceVariant),
          title: Text('${f['display_name']}', maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text([
            if (size > 0) fmtBytes(size),
            if (updated != null) l10n.canvasFileUpdated(updated.month, updated.day),
            if ('${f['module'] ?? ''}'.isNotEmpty) '${f['module']}',
            if (locked) l10n.canvasFileLocked,
          ].join(' · ')),
          trailing: _downloading.contains(id)
              ? const Padding(padding: EdgeInsets.all(Space.md), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)))
              : saved != null
                  ? IconButton(tooltip: l10n.commonOpen, onPressed: () => openPath('$_root/$saved'), icon: const Icon(Icons.file_open_outlined))
                  : IconButton(tooltip: l10n.canvasDownloadToCourse, onPressed: locked ? null : () => _download(f), icon: const Icon(Icons.download_rounded)),
        );
      },
    );
  }

  Widget _announcements(BuildContext context, Map<String, dynamic> d) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final ns = _maps(d['announcements']);
    if (ns.isEmpty) return EmptyState(icon: Icons.campaign_outlined, title: l10n.canvasNoAnnouncements);
    return ListView.separated(
      padding: const EdgeInsets.all(Space.lg),
      itemCount: ns.length,
      separatorBuilder: (_, _) => const SizedBox(height: Space.md),
      itemBuilder: (_, i) {
        final n = ns[i];
        final at = _time(n['posted_at']);
        final author = '${_map(n['author'])['display_name'] ?? ''}';
        return Material(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(Corners.lg),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => openPlainLink(context, '${n['html_url'] ?? ''}'),
            child: Padding(
              padding: const EdgeInsets.all(Space.lg),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${n['title']}', style: tt.titleSmall),
                const SizedBox(height: Space.xxs),
                Text([if (author.isNotEmpty) author, if (at != null) fmtRelative(at)].join(' · '), style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: Space.sm),
                Text(_plain('${n['message'] ?? ''}'), maxLines: 4, overflow: TextOverflow.ellipsis, style: tt.bodyMedium),
              ]),
            ),
          ),
        );
      },
    );
  }
}

IconData _fileIcon(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  return switch (ext) {
    'pdf' => Icons.picture_as_pdf_outlined,
    'ppt' || 'pptx' || 'key' => Icons.slideshow_outlined,
    'doc' || 'docx' || 'txt' || 'md' => Icons.description_outlined,
    'xls' || 'xlsx' || 'csv' => Icons.table_chart_outlined,
    'zip' || 'rar' || '7z' => Icons.folder_zip_outlined,
    'mp4' || 'mov' || 'mkv' => Icons.movie_outlined,
    'png' || 'jpg' || 'jpeg' || 'gif' => Icons.image_outlined,
    _ => Icons.insert_drive_file_outlined,
  };
}
