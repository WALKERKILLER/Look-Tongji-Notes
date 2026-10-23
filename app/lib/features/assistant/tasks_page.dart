import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../theme/tokens.dart';
import '../../widgets/states.dart';
import 'assistant_controller.dart';
import 'assistant_panel.dart';
import 'task_inbox.dart';
import '../../l10n/l10n.dart';

// Scheduled assistant tasks (docs/specs/0003-scheduled-agent-tasks.md).

/// Calls the agent host's task API; a seam for widget tests.
typedef TaskApi = Future<dynamic> Function(String method, String path, [Object? body]);

TaskApi _api(BuildContext context) {
  final api = context.read<AppState>().api;
  return (method, path, [body]) {
    final u = Uri.parse(path);
    return switch (method) {
      'GET' => api.get(u.path, u.queryParameters),
      'POST' => api.post(path, body),
      'PUT' => api.put(path, body ?? const {}),
      _ => api.delete(path),
    };
  };
}

/// Whether a weekly [s] runs Monday to Friday only.
bool isWorkdays(Map s) {
  final days = {for (final d in (s['days'] as List? ?? const [])) (d as num).toInt()};
  return s['type'] == 'weekly' && days.length == 5 && days.every((d) => d <= 5);
}

/// "每天 21:30", "工作日 08:00", "每周一、五 08:00", "10月15日 07:00".
String fmtSchedule(Map s) {
  switch (s['type']) {
    case 'daily':
      return l10n.scheduleDaily(s['time']);
    case 'weekly':
      final days = [for (final d in (s['days'] as List? ?? const [])) (d as num).toInt()];
      if (days.length == 7) return l10n.scheduleDaily(s['time']);
      if (isWorkdays(s)) return l10n.scheduleWorkdays(s['time']);
      return l10n.scheduleWeekly(days.map((d) => weekdayNames[d - 1]).join(l10n.listSeparator), s['time']);
    case 'once':
      final at = DateTime.tryParse('${s['at']}');
      return at == null ? l10n.scheduleOnce : l10n.scheduleOnceAt(at.month, at.day, _hm(at));
  }
  return '';
}

String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// "今天 21:30", "明天 08:00", "周五 08:00", "10月20日 08:00".
String fmtWhen(DateTime t, DateTime now) {
  final days = DateTime(t.year, t.month, t.day).difference(DateTime(now.year, now.month, now.day)).inDays;
  final day = switch (days) {
    0 => l10n.commonToday,
    1 => l10n.commonTomorrow,
    -1 => l10n.commonYesterday,
    > 1 && < 7 => l10n.weekdayName(weekdayNames[t.weekday - 1]),
    _ => l10n.dateMonthDay(t.month, t.day),
  };
  return '$day ${_hm(t)}';
}

/// Status label and icon of a run; colors come from the theme.
(String, IconData, bool) runStatus(String s) => switch (s) {
      'ok' => (l10n.commonFinished, Icons.check_circle_outline_rounded, false),
      'error' => (l10n.commonFailed, Icons.error_outline_rounded, true),
      'budget' => (l10n.runCostLimit, Icons.money_off_rounded, true),
      'aborted' => (l10n.runAborted, Icons.stop_circle_outlined, false),
      'skipped' => (l10n.runMissed, Icons.skip_next_outlined, false),
      _ => (s, Icons.circle_outlined, false),
    };

/// Opens the conversation of a run over the current screen.
Future<void> openRunConversation(BuildContext context, String sessionId) async {
  final a = context.read<AssistantController>();
  if (a.busy) {
    showSnack(context, l10n.tasksBusy);
    return;
  }
  await a.openSession(sessionId);
  if (context.mounted) await showAssistantSheet(context);
}

DateTime? _at(Object? ms) => ms is num ? DateTime.fromMillisecondsSinceEpoch(ms.toInt()) : null;

List<Map<String, dynamic>> _maps(Object? v) => [for (final x in (v as List? ?? const [])) (x as Map).cast<String, dynamic>()];

/// "今天", "昨天", "10月12日 周一" — day headers of the run history.
String _dayLabel(DateTime t, DateTime now) {
  final days = DateTime(now.year, now.month, now.day).difference(DateTime(t.year, t.month, t.day)).inDays;
  return switch (days) {
    0 => l10n.commonToday,
    1 => l10n.commonYesterday,
    _ => l10n.dateMonthDayWeek(t.month, t.day, weekdayNames[t.weekday - 1]),
  };
}

/// The 定时 tab: tasks beside the selected task's detail on wide windows,
/// a list with pushed detail pages otherwise, and runs of every task.
class TasksPage extends StatefulWidget {
  const TasksPage({super.key, this.api, this.now});
  final TaskApi? api;
  final DateTime Function()? now;
  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  List<Map<String, dynamic>>? _tasks;
  List<Map<String, dynamic>> _runs = [];
  Object? _error;
  int _view = 0; // 0 tasks, 1 run history
  String? _selected;
  String _filter = 'all';
  StreamSubscription? _sub;

  TaskApi get _call => widget.api ?? _api(context);

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.api == null) {
      _sub = context.read<AppState>().events.listen((e) {
        if (e['type'] == 'agent_task') _load();
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([_call('GET', '/agent/tasks'), _call('GET', '/agent/tasks/runs?limit=200')]);
      if (!mounted) return;
      setState(() {
        _tasks = _maps(r[0]);
        _runs = _maps(r[1]);
        _error = null;
        if (!_tasks!.any((t) => t['id'] == _selected)) _selected = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _edit([Map<String, dynamic>? template]) async {
    final saved = await showTaskEditor(context, template: template, api: _call);
    if (saved == null) return;
    setState(() {
      _view = 0;
      _selected = '${saved['id']}';
    });
    _load();
  }

  Future<void> _toggle(Map<String, dynamic> t, bool on) async {
    try {
      await _call('PUT', '/agent/tasks/${t['id']}', {'enabled': on});
      _load();
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    }
  }

  Future<void> _open(Map<String, dynamic> t) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => TaskDetailPage(taskId: '${t['id']}', api: widget.api, now: widget.now)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final now = (widget.now ?? DateTime.now)();
    final lastVisit = context.watch<TaskInbox?>()?.lastVisit ?? 0;
    return Scaffold(
      body: LayoutBuilder(builder: (context, box) {
        final compact = box.maxWidth < 600;
        final pad = compact ? Space.lg : Space.xl;
        final tasks = _tasks;
        final Widget body;
        if (tasks == null) {
          body = _error == null ? const CenteredLoader() : ErrorState(error: _error!, onRetry: _load);
        } else if (_view == 1) {
          body = _history(now, pad, lastVisit);
        } else if (tasks.isEmpty) {
          body = _TemplateGallery(pad: pad, onPick: (t) => _edit(t?.toJson()));
        } else if (box.maxWidth >= 880) {
          body = _split(tasks, now, pad, box.maxWidth);
        } else {
          body = RefreshIndicator(
            onRefresh: _load,
            child: ListView(padding: EdgeInsets.fromLTRB(pad, 0, pad, 120), children: [
              ContentWidth(
                max: 760,
                child: Column(children: [
                  for (final t in tasks)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.sm),
                      child: _TaskRow(task: t, now: now, onTap: () => _open(t), onToggle: (v) => _toggle(t, v)),
                    ),
                ]),
              ),
            ]),
          );
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _header(context, tasks, now, pad, compact),
          Expanded(child: body),
        ]);
      }),
    );
  }

  Widget _header(BuildContext context, List<Map<String, dynamic>>? tasks, DateTime now, double pad, bool compact) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    String sub = l10n.tasksSubtitle;
    if (tasks != null && tasks.isNotEmpty) {
      final on = tasks.where((t) => t['enabled'] == true).toList();
      final upcoming = on.where((t) => t['next_run'] is num).toList()..sort((a, b) => (a['next_run'] as num).compareTo(b['next_run'] as num));
      sub = [
        l10n.tasksCount(tasks.length),
        on.length == tasks.length ? l10n.commonAllEnabled : l10n.tasksEnabledCount(on.length),
        if (upcoming.isNotEmpty) l10n.tasksNextUp(upcoming.first['name'], fmtWhen(_at(upcoming.first['next_run'])!, now)),
      ].join(' · ');
    }
    final add = compact
        ? IconButton.filled(tooltip: l10n.tasksNew, onPressed: () => _edit(), icon: const Icon(Icons.add_rounded))
        : FilledButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.add_rounded), label: Text(l10n.tasksNew));
    return ContentWidth(
      max: kMaxContentWidth + 200,
      child: Padding(
        padding: EdgeInsets.fromLTRB(pad, compact ? Space.xl : Space.xxl, pad, Space.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l10n.commonScheduledTasks, style: compact ? tt.headlineMedium : tt.displaySmall),
          const SizedBox(height: Space.xs),
          Text(sub, style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: Space.lg),
          Row(children: [
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: 0, icon: const Icon(Icons.schedule_rounded), label: Text(tasks == null || tasks.isEmpty ? l10n.commonTasks : l10n.commonTasksCount(tasks.length))),
                ButtonSegment(value: 1, icon: Icon(Icons.history_rounded), label: Text(l10n.tasksRuns)),
              ],
              selected: {_view},
              onSelectionChanged: (v) => setState(() => _view = v.first),
            ),
            const Spacer(),
            add,
          ]),
        ]),
      ),
    );
  }

  Widget _split(List<Map<String, dynamic>> tasks, DateTime now, double pad, double width) {
    final cs = Theme.of(context).colorScheme;
    final sel = tasks.firstWhere((t) => t['id'] == _selected, orElse: () => tasks.first);
    return ContentWidth(
      max: kMaxContentWidth + 200,
      child: Padding(
        padding: EdgeInsets.fromLTRB(pad - Space.sm, 0, pad, pad),
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            width: width >= 1200 ? 380 : 320,
            child: ListView(padding: const EdgeInsets.only(bottom: Space.xl), children: [
              for (final t in tasks)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.xs),
                  child: _TaskRow(task: t, now: now, selected: t == sel, onTap: () => setState(() => _selected = '${t['id']}')),
                ),
            ]),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Material(
              color: cs.surfaceContainerLow,
              borderRadius: Corners.all(Corners.xl),
              clipBehavior: Clip.antiAlias,
              child: TaskDetailView(
                key: ValueKey(sel['id']),
                taskId: '${sel['id']}',
                api: widget.api,
                now: widget.now,
                embedded: true,
                onChanged: _load,
                onDeleted: () => setState(() => _selected = null),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _history(DateTime now, double pad, int lastVisit) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final runs = _runs.where((r) => switch (_filter) {
          'ok' => r['status'] == 'ok',
          'failed' => r['status'] == 'error' || r['status'] == 'budget',
          'skipped' => r['status'] == 'skipped',
          _ => true,
        });
    final days = <String, List<Map<String, dynamic>>>{};
    for (final r in runs) {
      days.putIfAbsent(_dayLabel(_at(r['started']) ?? now, now), () => []).add(r);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: EdgeInsets.fromLTRB(pad, 0, pad, 120), children: [
        ContentWidth(
          max: 840,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
              for (final (k, label) in [('all', l10n.commonAll), ('ok', l10n.commonFinished), ('failed', l10n.commonFailed), ('skipped', l10n.runMissed)])
                ChoiceChip(label: Text(label), selected: _filter == k, onSelected: (_) => setState(() => _filter = k)),
            ]),
            if (days.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.xxl),
                child: Text(_runs.isEmpty ? l10n.tasksRunsEmpty : l10n.tasksRunsNoMatch, textAlign: TextAlign.center, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
              ),
            for (final MapEntry(key: day, value: list) in days.entries) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.xs, Space.xl, 0, Space.sm),
                child: Text(day, style: tt.titleSmall?.copyWith(color: cs.onSurfaceVariant)),
              ),
              Material(
                color: cs.surfaceContainerLow,
                borderRadius: Corners.all(Corners.xl),
                clipBehavior: Clip.antiAlias,
                child: Column(children: [
                  for (final r in list) _RunTile(run: r, now: now, showTask: true, isNew: ((r['finished'] as num?) ?? 0) > lastVisit),
                ]),
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}

/// A tonal rounded tile whose icon hints at when the task runs.
class _TaskGlyph extends StatelessWidget {
  const _TaskGlyph({required this.task, this.size = 44});
  final Map<String, dynamic> task;
  final double size;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = task['schedule'] as Map? ?? const {};
    final hour = int.tryParse('${s['time'] ?? ''}'.split(':').first) ?? 12;
    final icon = switch (s['type']) {
      'once' => Icons.alarm_rounded,
      'weekly' when isWorkdays(s) => Icons.work_outline_rounded,
      'weekly' => Icons.date_range_rounded,
      _ when hour >= 18 || hour < 5 => Icons.nightlight_outlined,
      _ when hour < 11 => Icons.wb_sunny_outlined,
      _ => Icons.light_mode_outlined,
    };
    // A stable tone per task, so neighbours differ.
    final tone = '${task['id'] ?? task['name']}'.codeUnits.fold(0, (a, b) => a + b) % 3;
    final (bg, fg) = task['enabled'] == false
        ? (cs.surfaceContainerHighest, cs.onSurfaceVariant)
        : switch (tone) {
            0 => (cs.primaryContainer, cs.onPrimaryContainer),
            1 => (cs.secondaryContainer, cs.onSecondaryContainer),
            _ => (cs.tertiaryContainer, cs.onTertiaryContainer),
          };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(size * 0.32)),
      child: Icon(icon, size: size * 0.5, color: fg),
    );
  }
}

/// "运行中" / "排队中" / "已启用" / "已暂停" as a small pill.
class _StatePill extends StatelessWidget {
  const _StatePill({required this.task});
  final Map<String, dynamic> task;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final (label, bg, fg) = switch ('${task['state'] ?? 'idle'}') {
      'running' => (l10n.commonRunning, cs.primary, cs.onPrimary),
      'queued' => (l10n.commonQueued, cs.secondaryContainer, cs.onSecondaryContainer),
      _ when task['enabled'] != true => (l10n.commonPaused, cs.surfaceContainerHighest, cs.onSurfaceVariant),
      _ => (l10n.commonEnabled, cs.primaryContainer, cs.onPrimaryContainer),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.xxs),
      decoration: BoxDecoration(color: bg, borderRadius: Corners.all(Corners.full)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
        const SizedBox(width: Space.xs),
        Text(label, style: tt.labelMedium?.copyWith(color: fg)),
      ]),
    );
  }
}

/// A task in the list. With [onToggle] it is a card with a switch (narrow
/// windows); without, a selectable row beside the detail pane.
class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task, required this.now, required this.onTap, this.onToggle, this.selected = false});
  final Map<String, dynamic> task;
  final DateTime now;
  final VoidCallback onTap;
  final ValueChanged<bool>? onToggle;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final enabled = task['enabled'] == true;
    final next = _at(task['next_run']);
    final last = task['last_run'] as Map?;
    final state = '${task['state'] ?? 'idle'}';
    final line = switch (state) {
      'running' => l10n.tasksRunningNow,
      'queued' => l10n.commonQueued,
      _ => !enabled ? l10n.commonPaused : next == null ? l10n.tasksNoNextRun : l10n.tasksNextRun(fmtWhen(next, now)),
    };
    final card = onToggle != null;
    return Semantics(
      selected: selected,
      child: Material(
        color: selected ? cs.secondaryContainer : card ? cs.surfaceContainerLow : Colors.transparent,
        borderRadius: Corners.all(card ? Corners.xl : Corners.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.fromLTRB(Space.md, Space.md, card ? Space.sm : Space.md, Space.md),
            child: Row(children: [
              _TaskGlyph(task: task),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${task['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.titleMedium?.copyWith(color: enabled ? null : cs.onSurfaceVariant)),
                  const SizedBox(height: Space.xxs),
                  Text('${fmtSchedule(task['schedule'] as Map? ?? const {})} · $line',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                  if (last != null) ...[
                    const SizedBox(height: Space.xs),
                    _RunLine(run: last.cast<String, dynamic>(), now: now),
                  ],
                ]),
              ),
              if (state == 'running')
                const Padding(padding: EdgeInsets.all(Space.sm), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
              if (card) Switch(value: enabled, onChanged: onToggle),
            ]),
          ),
        ),
      ),
    );
  }
}

/// "完成 · 今天 21:31 · $0.012" with a status icon.
class _RunLine extends StatelessWidget {
  const _RunLine({required this.run, required this.now});
  final Map<String, dynamic> run;
  final DateTime now;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final (label, icon, bad) = runStatus('${run['status']}');
    final color = bad ? cs.error : cs.onSurfaceVariant;
    final cost = (run['cost'] as num?) ?? 0;
    return Row(children: [
      Icon(icon, size: 16, color: bad ? cs.error : (run['status'] == 'ok' ? cs.primary : color)),
      const SizedBox(width: Space.xs),
      Flexible(
        child: Text(
          [label, fmtWhen(_at(run['started'])!, now), if (cost > 0) fmtUsd(cost)].join(' · '),
          style: tt.labelMedium?.copyWith(color: color, fontFeatures: const [FontFeature.tabularFigures()]),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ]);
  }
}

/// One task on a narrow window, pushed over the list.
class TaskDetailPage extends StatelessWidget {
  const TaskDetailPage({super.key, required this.taskId, this.api, this.now});
  final String taskId;
  final TaskApi? api;
  final DateTime Function()? now;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(),
        body: TaskDetailView(taskId: taskId, api: api, now: now, onDeleted: () => Navigator.pop(context)),
      );
}

/// What a task does, its controls, and its run history.
class TaskDetailView extends StatefulWidget {
  const TaskDetailView({super.key, required this.taskId, this.api, this.now, this.embedded = false, this.onChanged, this.onDeleted});
  final String taskId;
  final TaskApi? api;
  final DateTime Function()? now;

  /// Shown in the pane beside the list rather than as its own page.
  final bool embedded;
  final VoidCallback? onChanged;
  final VoidCallback? onDeleted;
  @override
  State<TaskDetailView> createState() => _TaskDetailViewState();
}

class _TaskDetailViewState extends State<TaskDetailView> {
  Map<String, dynamic>? _task;
  List<Map<String, dynamic>> _runs = [];
  Object? _error;
  StreamSubscription? _sub;

  TaskApi get _call => widget.api ?? _api(context);

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.api == null) {
      _sub = context.read<AppState>().events.listen((e) {
        if (e['type'] == 'agent_task' && (e['data'] as Map?)?['task_id'] == widget.taskId) _load();
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final all = await _call('GET', '/agent/tasks') as List;
      final t = all.cast<Map>().firstWhere((x) => x['id'] == widget.taskId, orElse: () => const {});
      final runs = t.isEmpty ? const [] : await _call('GET', '/agent/tasks/${widget.taskId}/runs');
      if (!mounted) return;
      setState(() {
        _task = t.isEmpty ? null : t.cast<String, dynamic>();
        _runs = _maps(runs);
        _error = t.isEmpty ? l10n.tasksNotFound : null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// Runs [action], then refreshes this view and the list.
  Future<void> _act(Future<void> Function() action, [String? done]) async {
    try {
      await action();
      if (mounted && done != null) showSnack(context, done);
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    }
    await _load();
    widget.onChanged?.call();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l10n.tasksDeleteTitle),
        content: Text(l10n.tasksDeleteBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(l10n.commonCancel)),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(l10n.commonDelete)),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _call('DELETE', '/agent/tasks/${widget.taskId}');
      widget.onDeleted?.call();
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final t = _task;
    if (t == null) return _error == null ? const CenteredLoader() : ErrorState(error: _error!, onRetry: _load);
    final now = (widget.now ?? DateTime.now)();
    final enabled = t['enabled'] == true;
    final state = '${t['state'] ?? 'idle'}';
    final next = _at(t['next_run']);
    final last = _runs.isEmpty ? null : _runs.first;
    final tile = widget.embedded ? cs.surfaceContainer : cs.surfaceContainerLow;
    final pad = context.isCompact ? Space.lg : Space.xl;
    final writes = [for (final w in (t['writes'] as List? ?? const [])) kTaskWrites['$w']?.$1 ?? '$w'];
    return ListView(padding: EdgeInsets.fromLTRB(pad, widget.embedded ? Space.xl : Space.sm, pad, Space.xxxl), children: [
      ContentWidth(
        max: 760,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _TaskGlyph(task: t, size: 56),
            const SizedBox(width: Space.lg),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${t['name']}', style: tt.headlineSmall),
                const SizedBox(height: Space.xs),
                Wrap(spacing: Space.sm, runSpacing: Space.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  _StatePill(task: t),
                  Text(fmtSchedule(t['schedule'] as Map? ?? const {}), style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                ]),
              ]),
            ),
            Tooltip(
              message: enabled ? l10n.commonPause : l10n.commonEnable,
              child: Switch(value: enabled, onChanged: (v) => _act(() => _call('PUT', '/agent/tasks/${widget.taskId}', {'enabled': v}))),
            ),
          ]),
          const SizedBox(height: Space.lg),
          Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
            FilledButton.tonalIcon(
              onPressed: state == 'idle' ? () => _act(() => _call('POST', '/agent/tasks/${widget.taskId}/run'), l10n.tasksStarted) : null,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(state == 'running' ? l10n.tasksRunningNow : state == 'queued' ? l10n.commonQueued : l10n.tasksRunNow),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                if (await showTaskEditor(context, task: t, api: _call) != null) _act(() async {});
              },
              icon: const Icon(Icons.edit_outlined),
              label: Text(l10n.commonEdit),
            ),
            TextButton.icon(
              onPressed: _delete,
              style: TextButton.styleFrom(foregroundColor: cs.error),
              icon: const Icon(Icons.delete_outline_rounded),
              label: Text(l10n.commonDelete),
            ),
          ]),
          const SizedBox(height: Space.xl),
          Row(children: [
            Expanded(child: _Fact(color: tile, icon: Icons.update_rounded, label: l10n.tasksNextRunLabel, value: !enabled ? l10n.commonPaused : next == null ? l10n.commonNone : fmtWhen(next, now))),
            const SizedBox(width: Space.sm),
            Expanded(
              child: _Fact(
                color: tile,
                icon: Icons.history_rounded,
                label: l10n.tasksLastResult,
                value: last == null ? l10n.tasksNeverRun : runStatus('${last['status']}').$1,
                bad: last != null && runStatus('${last['status']}').$3,
              ),
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: _Fact(
                color: tile,
                icon: Icons.savings_outlined,
                label: t['catch_up'] == true ? l10n.tasksCostLimitCatchUp : l10n.tasksCostLimit,
                value: fmtUsd((t['budget_usd'] as num?) ?? 0.2),
              ),
            ),
          ]),
          const SizedBox(height: Space.md),
          Row(children: [
            Icon(writes.isEmpty ? Icons.lock_outline_rounded : Icons.edit_note_rounded, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Text(writes.isEmpty ? l10n.tasksReadOnly : l10n.tasksAllowed(writes.join(l10n.listSeparator)), style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
            ),
          ]),
          const SizedBox(height: Space.xl),
          Text(l10n.tasksPrompt, style: tt.titleSmall),
          const SizedBox(height: Space.sm),
          Container(
            padding: const EdgeInsets.all(Space.lg),
            decoration: BoxDecoration(color: tile, borderRadius: Corners.all(Corners.lg)),
            child: SelectableText('${t['prompt']}', style: tt.bodyMedium?.copyWith(height: 1.6)),
          ),
          const SizedBox(height: Space.xl),
          Row(children: [
            Text(l10n.tasksRuns, style: tt.titleSmall),
            const Spacer(),
            if (_runs.isNotEmpty) Text(l10n.tasksRecentRuns(_runs.length), style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
          ]),
          const SizedBox(height: Space.xs),
          if (_runs.isEmpty) Text(l10n.tasksNoRunsYet, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          for (final r in _runs) _RunTile(run: r, now: now),
        ]),
      ),
    ]);
  }
}

/// A labelled value on a tonal tile (下次运行, 上次结果, 上限).
class _Fact extends StatelessWidget {
  const _Fact({required this.color, required this.icon, required this.label, required this.value, this.bad = false});
  final Color color;
  final IconData icon;
  final String label, value;
  final bool bad;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(color: color, borderRadius: Corners.all(Corners.lg)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: Space.xs),
          Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant))),
        ]),
        const SizedBox(height: Space.xs),
        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.titleMedium?.copyWith(color: bad ? cs.error : null)),
      ]),
    );
  }
}

/// One run; with [showTask] it names the task (cross-task history).
class _RunTile extends StatelessWidget {
  const _RunTile({required this.run, required this.now, this.showTask = false, this.isNew = false});
  final Map<String, dynamic> run;
  final DateTime now;
  final bool showTask, isNew;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final status = '${run['status']}';
    final (label, icon, bad) = runStatus(status);
    final started = _at(run['started'])!;
    final secs = (((run['finished'] as num? ?? 0) - (run['started'] as num)) / 1000).round();
    final dur = secs < 60 ? l10n.durationSeconds(secs) : l10n.durationMinutesSeconds(secs ~/ 60, secs % 60);
    final cost = (run['cost'] as num?) ?? 0;
    final session = '${run['session_id'] ?? ''}';
    final summary = '${run['summary'] ?? ''}';
    final manual = run['manual'] == true ? l10n.tasksManualSuffix : '';
    final (bg, fg) = bad
        ? (cs.errorContainer, cs.onErrorContainer)
        : status == 'ok'
            ? (cs.primaryContainer, cs.onPrimaryContainer)
            : (cs.surfaceContainerHighest, cs.onSurfaceVariant);
    final String title, sub;
    if (showTask) {
      title = '${run['name'] ?? l10n.tasksDeletedTask}${run['deleted'] == true && run['name'] != null ? l10n.tasksDeletedSuffix : ''}';
      sub = '$label · ${_hm(started)}$manual${summary.isEmpty ? '' : '\n$summary'}';
    } else {
      title = '$label · ${fmtWhen(started, now)}$manual';
      sub = summary;
    }
    return ListTile(
      contentPadding: showTask ? const EdgeInsets.symmetric(horizontal: Space.lg) : EdgeInsets.zero,
      leading: CircleAvatar(radius: 18, backgroundColor: bg, child: Icon(icon, size: 20, color: fg)),
      title: Row(children: [
        Flexible(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)),
        if (isNew) ...[
          const SizedBox(width: Space.sm),
          Semantics(label: l10n.commonNewBadge, child: Container(width: 8, height: 8, decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle))),
        ],
      ]),
      subtitle: sub.isEmpty ? null : Text(sub, maxLines: showTask ? 3 : 2, overflow: TextOverflow.ellipsis),
      trailing: status == 'skipped'
          ? null
          : Text('$dur${cost > 0 ? '\n${fmtUsd(cost)}' : ''}',
              textAlign: TextAlign.end, style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant, fontFeatures: const [FontFeature.tabularFigures()])),
      onTap: session.isEmpty ? null : () => openRunConversation(context, session),
    );
  }
}

/// The empty 定时 tab: what tasks do, and templates to start from.
class _TemplateGallery extends StatelessWidget {
  const _TemplateGallery({required this.pad, required this.onPick});
  final double pad;
  final ValueChanged<TaskTemplate?> onPick;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return ListView(padding: EdgeInsets.fromLTRB(pad, Space.sm, pad, Space.xxxl), children: [
      ContentWidth(
        max: 900,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l10n.tasksIntroTitle, style: tt.titleLarge),
          const SizedBox(height: Space.xs),
          Text(l10n.tasksIntroBody,
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: Space.xl),
          LayoutBuilder(builder: (context, box) {
            final cols = box.maxWidth >= 720 ? 3 : box.maxWidth >= 460 ? 2 : 1;
            final w = (box.maxWidth - Space.md * (cols - 1)) / cols;
            return Wrap(spacing: Space.md, runSpacing: Space.md, children: [
              for (final t in kTaskTemplates) SizedBox(width: w, child: _TemplateCard(template: t, onTap: () => onPick(t))),
            ]);
          }),
          const SizedBox(height: Space.lg),
          OutlinedButton.icon(onPressed: () => onPick(null), icon: const Icon(Icons.edit_note_rounded), label: Text(l10n.tasksFromBlank)),
        ]),
      ),
    ]);
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({required this.template, required this.onTap});
  final TaskTemplate template;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: Corners.all(Corners.xl),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: cs.tertiaryContainer, borderRadius: BorderRadius.circular(13)),
              child: Icon(template.icon, size: 20, color: cs.onTertiaryContainer),
            ),
            const SizedBox(height: Space.md),
            Text(template.name, style: tt.titleMedium),
            const SizedBox(height: Space.xxs),
            Text(fmtSchedule(template.schedule), style: tt.labelLarge?.copyWith(color: cs.primary)),
            const SizedBox(height: Space.sm),
            Text(template.prompt, maxLines: 3, overflow: TextOverflow.ellipsis, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.5)),
          ]),
        ),
      ),
    );
  }
}

/// Ready-made tasks offered when the list is empty.
/// What a run may change (the agent's TASK_WRITES); other writes are refused.
final kTaskWrites = {
  'notes': (l10n.tasksWriteNotes, Icons.edit_note_rounded),
  'schedule': (l10n.tasksWriteSchedule, Icons.event_available_outlined),
  'quiz': (l10n.tasksWriteQuizzes, Icons.quiz_outlined),
};

class TaskTemplate {
  const TaskTemplate(this.name, this.icon, this.prompt, this.schedule, this.writes);
  final String name, prompt;
  final IconData icon;
  final Map<String, Object> schedule;
  final List<String> writes;
  Map<String, dynamic> toJson() => {'name': name, 'prompt': prompt, 'schedule': schedule, 'writes': writes};
}

final kTaskTemplates = [
  TaskTemplate(l10n.taskTemplateReviewName, Icons.nightlight_outlined,
      l10n.taskTemplateReviewPrompt, {'type': 'daily', 'time': '21:30'}, ['notes']),
  TaskTemplate(l10n.taskTemplateQuizName, Icons.quiz_outlined,
      l10n.taskTemplateQuizPrompt, {'type': 'weekly', 'days': [1], 'time': '08:00'}, ['quiz']),
  TaskTemplate(l10n.taskTemplateDeadlinesName, Icons.event_note_outlined,
      l10n.taskTemplateDeadlinesPrompt, {'type': 'daily', 'time': '08:00'}, []),
];

/// Creates or edits a task; returns the saved task.
Future<Map<String, dynamic>?> showTaskEditor(BuildContext context, {Map<String, dynamic>? task, Map<String, dynamic>? template, required TaskApi api}) {
  final editor = _TaskEditor(task: task, template: template, api: api);
  if (context.isCompact) {
    return showDialog(context: context, useRootNavigator: true, builder: (_) => Dialog.fullscreen(child: editor));
  }
  return showDialog(
    context: context,
    useRootNavigator: true,
    builder: (_) => Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560, maxHeight: 760), child: editor),
    ),
  );
}

class _TaskEditor extends StatefulWidget {
  const _TaskEditor({this.task, this.template, required this.api});
  final Map<String, dynamic>? task, template;
  final TaskApi api;
  @override
  State<_TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends State<_TaskEditor> {
  late final Map<String, dynamic> _src = widget.task ?? widget.template ?? const {};
  late final _name = TextEditingController(text: '${_src['name'] ?? ''}');
  late final _prompt = TextEditingController(text: '${_src['prompt'] ?? ''}');
  late final _budget = TextEditingController(text: '${_src['budget_usd'] ?? 0.2}');
  late String _type = _src['schedule'] is Map && isWorkdays(_src['schedule'] as Map) ? 'workdays' : '${(_src['schedule'] as Map?)?['type'] ?? 'daily'}';
  late TimeOfDay _time = _parseTime('${(_src['schedule'] as Map?)?['time'] ?? '21:30'}');
  late Set<int> _days = {for (final d in ((_src['schedule'] as Map?)?['days'] as List? ?? const [1])) (d as num).toInt()};
  late DateTime _once = DateTime.tryParse('${(_src['schedule'] as Map?)?['at'] ?? ''}') ?? DateTime.now().add(const Duration(hours: 1));
  late bool _catchUp = _src['catch_up'] != false;
  late final Set<String> _writes = {for (final w in (_src['writes'] as List? ?? const [])) '$w'};
  bool _saving = false;
  String? _error;

  static TimeOfDay _parseTime(String s) {
    final p = s.split(':');
    return TimeOfDay(hour: int.tryParse(p.first) ?? 21, minute: int.tryParse(p.length > 1 ? p[1] : '') ?? 30);
  }

  String get _hhmm => '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _name.dispose();
    _prompt.dispose();
    _budget.dispose();
    super.dispose();
  }

  Map<String, Object> get _schedule => switch (_type) {
        'weekly' => {'type': 'weekly', 'days': (_days.toList()..sort()), 'time': _hhmm},
        'workdays' => {'type': 'weekly', 'days': const [1, 2, 3, 4, 5], 'time': _hhmm},
        'once' => {'type': 'once', 'at': '${fmtIsoDay(_once)}T${_hm(_once)}'},
        _ => {'type': 'daily', 'time': _hhmm},
      };

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final body = {
      'name': _name.text.trim(),
      'prompt': _prompt.text.trim(),
      'schedule': _schedule,
      'budget_usd': double.tryParse(_budget.text.trim()) ?? -1,
      'catch_up': _catchUp,
      'writes': _writes.toList()..sort(),
    };
    try {
      final id = widget.task?['id'];
      final r = await (id == null ? widget.api('POST', '/agent/tasks', body) : widget.api('PUT', '/agent/tasks/$id', body));
      if (mounted) Navigator.pop(context, (r as Map).cast<String, dynamic>());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '$e';
      });
    }
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: _type == 'once' ? TimeOfDay.fromDateTime(_once) : _time);
    if (t == null) return;
    setState(() {
      if (_type == 'once') {
        _once = DateTime(_once.year, _once.month, _once.day, t.hour, t.minute);
      } else {
        _time = t;
      }
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(context: context, initialDate: _once.isBefore(now) ? now : _once, firstDate: DateTime(now.year, now.month, now.day), lastDate: now.add(const Duration(days: 365)));
    if (d != null) setState(() => _once = DateTime(d.year, d.month, d.day, _once.hour, _once.minute));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    Widget label(String t) => Padding(padding: const EdgeInsets.only(top: Space.lg, bottom: Space.sm), child: Text(t, style: tt.labelLarge?.copyWith(color: cs.onSurfaceVariant)));
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: l10n.commonCancel, onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
        title: Text(widget.task == null ? l10n.tasksNewTitle : l10n.tasksEditTitle),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: Space.md),
            child: FilledButton(onPressed: _saving ? null : _save, child: Text(l10n.commonSave)),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(Space.xl, Space.sm, Space.xl, Space.xxl), children: [
        if (widget.task == null && widget.template == null) ...[
          Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
            for (final t in kTaskTemplates)
              ActionChip(
                avatar: Icon(t.icon, size: 18),
                label: Text(t.name),
                onPressed: () => setState(() {
                  _name.text = t.name;
                  _prompt.text = t.prompt;
                  _type = '${t.schedule['type']}';
                  _time = _parseTime('${t.schedule['time']}');
                  if (t.schedule['days'] case final List d) _days = {for (final x in d) x as int};
                  _writes
                    ..clear()
                    ..addAll(t.writes);
                }),
              ),
          ]),
          const SizedBox(height: Space.lg),
        ],
        TextField(controller: _name, maxLength: 40, decoration: InputDecoration(labelText: l10n.commonName, border: OutlineInputBorder())),
        const SizedBox(height: Space.sm),
        TextField(
          controller: _prompt,
          minLines: 4,
          maxLines: 10,
          maxLength: 4000,
          decoration: InputDecoration(labelText: l10n.tasksPromptLabel, alignLabelWithHint: true, border: OutlineInputBorder()),
        ),
        label(l10n.commonTime),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: 'daily', label: Text(l10n.commonDaily)),
            ButtonSegment(value: 'workdays', label: Text(l10n.tasksWorkdays)),
            ButtonSegment(value: 'weekly', label: Text(l10n.commonWeekly)),
            ButtonSegment(value: 'once', label: Text(l10n.scheduleOnce)),
          ],
          selected: {_type},
          onSelectionChanged: (v) => setState(() => _type = v.first),
        ),
        const SizedBox(height: Space.md),
        if (_type == 'weekly') ...[
          Wrap(spacing: Space.xs, runSpacing: Space.xs, children: [
            for (var d = 1; d <= 7; d++)
              FilterChip(
                label: Text(l10n.weekdayName(weekdayNames[d - 1])),
                selected: _days.contains(d),
                onSelected: (on) => setState(() => on ? _days.add(d) : _days.remove(d)),
              ),
          ]),
          const SizedBox(height: Space.md),
        ],
        Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
          if (_type == 'once') OutlinedButton.icon(onPressed: _pickDate, icon: const Icon(Icons.calendar_today_outlined, size: 18), label: Text(l10n.dateMonthDay(_once.month, _once.day))),
          OutlinedButton.icon(onPressed: _pickTime, icon: const Icon(Icons.schedule_rounded, size: 18), label: Text(_type == 'once' ? _hm(_once) : _hhmm)),
        ]),
        label(l10n.tasksAllowLabel),
        Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
          for (final MapEntry(key: k, value: (name, icon)) in kTaskWrites.entries)
            FilterChip(
              avatar: Icon(icon, size: 18),
              label: Text(name),
              selected: _writes.contains(k),
              onSelected: (on) => setState(() => on ? _writes.add(k) : _writes.remove(k)),
            ),
        ]),
        Padding(
          padding: const EdgeInsets.only(top: Space.xs),
          child: Text(l10n.tasksAllowHint, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ),
        label(l10n.tasksLimits),
        TextField(
          controller: _budget,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: l10n.tasksCostLimitLabel, prefixText: r'$ ', helperText: l10n.tasksCostLimitHelper, border: OutlineInputBorder()),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _catchUp,
          onChanged: (v) => setState(() => _catchUp = v),
          title: Text(l10n.tasksCatchUp),
          subtitle: Text(l10n.tasksCatchUpHint),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: Space.sm), child: Text(_error!, style: tt.bodyMedium?.copyWith(color: cs.error))),
      ]),
    );
  }
}

/// Shows a snackbar when a scheduled run finishes, anywhere in the app.
class TaskRunListener extends StatefulWidget {
  const TaskRunListener({super.key, required this.messenger, required this.navigator, required this.child});
  final GlobalKey<ScaffoldMessengerState> messenger;
  final GlobalKey<NavigatorState> navigator;
  final Widget child;
  @override
  State<TaskRunListener> createState() => _TaskRunListenerState();
}

class _TaskRunListenerState extends State<TaskRunListener> {
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _sub = context.read<AppState>().events.listen((e) {
      if (e['type'] != 'agent_task') return;
      final d = (e['data'] as Map?) ?? const {};
      if (d['phase'] != 'finished' || d['status'] == 'skipped') return;
      final (label, _, bad) = runStatus('${d['status']}');
      final session = '${d['session_id'] ?? ''}';
      final why = bad && '${d['summary'] ?? ''}'.isNotEmpty ? l10n.tasksRunReason(d['summary']) : '';
      widget.messenger.currentState?.showSnackBar(SnackBar(
        persist: false,
        duration: const Duration(seconds: 6),
        content: Text(l10n.tasksRunNotice(d['name'], label, why), maxLines: 2, overflow: TextOverflow.ellipsis),
        action: session.isEmpty
            ? null
            : SnackBarAction(
                label: l10n.commonView,
                onPressed: () {
                  final c = widget.navigator.currentContext;
                  if (c != null) openRunConversation(c, session);
                },
              ),
      ));
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
