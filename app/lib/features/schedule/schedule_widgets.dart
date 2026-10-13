import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../shell.dart';
import '../../theme/tokens.dart';
import '../../widgets/states.dart';
import '../player/player_page.dart';
import 'schedule_store.dart';

/// Visual identity of a schedule kind, built from color-scheme roles.
class KindStyle {
  const KindStyle(this.label, this.icon, this.container, this.onContainer, this.accent);
  final String label;
  final IconData icon;
  final Color container, onContainer, accent;

  static const kinds = ['homework', 'exam', 'activity', 'deadline', 'task'];

  static KindStyle of(BuildContext context, String kind) {
    final cs = Theme.of(context).colorScheme;
    return switch (kind) {
      'homework' => KindStyle('作业', Icons.edit_note_rounded, cs.primaryContainer, cs.onPrimaryContainer, cs.primary),
      'exam' => KindStyle('考试', Icons.quiz_outlined, cs.tertiaryContainer, cs.onTertiaryContainer, cs.tertiary),
      'activity' => KindStyle('活动', Icons.groups_2_outlined, cs.secondaryContainer, cs.onSecondaryContainer, cs.secondary),
      'deadline' => KindStyle('截止', Icons.flag_outlined, cs.errorContainer, cs.onErrorContainer, cs.error),
      _ => KindStyle('待办', Icons.task_alt_rounded, cs.surfaceContainerHighest, cs.onSurfaceVariant, cs.outline),
    };
  }
}

String fmtDue(ScheduleItem it) {
  final d = it.day;
  final today = dayOf(DateTime.now());
  final diff = d.difference(today).inDays;
  final rel = switch (diff) { 0 => '今天', 1 => '明天', 2 => '后天', -1 => '昨天', _ => '${d.month}月${d.day}日' };
  final wd = '周${weekdayNames[d.weekday - 1]}';
  return [rel, if (diff.abs() > 1) wd, if (it.dueTime.isNotEmpty) it.dueTime].join(' ');
}

String fmtCountdown(ScheduleItem it) {
  final diff = it.day.difference(dayOf(DateTime.now())).inDays;
  if (it.done) return '已完成';
  if (diff < 0) return '逾期 ${-diff} 天';
  if (diff == 0) return '今天';
  return '还有 $diff 天';
}

/// A calendar leaf: month on a tinted band, the day large below.
class DateLeaf extends StatelessWidget {
  const DateLeaf({super.key, required this.date, required this.style, this.size = 52, this.muted = false});
  final DateTime date;
  final KindStyle style;
  final double size;
  final bool muted;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return SizedBox(
      width: size,
      height: size * 1.12,
      child: DecoratedBox(
        decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(Corners.md)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Corners.md),
          child: Column(children: [
            Container(
              height: size * 0.32,
              width: double.infinity,
              color: muted ? cs.surfaceContainerHigh : style.container,
              alignment: Alignment.center,
              child: Text('${date.month}月', style: tt.labelSmall?.copyWith(color: muted ? cs.onSurfaceVariant : style.onContainer, height: 1)),
            ),
            Expanded(
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('${date.day}',
                      style: tt.titleLarge?.copyWith(height: 1, fontWeight: FontWeight.w600, color: muted ? cs.onSurfaceVariant : cs.onSurface)),
                  Text('周${weekdayNames[date.weekday - 1]}', style: tt.labelSmall?.copyWith(fontSize: 10, height: 1.3, color: cs.onSurfaceVariant)),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Small tonal label with the kind's icon.
class KindLabel extends StatelessWidget {
  const KindLabel({super.key, required this.style});
  final KindStyle style;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(6, 2, 8, 2),
        decoration: BoxDecoration(color: style.container, borderRadius: BorderRadius.circular(Corners.full)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(style.icon, size: 13, color: style.onContainer),
          const SizedBox(width: 3),
          Text(style.label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: style.onContainer)),
        ]),
      );
}

/// Round check that fills with a short spring when toggled.
class DoneCheck extends StatelessWidget {
  const DoneCheck({super.key, required this.done, required this.color, required this.onChanged});
  final bool done;
  final Color color;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      checked: done,
      button: true,
      child: InkResponse(
        radius: 22,
        onTap: () => onChanged(!done),
        child: SizedBox.square(
          dimension: 40,
          child: Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: done ? 1 : 0),
              duration: Motion.medium2,
              curve: Curves.easeOutBack,
              builder: (_, t, _) => Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color.lerp(Colors.transparent, color, t.clamp(0, 1)),
                  border: Border.all(color: Color.lerp(cs.outline, color, t.clamp(0, 1))!, width: 2),
                ),
                child: Transform.scale(scale: t.clamp(0, 1.2), child: Icon(Icons.check_rounded, size: 15, color: cs.surface)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Jumps to where an item was mentioned in its lecture.
void openMention(BuildContext context, ScheduleItem it) {
  if (it.lectureId.isEmpty) return;
  seekOrOpen(context, it.lectureId, (it.tMs < 0 ? 0 : it.tMs) ~/ 1000);
}

/// One agenda row.
class ScheduleTile extends StatelessWidget {
  const ScheduleTile({super.key, required this.item, this.showDate = false});
  final ScheduleItem item;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final st = KindStyle.of(context, item.kind);
    final store = context.read<ScheduleStore>();
    final meta = [
      if (showDate) fmtDue(item) else if (item.dueTime.isNotEmpty) item.dueTime,
      if (item.courseTitle.isNotEmpty) item.courseTitle,
    ];
    return AnimatedOpacity(
      duration: Motion.medium2,
      opacity: item.done ? 0.6 : 1,
      child: Material(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(Corners.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showScheduleEditor(context, item: item),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.xs, Space.sm, Space.xs, Space.sm),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              DoneCheck(
                done: item.done,
                color: st.accent,
                onChanged: (v) => store.patch(item, {'done': v}).catchError((e) {
                  if (context.mounted) showSnack(context, '更新失败：$e');
                }),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: Space.sm),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(item.title,
                        style: tt.titleSmall?.copyWith(
                          decoration: item.done ? TextDecoration.lineThrough : null,
                          decorationColor: cs.onSurfaceVariant,
                        )),
                    const SizedBox(height: Space.xs),
                    Wrap(spacing: Space.sm, runSpacing: Space.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      KindLabel(style: st),
                      if (meta.isNotEmpty) Text(meta.join(' · '), style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      if (item.overdue) Text(fmtCountdown(item), style: tt.labelSmall?.copyWith(color: cs.error)),
                    ]),
                    if (item.quote.isNotEmpty) ...[
                      const SizedBox(height: Space.sm),
                      _Mention(item: item),
                    ],
                  ]),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: '更多',
                icon: Icon(Icons.more_vert_rounded, color: cs.onSurfaceVariant),
                onSelected: (v) async {
                  if (v == 'edit') showScheduleEditor(context, item: item);
                  if (v == 'delete') {
                    await store.remove(item);
                    if (context.mounted) {
                      showSnack(context, '已删除「${item.title}」', action: '撤销', onAction: () => store.restore(item));
                    }
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('编辑'), contentPadding: EdgeInsets.zero)),
                  PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline_rounded), title: Text('删除'), contentPadding: EdgeInsets.zero)),
                ],
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The words that mentioned the item, with a jump to the recording.
class _Mention extends StatelessWidget {
  const _Mention({required this.item});
  final ScheduleItem item;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(top: 2, right: Space.sm),
        child: Icon(item.source == 'agent' ? Icons.auto_awesome_outlined : Icons.format_quote_rounded, size: 14, color: cs.onSurfaceVariant),
      ),
      Expanded(
        child: Text('“${item.quote}”', maxLines: 2, overflow: TextOverflow.ellipsis, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.45)),
      ),
      if (item.lectureId.isNotEmpty && item.tMs >= 0)
        Padding(
          padding: const EdgeInsets.only(left: Space.sm),
          child: ActionChip(
            visualDensity: VisualDensity.compact,
            avatar: const Icon(Icons.play_arrow_rounded, size: 16),
            label: Text(fmtClock(item.tMs), style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
            tooltip: '跳到老师提到的地方',
            onPressed: () => openMention(context, item),
          ),
        ),
    ]);
  }
}

/// Create or edit an item. Returns when the sheet closes.
Future<void> showScheduleEditor(BuildContext context, {ScheduleItem? item, DateTime? day}) {
  final wide = !context.isCompact;
  final editor = _Editor(item: item, day: day);
  if (wide) {
    return showDialog(
      context: context,
      useRootNavigator: true,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Corners.xl)),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: editor),
      ),
    );
  }
  return showModalBottomSheet(context: context, useRootNavigator: true, isScrollControlled: true, showDragHandle: true, builder: (_) => editor);
}

class _Editor extends StatefulWidget {
  const _Editor({this.item, this.day});
  final ScheduleItem? item;
  final DateTime? day;
  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  late final _title = TextEditingController(text: widget.item?.title ?? '');
  late final _detail = TextEditingController(text: widget.item?.detail ?? '');
  late String _kind = widget.item?.kind ?? 'homework';
  late DateTime _date = widget.item?.day ?? widget.day ?? dayOf(DateTime.now()).add(const Duration(days: 7));
  late String _time = widget.item?.dueTime ?? '';
  late String _course = widget.item?.courseId ?? '';
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _detail.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) return;
    setState(() => _busy = true);
    final store = context.read<ScheduleStore>();
    final fields = {
      'title': _title.text.trim(),
      'kind': _kind,
      'detail': _detail.text.trim(),
      'due_date': isoDate(_date),
      'due_time': _time,
      'course_id': _course,
    };
    try {
      if (widget.item == null) {
        await store.add(fields);
      } else {
        await store.patch(widget.item!, fields);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showSnack(context, '保存失败：$e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final courses = context.read<AppState>().courses.where((c) => !c.hidden).toList();
    final it = widget.item;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(Space.xl, context.isCompact ? 0 : Space.xl, Space.xl, Space.xl + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Text(it == null ? '新建日程' : '编辑日程', style: tt.headlineSmall),
        const SizedBox(height: Space.lg),
        TextField(
          controller: _title,
          autofocus: it == null,
          maxLength: 80,
          decoration: const InputDecoration(labelText: '标题', hintText: '例如：实验二报告', border: OutlineInputBorder()),
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: Space.sm),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              for (final k in KindStyle.kinds)
                ButtonSegment(value: k, icon: Icon(KindStyle.of(context, k).icon, size: 18), label: Text(KindStyle.of(context, k).label)),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() => _kind = s.first),
          ),
        ),
        const SizedBox(height: Space.lg),
        Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
          InputChip(
            avatar: const Icon(Icons.event_rounded, size: 18),
            label: Text('${_date.year}年${_date.month}月${_date.day}日 周${weekdayNames[_date.weekday - 1]}'),
            onPressed: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
                helpText: '截止日期',
              );
              if (d != null) setState(() => _date = d);
            },
          ),
          InputChip(
            avatar: const Icon(Icons.schedule_rounded, size: 18),
            label: Text(_time.isEmpty ? '全天' : _time),
            onDeleted: _time.isEmpty ? null : () => setState(() => _time = ''),
            onPressed: () async {
              final parts = _time.split(':');
              final t = await showTimePicker(
                context: context,
                initialTime: _time.isEmpty ? const TimeOfDay(hour: 23, minute: 59) : TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
              );
              if (t != null) setState(() => _time = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
            },
          ),
        ]),
        const SizedBox(height: Space.lg),
        DropdownMenu<String>(
          initialSelection: _course,
          expandedInsets: EdgeInsets.zero,
          label: const Text('课程'),
          leadingIcon: const Icon(Icons.school_outlined),
          onSelected: (v) => setState(() => _course = v ?? ''),
          dropdownMenuEntries: [
            const DropdownMenuEntry(value: '', label: '不关联课程'),
            for (final c in courses) DropdownMenuEntry(value: c.id, label: c.title),
          ],
        ),
        const SizedBox(height: Space.lg),
        TextField(
          controller: _detail,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(labelText: '备注', hintText: '要求、提交方式…', border: OutlineInputBorder()),
        ),
        if (it != null && it.quote.isNotEmpty) ...[
          const SizedBox(height: Space.lg),
          Container(
            padding: const EdgeInsets.all(Space.md),
            decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(Corners.md)),
            child: _Mention(item: it),
          ),
        ],
        const SizedBox(height: Space.xl),
        Row(children: [
          const Spacer(),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          const SizedBox(width: Space.sm),
          FilledButton(onPressed: _busy ? null : _save, child: Text(it == null ? '添加' : '保存')),
        ]),
      ]),
    );
  }
}

/// What the assistant shows after mark_schedule: the item as a calendar leaf
/// with its source, and undo / done / open in schedule.
class ScheduleChatCard extends StatelessWidget {
  const ScheduleChatCard({super.key, required this.data, this.duplicate = false});
  final Map<String, dynamic> data;
  final bool duplicate;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final store = context.watch<ScheduleStore>();
    final live = store.byId('${data['id']}');
    final it = live ?? ScheduleItem(data);
    final removed = live == null && store.loaded;
    final st = KindStyle.of(context, it.kind);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Motion.long2,
      curve: Motion.emphasizedDecelerate,
      builder: (_, t, child) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 8 * (1 - t)), child: child)),
      child: AnimatedContainer(
        duration: Motion.medium2,
        margin: const EdgeInsets.symmetric(vertical: Space.xs),
        padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.sm, Space.xs),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(Corners.xl),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            DateLeaf(date: it.day, style: st, muted: removed),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  it.title,
                  style: tt.titleSmall?.copyWith(decoration: removed || it.done ? TextDecoration.lineThrough : null, color: removed ? cs.onSurfaceVariant : null),
                ),
                const SizedBox(height: Space.xs),
                Wrap(spacing: Space.sm, runSpacing: Space.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  KindLabel(style: st),
                  Text(
                    removed ? '已撤销' : duplicate ? '日程里已有' : [fmtDue(it), fmtCountdown(it)].join(' · '),
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ]),
                if (it.quote.isNotEmpty) ...[
                  const SizedBox(height: Space.sm),
                  _Mention(item: it),
                ],
              ]),
            ),
          ]),
          Row(children: [
            const Spacer(),
            if (removed)
              TextButton.icon(
                onPressed: () => store.restore(it),
                icon: const Icon(Icons.undo_rounded, size: 18),
                label: const Text('恢复'),
              )
            else ...[
              TextButton(onPressed: () => store.remove(it), child: const Text('撤销')),
              TextButton(onPressed: () => store.patch(it, {'done': !it.done}), child: Text(it.done ? '标为未完成' : '完成')),
              TextButton(
                onPressed: () {
                  context.read<ScheduleFocus>().value = it.day;
                  ShellNav.goTo(Tabs.schedule);
                },
                child: const Text('查看日程'),
              ),
            ],
          ]),
        ]),
      ),
    );
  }
}

/// Day the schedule page should show next (set by cards that link to it).
class ScheduleFocus extends ValueNotifier<DateTime?> {
  ScheduleFocus() : super(null);
}
