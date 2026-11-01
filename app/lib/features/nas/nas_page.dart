import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../l10n/l10n.dart';
import '../../widgets/look_markdown.dart';
import '../courses/course_page.dart';

List<Map<String, dynamic>> nasRows(dynamic v) => v is List
    ? v.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList()
    : [];

class NasPage extends StatefulWidget {
  const NasPage({
    super.key,
    this.courseId = '',
    this.initialTab = 0,
    this.call,
  });
  final String courseId;
  final int initialTab;
  final ApiCall? call;
  @override
  State<NasPage> createState() => _NasPageState();
}

class _NasPageState extends State<NasPage> {
  Map<String, dynamic>? data;
  String course = '', query = '';
  bool busy = false, acting = false, selected = false;
  String? error, notice;
  Timer? timer;
  Future<dynamic> call(String method, String path, [Object? body]) =>
      widget.call != null
      ? widget.call!(method, path, body)
      : context.read<AppState>().api.call(method, path, body);
  @override
  void initState() {
    super.initState();
    load();
    timer = Timer.periodic(const Duration(seconds: 30), (_) => load());
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> load({bool refresh = false}) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final d = (await call(
        'GET',
        '/api/nas${refresh ? '?refresh=1' : ''}',
      ) as Map).cast<String, dynamic>();
      if (!mounted) return;
      setState(() {
        data = d;
        error = null;
        if (!selected && widget.courseId.isNotEmpty) {
          final links = (d['course_links'] as Map?) ?? {};
          final matches = links.entries
              .where((e) => e.value == widget.courseId)
              .toList();
          if (matches.length == 1) course = '${matches.single.key}';
          selected = true;
        }
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> run(String action) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(
          action == 'homework' ? l10n.nasRunHomework : l10n.nasRunCalendar,
        ),
        content: Text(
          action == 'homework'
              ? l10n.nasHomeworkConfirm
              : l10n.nasCalendarConfirm,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(l10n.nasRun),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => acting = true);
    try {
      final result = await call('POST', '/api/nas/actions/$action');
      if (mounted) setState(() => notice = '${result['message']}');
      await load(refresh: true);
    } catch (e) {
      if (mounted) setState(() => notice = '$e');
    } finally {
      if (mounted) setState(() => acting = false);
    }
  }

  bool matches(Map<String, dynamic> r) =>
      (course.isEmpty || r['course'] == course) &&
      (query.isEmpty ||
          '${r['name']} ${r['path']} ${r['title']} ${r['course']}'
              .toLowerCase()
              .contains(query.toLowerCase()));
  Future<void> openFile(Map<String, dynamic> f) async {
    if (f['available'] == false) return;
    final id = '${f['id']}', path = '${f['path']}';
    if (RegExp(
      r'\.(md|txt|srt|py|c|h|cpp|html|csv)$',
      caseSensitive: false,
    ).hasMatch(path)) {
      try {
        final d = await call('GET', '/api/nas/files/$id/text');
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => Scaffold(
              appBar: AppBar(
                title: Text(path.split('/').last),
                actions: [
                  if (widget.call == null)
                    TextButton.icon(
                      onPressed: () => openPlainLink(
                        context,
                        context.read<AppState>().api.nasFileUrl(id),
                      ),
                      icon: const Icon(Icons.open_in_new),
                      label: Text(l10n.nasFullFile),
                    ),
                ],
              ),
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: SelectableText(
                  '${d['text']}${d['truncated'] == true ? '\n\n${l10n.nasTextTruncated}' : ''}',
                ),
              ),
            ),
          ),
        );
      } catch (e) {
        if (mounted) setState(() => notice = '$e');
      }
    } else {
      await openPlainLink(context, context.read<AppState>().api.nasFileUrl(id));
    }
  }

  Future<void> linkCourse(String id) async {
    try {
      await call('PUT', '/api/nas/links', {'course': course, 'icourse_id': id});
      await load();
    } catch (e) {
      if (mounted) setState(() => notice = '$e');
    }
  }

  String dateLabel(dynamic value) {
    final parsed = DateTime.tryParse('$value');
    if (parsed == null) return '${value ?? '—'}';
    final local = parsed.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  String serviceName(String id) => switch (id) {
    'homework' => l10n.nasHomeworkService,
    'calendar' => l10n.nasCalendarService,
    'icourse-subscriber' => l10n.nasLectureService,
    'course-calendar-sync' => l10n.nasCalendarContainer,
    _ => id,
  };
  String stateName(String s) => switch (s) {
    'ready' => l10n.nasReady,
    'not_recorded' => l10n.nasGenerationUnknown,
    'failed' => l10n.nasFailed,
    'existing' => l10n.nasExisting,
    'running' => l10n.nasRunning,
    'queued' => l10n.nasQueued,
    'needs_input' => l10n.nasNeedsInput,
    _ => s,
  };
  @override
  Widget build(BuildContext context) {
    final files = nasRows(data?['files']);
    final courses = {
      ...files.map((f) => '${f['course']}'),
      ...nasRows(data?['jobs']).map((f) => '${f['course']}'),
    }.toList()..sort();
    final links = (data?['course_links'] as Map?) ?? {};
    final jobs = nasRows(data?['jobs']).where(matches).toList();
    final deadlines = nasRows(data?['deadlines']).where(matches).toList();
    final shownFiles = files.where(matches).toList();
    final appCourses = widget.call == null
        ? context.watch<AppState>().courses
        : [];
    final linked = '${links[course] ?? ''}';
    return DefaultTabController(
      length: 4,
      initialIndex: widget.initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.nasTitle),
          actions: [
            IconButton(
              tooltip: l10n.nasRefresh,
              onPressed: busy ? null : () => load(refresh: true),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (busy) const LinearProgressIndicator(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data?['online'] == true ? l10n.nasOnline : l10n.nasOffline,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    '${l10n.nasObserved}: ${dateLabel(data?['observed_at'])}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (error != null || data?['error'] != null)
                    Text(
                      error ?? '${data!['error']}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  if (data?['files_error'] != null)
                    Text('${data!['files_error']}'),
                  if (data?['calendar_error'] != null)
                    Text('${data!['calendar_error']}'),
                  if (notice != null)
                    Text(
                      notice!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      DropdownButton<String>(
                        value: courses.contains(course) ? course : '',
                        items: [
                          DropdownMenuItem(
                            value: '',
                            child: Text(l10n.nasAllCourses),
                          ),
                          ...courses.map(
                            (c) => DropdownMenuItem(
                              value: c,
                              child: SizedBox(
                                width: 235,
                                child: Text(c, overflow: TextOverflow.ellipsis),
                              ),
                            ),
                          ),
                        ],
                        onChanged: (v) => setState(() {
                          course = v ?? '';
                          selected = true;
                        }),
                      ),
                      SizedBox(
                        width: 220,
                        child: TextField(
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search),
                            hintText: l10n.nasSearch,
                          ),
                          onChanged: (v) => setState(() => query = v),
                        ),
                      ),
                      if (course.isNotEmpty)
                        DropdownButton<String>(
                          value: appCourses.any((c) => c.id == linked)
                              ? linked
                              : '',
                          hint: Text(l10n.nasLinkCourse),
                          items: [
                            DropdownMenuItem(
                              value: '',
                              child: Text(l10n.nasUnlinked),
                            ),
                            ...appCourses.map(
                              (c) => DropdownMenuItem(
                                value: c.id,
                                child: Text(c.title),
                              ),
                            ),
                          ],
                          onChanged: (v) => linkCourse(v ?? ''),
                        ),
                      if (linked.isNotEmpty)
                        TextButton.icon(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CoursePage(courseId: linked),
                            ),
                          ),
                          icon: const Icon(Icons.play_circle_outline),
                          label: Text(l10n.nasOpenRecording),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            TabBar(
              isScrollable: true,
              tabs: [
                Tab(text: '${l10n.nasHomework} (${jobs.length})'),
                Tab(text: '${l10n.nasDeadlines} (${deadlines.length})'),
                Tab(text: l10n.nasMaterials),
                Tab(text: l10n.nasServices),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Text(l10n.nasSeparateStates),
                      ...jobs.map(
                        (j) => Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${j['name']}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                Text('${j['course']}'),
                                Text(
                                  '${stateName('${j['generation_state']}')} · ${j['submission_state'] == 'submitted' ? l10n.nasSubmitted : l10n.nasUnconfirmed}',
                                ),
                                if (j['due_at'] != null)
                                  Text(
                                    '${l10n.nasDue}: ${DateTime.tryParse('${j['due_at']}')?.toLocal() ?? j['due_at']}',
                                  ),
                                if (j['reason'] == 'execution_timeout')
                                  Text(l10n.nasTimeout),
                                if (j['reason'] == 'needs_attention')
                                  Text(l10n.nasNeedsInput),
                                Builder(
                                  builder: (tabContext) => TextButton.icon(
                                    icon: const Icon(Icons.folder_open),
                                    label: Text(l10n.nasRelatedFiles),
                                    onPressed: () {
                                      setState(() {
                                        course = '${j['course']}';
                                        query = '';
                                      });
                                      DefaultTabController.of(tabContext)
                                          .animateTo(2);
                                    },
                                  ),
                                ),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    ...nasRows(j['reports']).map(
                                      (f) => TextButton.icon(
                                        onPressed: f['available'] == true
                                            ? () => openFile(f)
                                            : null,
                                        icon: const Icon(
                                          Icons.description_outlined,
                                        ),
                                        label: Text(
                                          '${f['path']}'.split('/').last,
                                        ),
                                      ),
                                    ),
                                    if ('${j['url'] ?? ''}'.startsWith(
                                      'https://elearning.fudan.edu.cn/',
                                    ))
                                      TextButton(
                                        onPressed: () => openPlainLink(
                                          context,
                                          '${j['url']}',
                                        ),
                                        child: Text(l10n.nasViewSource),
                                      ),
                                  ],
                                ),
                                if (nasRows(j['reports']).isEmpty)
                                  Text(l10n.nasNoReport),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  ListView(
                    padding: const EdgeInsets.all(20),
                    children: deadlines
                        .map(
                          (d) => Card(
                            child: ListTile(
                              leading: Icon(
                                d['completed'] == 'true'
                                    ? Icons.check_circle_outline
                                    : Icons.event_outlined,
                              ),
                              title: Text('${d['title']}'),
                              subtitle: Text(
                                '${dateLabel(d['due'])}\n${d['completed'] == 'true' ? l10n.nasDeadlineCompleted : l10n.nasUnconfirmed}',
                              ),
                              onTap:
                                  '${d['url'] ?? ''}'.startsWith(
                                    'https://elearning.fudan.edu.cn/',
                                  )
                                  ? () => openPlainLink(context, '${d['url']}')
                                  : null,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: shownFiles.length,
                    itemBuilder: (c, i) {
                      final f = shownFiles[i];
                      return ListTile(
                        leading: const Icon(Icons.insert_drive_file_outlined),
                        title: Text('${f['path']}'.split('/').last),
                        subtitle: Text(
                          '${f['path']}\n${f['modified']} · ${((f['size'] as num) / 1024).round()} KB',
                        ),
                        onTap: () => openFile(f),
                      );
                    },
                  ),
                  ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Text(l10n.nasServicesHint),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: acting || data?['online'] != true
                                ? null
                                : () => run('homework'),
                            icon: const Icon(Icons.play_arrow),
                            label: Text(l10n.nasRunHomework),
                          ),
                          OutlinedButton.icon(
                            onPressed: acting || data?['online'] != true
                                ? null
                                : () => run('calendar'),
                            icon: const Icon(Icons.event_repeat),
                            label: Text(l10n.nasRunCalendar),
                          ),
                        ],
                      ),
                      ...nasRows(data?['services']).map((s) {
                        final h = (s['health'] as Map?) ?? {};
                        return Card(
                          child: ListTile(
                            title: Text(serviceName('${s['id']}')),
                            subtitle: Text(
                              '${l10n.nasServiceState}: ${s['active']} · ${s['result'] ?? ''}\n${l10n.nasLastRun}: ${dateLabel(h['finished'])}\n${l10n.nasScanResult}: ${h['jobs'] ?? '—'} / ${h['failures'] ?? '—'}\n${l10n.nasNextRun}: ${s['next_run'] ?? '—'}',
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
