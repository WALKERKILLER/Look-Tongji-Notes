import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../theme/tokens.dart';
import '../../widgets/states.dart';
import 'assistant_controller.dart';
import 'assistant_panel.dart';

// Scheduled assistant tasks (docs/specs/0003-scheduled-agent-tasks.md).

/// Calls the agent host's task API; a seam for widget tests.
typedef TaskApi = Future<dynamic> Function(String method, String path, [Object? body]);

TaskApi _api(BuildContext context) {
  final api = context.read<AppState>().api;
  return (method, path, [body]) => switch (method) {
        'GET' => api.get(path),
        'POST' => api.post(path, body),
        'PUT' => api.put(path, body ?? const {}),
        _ => api.delete(path),
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

class TasksPage extends StatefulWidget {
  const TasksPage({super.key, this.api, this.now});
  final TaskApi? api;
  final DateTime Function()? now;
  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  List<Map<String, dynamic>>? _tasks;
  Object? _error;
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
      final r = await _call('GET', '/agent/tasks');
      if (!mounted) return;
      setState(() {
        _tasks = [for (final t in r as List) (t as Map).cast<String, dynamic>()];
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _edit([Map<String, dynamic>? task, Map<String, dynamic>? template]) async {
    final saved = await showTaskEditor(context, task: task, template: template, api: _call);
    if (saved != null) _load();
  }

  Future<void> _toggle(Map<String, dynamic> t, bool on) async {
    try {
      await _call('PUT', '/agent/tasks/${t['id']}', {'enabled': on});
      _load();
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final tasks = _tasks;
    final now = (widget.now ?? DateTime.now)();
    Widget body;
    if (tasks == null) {
      body = _error == null ? const CenteredLoader() : ErrorState(error: _error!, onRetry: _load);
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(0, Space.sm, 0, 120), children: [
          ContentWidth(
            max: 760,
            child: Padding(
              padding: context.isCompact ? Space.pageCompact : Space.page,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('助手按计划在新对话里完成任务，只在 Look Studio 运行时执行；错过的时间可以在下次启动时补跑。',
                    style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: Space.lg),
                if (tasks.isEmpty) ...[
                  Text('从模板开始', style: tt.titleSmall),
                  const SizedBox(height: Space.sm),
                  Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
                    for (final t in kTaskTemplates) ActionChip(avatar: Icon(t.icon, size: 18), label: Text(t.name), onPressed: () => _edit(null, t.toJson())),
                  ]),
                ],
                for (final t in tasks)
                  Padding(padding: const EdgeInsets.only(bottom: Space.sm), child: _TaskTile(task: t, now: now, onToggle: (v) => _toggle(t, v), onOpen: () => _open(t))),
              ]),
            ),
          ),
        ]),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('定时任务')),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _edit(), icon: const Icon(Icons.add_rounded), label: const Text('新建任务')),
      body: body,
    );
  }

  Future<void> _open(Map<String, dynamic> t) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => TaskDetailPage(taskId: '${t['id']}', api: widget.api, now: widget.now)));
    _load();
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task, required this.now, required this.onToggle, required this.onOpen});
  final Map<String, dynamic> task;
  final DateTime now;
  final ValueChanged<bool> onToggle;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final enabled = task['enabled'] == true;
    final next = task['next_run'] is num ? DateTime.fromMillisecondsSinceEpoch((task['next_run'] as num).toInt()) : null;
    final last = task['last_run'] as Map?;
    final state = '${task['state'] ?? 'idle'}';
    final line = switch (state) {
      'running' => '正在运行',
      'queued' => '排队中',
      _ => !enabled ? '已停用' : next == null ? '没有下次运行' : '下次 ${fmtWhen(next, now)}',
    };
    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: Corners.all(Corners.xl),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.md, Space.md),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${task['name']}', style: tt.titleMedium?.copyWith(color: enabled ? null : cs.onSurfaceVariant)),
                const SizedBox(height: 2),
                Text('${fmtSchedule(task['schedule'] as Map? ?? const {})} · $line', style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                if (last != null) ...[
                  const SizedBox(height: Space.xs),
                  _RunLine(run: last.cast<String, dynamic>(), now: now),
                ],
              ]),
            ),
            if (state == 'running') const Padding(padding: EdgeInsets.all(Space.md), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
            Switch(value: enabled, onChanged: onToggle),
          ]),
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
          [label, fmtWhen(DateTime.fromMillisecondsSinceEpoch((run['started'] as num).toInt()), now), if (cost > 0) fmtUsd(cost)].join(' · '),
          style: tt.labelMedium?.copyWith(color: color, fontFeatures: const [FontFeature.tabularFigures()]),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ]);
  }
}

/// One task: what it does, actions, and its run history.
class TaskDetailPage extends StatefulWidget {
  const TaskDetailPage({super.key, required this.taskId, this.api, this.now});
  final String taskId;
  final TaskApi? api;
  final DateTime Function()? now;
  @override
  State<TaskDetailPage> createState() => _TaskDetailPageState();
}

class _TaskDetailPageState extends State<TaskDetailPage> {
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
      final runs = await _call('GET', '/agent/tasks/${widget.taskId}/runs') as List;
      if (!mounted) return;
      setState(() {
        _task = t.isEmpty ? null : t.cast<String, dynamic>();
        _runs = [for (final r in runs) (r as Map).cast<String, dynamic>()];
        _error = t.isEmpty ? '任务不存在' : null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _run() async {
    try {
      await _call('POST', '/agent/tasks/${widget.taskId}/run');
      if (mounted) showSnack(context, '已开始运行');
      _load();
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('删除任务？'),
        content: const Text('以后不会再运行。已经生成的对话、笔记和练习会保留。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _call('DELETE', '/agent/tasks/${widget.taskId}');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final t = _task;
    final now = (widget.now ?? DateTime.now)();
    return Scaffold(
      appBar: AppBar(title: Text(t == null ? '定时任务' : '${t['name']}'), actions: [
        if (t != null) ...[
          IconButton(tooltip: '编辑', onPressed: () async {
            if (await showTaskEditor(context, task: t, api: _call) != null) _load();
          }, icon: const Icon(Icons.edit_outlined)),
          IconButton(tooltip: '删除', onPressed: _delete, icon: const Icon(Icons.delete_outline_rounded)),
        ],
      ]),
      body: t == null
          ? (_error == null ? const CenteredLoader() : ErrorState(error: _error!, onRetry: _load))
          : ListView(padding: const EdgeInsets.fromLTRB(0, Space.sm, 0, Space.xxxl), children: [
              ContentWidth(
                max: 760,
                child: Padding(
                  padding: context.isCompact ? Space.pageCompact : Space.page,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(fmtSchedule(t['schedule'] as Map? ?? const {}), style: tt.titleMedium),
                    Text(
                      [
                        '单次上限 ${fmtUsd((t['budget_usd'] as num?) ?? 0.2)}',
                        t['catch_up'] == true ? '错过时补跑' : '错过不补跑',
                        if (t['next_run'] is num) '下次 ${fmtWhen(DateTime.fromMillisecondsSinceEpoch((t['next_run'] as num).toInt()), now)}',
                      ].join(' · '),
                      style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: Space.lg),
                    Container(
                      padding: const EdgeInsets.all(Space.lg),
                      decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: Corners.all(Corners.lg)),
                      child: SelectableText('${t['prompt']}', style: tt.bodyMedium?.copyWith(height: 1.6)),
                    ),
                    const SizedBox(height: Space.lg),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.tonalIcon(
                        onPressed: t['state'] == 'idle' ? _run : null,
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text(t['state'] == 'running' ? '正在运行' : t['state'] == 'queued' ? '排队中' : '立即运行'),
                      ),
                    ),
                    const SizedBox(height: Space.xl),
                    Text('运行记录', style: tt.titleSmall),
                    const SizedBox(height: Space.xs),
                    if (_runs.isEmpty) Text('还没有运行过', style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                    for (final r in _runs) _RunTile(run: r, now: now),
                  ]),
                ),
              ),
            ]),
    );
  }
}

class _RunTile extends StatelessWidget {
  const _RunTile({required this.run, required this.now});
  final Map<String, dynamic> run;
  final DateTime now;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final (label, icon, bad) = runStatus('${run['status']}');
    final started = DateTime.fromMillisecondsSinceEpoch((run['started'] as num).toInt());
    final secs = (((run['finished'] as num? ?? 0) - (run['started'] as num)) / 1000).round();
    final dur = secs < 60 ? '$secs 秒' : '${secs ~/ 60} 分 ${secs % 60} 秒';
    final cost = (run['cost'] as num?) ?? 0;
    final session = '${run['session_id'] ?? ''}';
    final summary = '${run['summary'] ?? ''}';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: bad ? cs.error : (run['status'] == 'ok' ? cs.primary : cs.onSurfaceVariant)),
      title: Text('$label · ${fmtWhen(started, now)}${run['manual'] == true ? ' · 手动' : ''}'),
      subtitle: summary.isEmpty ? null : Text(summary, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: run['status'] == 'skipped'
          ? null
          : Text('$dur${cost > 0 ? '\n${fmtUsd(cost)}' : ''}',
              textAlign: TextAlign.end, style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant, fontFeatures: const [FontFeature.tabularFigures()])),
      onTap: session.isEmpty ? null : () => openRunConversation(context, session),
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
  late String _type = '${(_src['schedule'] as Map?)?['type'] ?? 'daily'}';
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
          segments: const [ButtonSegment(value: 'daily', label: Text('每天')), ButtonSegment(value: 'weekly', label: Text('每周')), ButtonSegment(value: 'once', label: Text('一次'))],
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
