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

const _weekdayNames = ['一', '二', '三', '四', '五', '六', '日'];

/// "每天 21:30", "工作日 08:00", "每周一、五 08:00", "10月15日 07:00".
String fmtSchedule(Map s) {
  switch (s['type']) {
    case 'daily':
      return '每天 ${s['time']}';
    case 'weekly':
      final days = [for (final d in (s['days'] as List? ?? const [])) (d as num).toInt()];
      if (days.length == 7) return '每天 ${s['time']}';
      if (days.length == 5 && days.every((d) => d <= 5)) return '工作日 ${s['time']}';
      return '每周${days.map((d) => _weekdayNames[d - 1]).join('、')} ${s['time']}';
    case 'once':
      final at = DateTime.tryParse('${s['at']}');
      return at == null ? '一次' : '${at.month}月${at.day}日 ${_hm(at)}（一次）';
  }
  return '';
}

String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// "今天 21:30", "明天 08:00", "周五 08:00", "10月20日 08:00".
String fmtWhen(DateTime t, DateTime now) {
  final days = DateTime(t.year, t.month, t.day).difference(DateTime(now.year, now.month, now.day)).inDays;
  final day = switch (days) {
    0 => '今天',
    1 => '明天',
    -1 => '昨天',
    > 1 && < 7 => '周${_weekdayNames[t.weekday - 1]}',
    _ => '${t.month}月${t.day}日',
  };
  return '$day ${_hm(t)}';
}

/// Status label and icon of a run; colors come from the theme.
(String, IconData, bool) runStatus(String s) => switch (s) {
      'ok' => ('完成', Icons.check_circle_outline_rounded, false),
      'error' => ('失败', Icons.error_outline_rounded, true),
      'budget' => ('超出费用上限', Icons.money_off_rounded, true),
      'aborted' => ('已中止', Icons.stop_circle_outlined, false),
      'skipped' => ('已错过', Icons.skip_next_outlined, false),
      _ => (s, Icons.circle_outlined, false),
    };

/// Opens the conversation of a run over the current screen.
Future<void> openRunConversation(BuildContext context, String sessionId) async {
  final a = context.read<AssistantController>();
  if (a.busy) {
    showSnack(context, '助手正在回复，请稍后再查看');
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
    0 => '今天',
    1 => '昨天',
    _ => '${t.month}月${t.day}日 周${_weekdayNames[t.weekday - 1]}',
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
    String sub = '按计划在新对话里复盘、出题、汇总截止事项';
    if (tasks != null && tasks.isNotEmpty) {
      final on = tasks.where((t) => t['enabled'] == true).toList();
      final upcoming = on.where((t) => t['next_run'] is num).toList()..sort((a, b) => (a['next_run'] as num).compareTo(b['next_run'] as num));
      sub = [
        '${tasks.length} 个任务',
        on.length == tasks.length ? '全部启用' : '${on.length} 个启用',
        if (upcoming.isNotEmpty) '下一个「${upcoming.first['name']}」${fmtWhen(_at(upcoming.first['next_run'])!, now)}',
      ].join(' · ');
    }
    final add = compact
        ? IconButton.filled(tooltip: '新建任务', onPressed: () => _edit(), icon: const Icon(Icons.add_rounded))
        : FilledButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.add_rounded), label: const Text('新建任务'));
    return ContentWidth(
      max: kMaxContentWidth + 200,
      child: Padding(
        padding: EdgeInsets.fromLTRB(pad, compact ? Space.xl : Space.xxl, pad, Space.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('定时任务', style: compact ? tt.headlineMedium : tt.displaySmall),
          const SizedBox(height: Space.xs),
          Text(sub, style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: Space.lg),
          Row(children: [
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: 0, icon: const Icon(Icons.schedule_rounded), label: Text(tasks == null || tasks.isEmpty ? '任务' : '任务 ${tasks.length}')),
                const ButtonSegment(value: 1, icon: Icon(Icons.history_rounded), label: Text('运行记录')),
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
              for (final (k, label) in const [('all', '全部'), ('ok', '完成'), ('failed', '失败'), ('skipped', '已错过')])
                ChoiceChip(label: Text(label), selected: _filter == k, onSelected: (_) => setState(() => _filter = k)),
            ]),
            if (days.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.xxl),
                child: Text(_runs.isEmpty ? '任务运行后，结果会按时间出现在这里' : '没有符合条件的运行', textAlign: TextAlign.center, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
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
      'weekly' when fmtSchedule(s).startsWith('工作日') => Icons.work_outline_rounded,
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
      'running' => ('运行中', cs.primary, cs.onPrimary),
      'queued' => ('排队中', cs.secondaryContainer, cs.onSecondaryContainer),
      _ when task['enabled'] != true => ('已暂停', cs.surfaceContainerHighest, cs.onSurfaceVariant),
      _ => ('已启用', cs.primaryContainer, cs.onPrimaryContainer),
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
      'running' => '正在运行',
      'queued' => '排队中',
      _ => !enabled ? '已暂停' : next == null ? '没有下次运行' : '下次 ${fmtWhen(next, now)}',
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
        _error = t.isEmpty ? '任务不存在' : null;
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
        title: const Text('删除任务？'),
        content: const Text('以后不会再运行。已经生成的对话、笔记和练习会保留，运行记录仍可在“运行记录”里查看。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('删除')),
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
              message: enabled ? '暂停' : '启用',
              child: Switch(value: enabled, onChanged: (v) => _act(() => _call('PUT', '/agent/tasks/${widget.taskId}', {'enabled': v}))),
            ),
          ]),
          const SizedBox(height: Space.lg),
          Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
            FilledButton.tonalIcon(
              onPressed: state == 'idle' ? () => _act(() => _call('POST', '/agent/tasks/${widget.taskId}/run'), '已开始运行') : null,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(state == 'running' ? '正在运行' : state == 'queued' ? '排队中' : '立即运行'),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                if (await showTaskEditor(context, task: t, api: _call) != null) _act(() async {});
              },
              icon: const Icon(Icons.edit_outlined),
              label: const Text('编辑'),
            ),
            TextButton.icon(
              onPressed: _delete,
              style: TextButton.styleFrom(foregroundColor: cs.error),
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('删除'),
            ),
          ]),
          const SizedBox(height: Space.xl),
          Row(children: [
            Expanded(child: _Fact(color: tile, icon: Icons.update_rounded, label: '下次运行', value: !enabled ? '已暂停' : next == null ? '无' : fmtWhen(next, now))),
            const SizedBox(width: Space.sm),
            Expanded(
              child: _Fact(
                color: tile,
                icon: Icons.history_rounded,
                label: '上次结果',
                value: last == null ? '还没运行' : runStatus('${last['status']}').$1,
                bad: last != null && runStatus('${last['status']}').$3,
              ),
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: _Fact(
                color: tile,
                icon: Icons.savings_outlined,
                label: t['catch_up'] == true ? '单次上限 · 补跑' : '单次上限',
                value: fmtUsd((t['budget_usd'] as num?) ?? 0.2),
              ),
            ),
          ]),
          const SizedBox(height: Space.xl),
          Text('任务内容', style: tt.titleSmall),
          const SizedBox(height: Space.sm),
          Container(
            padding: const EdgeInsets.all(Space.lg),
            decoration: BoxDecoration(color: tile, borderRadius: Corners.all(Corners.lg)),
            child: SelectableText('${t['prompt']}', style: tt.bodyMedium?.copyWith(height: 1.6)),
          ),
          const SizedBox(height: Space.xl),
          Row(children: [
            Text('运行记录', style: tt.titleSmall),
            const Spacer(),
            if (_runs.isNotEmpty) Text('最近 ${_runs.length} 次', style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
          ]),
          const SizedBox(height: Space.xs),
          if (_runs.isEmpty) Text('还没有运行过。可以点“立即运行”先试一次。', style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
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
    final dur = secs < 60 ? '$secs 秒' : '${secs ~/ 60} 分 ${secs % 60} 秒';
    final cost = (run['cost'] as num?) ?? 0;
    final session = '${run['session_id'] ?? ''}';
    final summary = '${run['summary'] ?? ''}';
    final manual = run['manual'] == true ? ' · 手动' : '';
    final (bg, fg) = bad
        ? (cs.errorContainer, cs.onErrorContainer)
        : status == 'ok'
            ? (cs.primaryContainer, cs.onPrimaryContainer)
            : (cs.surfaceContainerHighest, cs.onSurfaceVariant);
    final String title, sub;
    if (showTask) {
      title = '${run['name'] ?? '已删除的任务'}${run['deleted'] == true && run['name'] != null ? '（已删除）' : ''}';
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
          Semantics(label: '新', child: Container(width: 8, height: 8, decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle))),
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
          Text('让助手按计划替你做事', style: tt.titleLarge),
          const SizedBox(height: Space.xs),
          Text('每次运行都会开一个新对话，结果可在“运行记录”里查看。任务只在 Look Studio 打开时执行；错过的时间可以在 12 小时内启动时补跑。',
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
          OutlinedButton.icon(onPressed: () => onPick(null), icon: const Icon(Icons.edit_note_rounded), label: const Text('从空白开始')),
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
class TaskTemplate {
  const TaskTemplate(this.name, this.icon, this.prompt, this.schedule);
  final String name, prompt;
  final IconData icon;
  final Map<String, Object> schedule;
  Map<String, dynamic> toJson() => {'name': name, 'prompt': prompt, 'schedule': schedule};
}

const kTaskTemplates = [
  TaskTemplate('每晚复盘今天的课', Icons.nightlight_outlined,
      '看看今天有哪些课的转写已经完成，为每节课写一份简明的复盘笔记并保存：核心概念、关键公式与例题、老师强调的要点，附时间戳。没有新课就简单说明。', {'type': 'daily', 'time': '21:30'}),
  TaskTemplate('每周一出一组复习题', Icons.quiz_outlined,
      '回顾上周转写过的课程，为每门课出一组 10 道中等难度的选择题并保存为练习，重点覆盖上周的新内容。', {'type': 'weekly', 'days': [1], 'time': '08:00'}),
  TaskTemplate('每天早上汇总近期截止', Icons.event_note_outlined,
      '列出今天起 7 天内的作业、考试和截止事项，按日期排序，提醒最紧急的两件；如果有已经过期但没完成的也指出来。', {'type': 'daily', 'time': '08:00'}),
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
  late String _type = _src['schedule'] is Map && fmtSchedule(_src['schedule'] as Map).startsWith('工作日') ? 'workdays' : '${(_src['schedule'] as Map?)?['type'] ?? 'daily'}';
  late TimeOfDay _time = _parseTime('${(_src['schedule'] as Map?)?['time'] ?? '21:30'}');
  late Set<int> _days = {for (final d in ((_src['schedule'] as Map?)?['days'] as List? ?? const [1])) (d as num).toInt()};
  late DateTime _once = DateTime.tryParse('${(_src['schedule'] as Map?)?['at'] ?? ''}') ?? DateTime.now().add(const Duration(hours: 1));
  late bool _catchUp = _src['catch_up'] != false;
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
        leading: IconButton(tooltip: '取消', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
        title: Text(widget.task == null ? '新建定时任务' : '编辑定时任务'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: Space.md),
            child: FilledButton(onPressed: _saving ? null : _save, child: const Text('保存')),
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
                }),
              ),
          ]),
          const SizedBox(height: Space.lg),
        ],
        TextField(controller: _name, maxLength: 40, decoration: const InputDecoration(labelText: '名称', border: OutlineInputBorder())),
        const SizedBox(height: Space.sm),
        TextField(
          controller: _prompt,
          minLines: 4,
          maxLines: 10,
          maxLength: 4000,
          decoration: const InputDecoration(labelText: '让助手做什么', alignLabelWithHint: true, border: OutlineInputBorder()),
        ),
        label('时间'),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 'daily', label: Text('每天')),
            ButtonSegment(value: 'workdays', label: Text('工作日')),
            ButtonSegment(value: 'weekly', label: Text('每周')),
            ButtonSegment(value: 'once', label: Text('一次')),
          ],
          selected: {_type},
          onSelectionChanged: (v) => setState(() => _type = v.first),
        ),
        const SizedBox(height: Space.md),
        if (_type == 'weekly') ...[
          Wrap(spacing: Space.xs, runSpacing: Space.xs, children: [
            for (var d = 1; d <= 7; d++)
              FilterChip(
                label: Text('周${_weekdayNames[d - 1]}'),
                selected: _days.contains(d),
                onSelected: (on) => setState(() => on ? _days.add(d) : _days.remove(d)),
              ),
          ]),
          const SizedBox(height: Space.md),
        ],
        Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
          if (_type == 'once') OutlinedButton.icon(onPressed: _pickDate, icon: const Icon(Icons.calendar_today_outlined, size: 18), label: Text('${_once.month}月${_once.day}日')),
          OutlinedButton.icon(onPressed: _pickTime, icon: const Icon(Icons.schedule_rounded, size: 18), label: Text(_type == 'once' ? _hm(_once) : _hhmm)),
        ]),
        label('限制'),
        TextField(
          controller: _budget,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: '单次费用上限', prefixText: r'$ ', helperText: '超过后中止这次运行（按模型价格估算）', border: OutlineInputBorder()),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _catchUp,
          onChanged: (v) => setState(() => _catchUp = v),
          title: const Text('错过时补跑'),
          subtitle: const Text('应用在计划时间未运行时，12 小时内启动会补跑一次'),
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
      final why = bad && '${d['summary'] ?? ''}'.isNotEmpty ? '：${d['summary']}' : '';
      widget.messenger.currentState?.showSnackBar(SnackBar(
        persist: false,
        duration: const Duration(seconds: 6),
        content: Text('定时任务「${d['name']}」$label$why', maxLines: 2, overflow: TextOverflow.ellipsis),
        action: session.isEmpty
            ? null
            : SnackBarAction(
                label: '查看',
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
