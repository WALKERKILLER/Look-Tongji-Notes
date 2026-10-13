import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../theme/tokens.dart';
import '../../widgets/report_screen.dart';
import '../../widgets/states.dart';
import 'schedule_store.dart';
import 'schedule_widgets.dart';

/// Month calendar beside an agenda of homework, exams and activities.
class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});
  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  DateTime _selected = dayOf(DateTime.now());
  late DateTime _month = DateTime(_selected.year, _selected.month);
  bool _all = false;
  bool _monthOpen = false;
  final _keys = <String, GlobalKey>{};
  late final ScheduleFocus _focus;

  @override
  void initState() {
    super.initState();
    _focus = context.read<ScheduleFocus>()..addListener(_onFocus);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onFocus());
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    super.dispose();
  }

  void _onFocus() {
    final d = _focus.value;
    if (d == null || !mounted) return;
    _focus.value = null;
    _select(d);
  }

  void _select(DateTime d) {
    setState(() {
      _selected = dayOf(d);
      _month = DateTime(d.year, d.month);
      if (_selected.isBefore(dayOf(DateTime.now()))) _all = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _keys[isoDate(_selected)]?.currentContext;
      if (c != null) Scrollable.ensureVisible(c, duration: Motion.long2, curve: Motion.emphasized, alignment: 0.05);
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ScheduleStore>();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final open = store.items.where((i) => !i.done).length;
    final overdue = store.items.where((i) => i.overdue).length;

    final header = Padding(
      padding: EdgeInsets.fromLTRB(wide ? Space.xl : Space.lg, wide ? Space.xl : Space.lg, Space.lg, Space.sm),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('日程', style: tt.headlineMedium),
            const SizedBox(height: 2),
            Text(
              [open == 0 ? '没有待办' : '$open 项待办', if (overdue > 0) '$overdue 项已逾期'].join(' · '),
              style: tt.bodyMedium?.copyWith(color: overdue > 0 ? cs.error : cs.onSurfaceVariant),
            ),
          ]),
        ),
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [ButtonSegment(value: false, label: Text('待办')), ButtonSegment(value: true, label: Text('全部'))],
          selected: {_all},
          onSelectionChanged: (s) => setState(() => _all = s.first),
        ),
      ]),
    );

    final calendar = _MonthCalendar(
      month: _month,
      selected: _selected,
      store: store,
      collapsed: !wide && !_monthOpen,
      onSelect: _select,
      onMonth: (m) => setState(() => _month = m),
      onToggle: wide ? null : () => setState(() => _monthOpen = !_monthOpen),
    );

    final agenda = !store.loaded
        ? const CenteredLoader()
        : store.items.isEmpty
            ? EmptyState(
                icon: Icons.event_available_outlined,
                title: '还没有日程',
                body: '老师在课上说到带日期的作业、考试或活动时，助手可以把它标记进来，并附上原话和录像时间点。也可以自己添加。',
                action: FilledButton.tonalIcon(
                  onPressed: () => showScheduleEditor(context, day: _selected),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('添加日程'),
                ),
              )
            : _Agenda(items: store.items, all: _all, selected: _selected, keys: _keys, onSelect: _select);

    return ReportScreen(
      value: {'screen': '日程', 'open_items': '$open', 'overdue': '$overdue', 'selected_day': isoDate(_selected)},
      child: Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'schedule-add',
          onPressed: () => showScheduleEditor(context, day: _selected.isBefore(dayOf(DateTime.now())) ? null : _selected),
          icon: const Icon(Icons.add_rounded),
          label: const Text('新建'),
        ),
        body: wide
            ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                header,
                Expanded(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Space.xl, Space.sm, Space.md, Space.xl),
                      child: SizedBox(width: 340, child: calendar),
                    ),
                    Expanded(child: agenda),
                  ]),
                ),
              ])
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                header,
                Padding(padding: const EdgeInsets.symmetric(horizontal: Space.md), child: calendar),
                Expanded(child: agenda),
              ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- calendar

class _MonthCalendar extends StatefulWidget {
  const _MonthCalendar({
    required this.month,
    required this.selected,
    required this.store,
    required this.collapsed,
    required this.onSelect,
    required this.onMonth,
    this.onToggle,
  });
  final DateTime month, selected;
  final ScheduleStore store;
  final bool collapsed;
  final ValueChanged<DateTime> onSelect, onMonth;
  final VoidCallback? onToggle;
  @override
  State<_MonthCalendar> createState() => _MonthCalendarState();
}

class _MonthCalendarState extends State<_MonthCalendar> {
  int _dir = 1;

  void _shift(int delta) {
    setState(() => _dir = delta);
    if (widget.collapsed) {
      final d = widget.selected.add(Duration(days: 7 * delta));
      widget.onSelect(d);
    } else {
      widget.onMonth(DateTime(widget.month.year, widget.month.month + delta));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final m = widget.collapsed ? DateTime(widget.selected.year, widget.selected.month) : widget.month;
    final today = dayOf(DateTime.now());
    final showToday = widget.selected != today || m != DateTime(today.year, today.month);

    // Monday-first grid; collapsed shows only the selected week.
    final List<DateTime> days;
    if (widget.collapsed) {
      final start = widget.selected.subtract(Duration(days: widget.selected.weekday - 1));
      days = [for (var i = 0; i < 7; i++) start.add(Duration(days: i))];
    } else {
      final first = DateTime(m.year, m.month);
      final start = first.subtract(Duration(days: first.weekday - 1));
      days = [for (var i = 0; i < 42; i++) DateTime(start.year, start.month, start.day + i)];
    }

    final grid = GridView.count(
      key: ValueKey('${widget.collapsed}-${days.first}'),
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 0.92,
      children: [
        for (final d in days)
          _DayCell(
            day: d,
            inMonth: widget.collapsed || d.month == m.month,
            today: d == today,
            selected: d == widget.selected,
            items: widget.store.onDay(d),
            onTap: () => widget.onSelect(d),
          ),
      ],
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(Space.sm, Space.sm, Space.sm, Space.xs),
      decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(Corners.xl)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          const SizedBox(width: Space.sm),
          Text('${m.year}年${m.month}月', style: tt.titleMedium),
          if (showToday)
            Padding(
              padding: const EdgeInsets.only(left: Space.xs),
              child: TextButton(onPressed: () => widget.onSelect(today), child: const Text('今天')),
            ),
          const Spacer(),
          IconButton(tooltip: widget.collapsed ? '上一周' : '上个月', onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left_rounded)),
          IconButton(tooltip: widget.collapsed ? '下一周' : '下个月', onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right_rounded)),
        ]),
        Row(children: [
          for (final w in weekdayNames)
            Expanded(child: Center(child: Text(w, style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)))),
        ]),
        const SizedBox(height: Space.xs),
        GestureDetector(
          onHorizontalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            if (v.abs() > 200) _shift(v < 0 ? 1 : -1);
          },
          child: AnimatedSize(
            duration: Motion.medium4,
            curve: Motion.emphasized,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: Motion.medium2,
              switchInCurve: Motion.emphasizedDecelerate,
              transitionBuilder: (c, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(position: Tween(begin: Offset(0.08 * _dir, 0), end: Offset.zero).animate(a), child: c),
              ),
              layoutBuilder: (cur, prev) => Stack(alignment: Alignment.topCenter, children: [...prev.map((p) => Positioned.fill(child: p)), ?cur]),
              child: grid,
            ),
          ),
        ),
        if (widget.onToggle != null)
          SizedBox(
            height: 28,
            child: IconButton(
              padding: EdgeInsets.zero,
              tooltip: widget.collapsed ? '展开月历' : '收起月历',
              onPressed: widget.onToggle,
              icon: AnimatedRotation(
                turns: widget.collapsed ? 0 : 0.5,
                duration: Motion.medium2,
                child: Icon(Icons.expand_more_rounded, color: cs.onSurfaceVariant),
              ),
            ),
          ),
      ]),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.day, required this.inMonth, required this.today, required this.selected, required this.items, required this.onTap});
  final DateTime day;
  final bool inMonth, today, selected;
  final List<ScheduleItem> items;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final fill = today ? cs.primary : selected ? cs.secondaryContainer : Colors.transparent;
    final fg = today
        ? cs.onPrimary
        : selected
            ? cs.onSecondaryContainer
            : inMonth
                ? cs.onSurface
                : cs.onSurface.withValues(alpha: 0.38);
    final dots = items.take(3).toList();
    return Semantics(
      button: true,
      selected: selected,
      label: '${day.month}月${day.day}日${items.isEmpty ? '' : '，${items.length} 项日程'}',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          AnimatedContainer(
            duration: Motion.medium1,
            curve: Motion.emphasized,
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: fill,
              shape: BoxShape.circle,
              border: selected && today ? Border.all(color: cs.secondaryContainer, width: 2, strokeAlign: BorderSide.strokeAlignOutside) : null,
            ),
            child: Text('${day.day}', style: tt.bodyMedium?.copyWith(color: fg, fontWeight: today || selected ? FontWeight.w600 : null)),
          ),
          const SizedBox(height: 3),
          SizedBox(
            height: 5,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (final it in dots)
                Container(
                  width: 5,
                  height: 5,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: it.done ? cs.outlineVariant : it.overdue ? cs.error : KindStyle.of(context, it.kind).accent,
                  ),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- agenda

class _Agenda extends StatelessWidget {
  const _Agenda({required this.items, required this.all, required this.selected, required this.keys, required this.onSelect});
  final List<ScheduleItem> items;
  final bool all;
  final DateTime selected;
  final Map<String, GlobalKey> keys;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final today = isoDate(dayOf(DateTime.now()));
    final overdue = all ? <ScheduleItem>[] : items.where((i) => i.overdue).toList();
    final shown = items.where((i) => all || (!i.done && i.dueDate.compareTo(today) >= 0)).toList();
    final byDay = <String, List<ScheduleItem>>{};
    for (final i in shown) {
      byDay.putIfAbsent(i.dueDate, () => []).add(i);
    }
    // The selected day always has a row, so tapping an empty day offers to add.
    byDay.putIfAbsent(isoDate(selected), () => []);
    final days = byDay.keys.toList()..sort();

    final children = <Widget>[];
    if (overdue.isNotEmpty) {
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(Space.sm, Space.sm, 0, Space.sm),
        child: Row(children: [
          Icon(Icons.error_outline_rounded, size: 18, color: cs.error),
          const SizedBox(width: Space.sm),
          Text('已逾期', style: tt.titleSmall?.copyWith(color: cs.error)),
        ]),
      ));
      for (final i in overdue) {
        children.add(Padding(padding: const EdgeInsets.only(bottom: Space.sm), child: ScheduleTile(item: i, showDate: true)));
      }
      children.add(const SizedBox(height: Space.md));
    }
    var lastMonth = '';
    for (final k in days) {
      final d = DateTime.parse(k);
      final month = '${d.year}-${d.month}';
      if (month != lastMonth) {
        lastMonth = month;
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(Space.sm, Space.lg, 0, Space.sm),
          child: Text(d.year == DateTime.now().year ? '${d.month}月' : '${d.year}年${d.month}月', style: tt.titleSmall?.copyWith(color: cs.primary)),
        ));
      }
      children.add(KeyedSubtree(
        key: keys.putIfAbsent(k, GlobalKey.new),
        child: _DayRow(day: d, items: byDay[k]!, today: k == today, selected: d == selected, onSelect: onSelect),
      ));
    }
    return ListView(padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.lg, 96), children: children);
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({required this.day, required this.items, required this.today, required this.selected, required this.onSelect});
  final DateTime day;
  final List<ScheduleItem> items;
  final bool today, selected;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          borderRadius: BorderRadius.circular(Corners.lg),
          onTap: () => onSelect(day),
          child: SizedBox(
            width: 56,
            child: Column(children: [
              const SizedBox(height: Space.xs),
              Text('周${weekdayNames[day.weekday - 1]}', style: tt.labelMedium?.copyWith(color: today ? cs.primary : cs.onSurfaceVariant)),
              const SizedBox(height: 2),
              AnimatedContainer(
                duration: Motion.medium1,
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: today ? cs.primary : selected ? cs.secondaryContainer : Colors.transparent,
                ),
                child: Text('${day.day}',
                    style: tt.titleLarge?.copyWith(color: today ? cs.onPrimary : selected ? cs.onSecondaryContainer : cs.onSurface)),
              ),
            ]),
          ),
        ),
        const SizedBox(width: Space.sm),
        Expanded(
          child: items.isEmpty
              ? Container(
                  height: 56,
                  margin: const EdgeInsets.only(top: Space.xs),
                  padding: const EdgeInsets.symmetric(horizontal: Space.md),
                  decoration: BoxDecoration(
                    border: Border.all(color: cs.outlineVariant),
                    borderRadius: BorderRadius.circular(Corners.lg),
                  ),
                  child: Row(children: [
                    Expanded(child: Text('这天没有安排', style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant))),
                    TextButton.icon(
                      onPressed: () => showScheduleEditor(context, day: day),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('添加'),
                    ),
                  ]),
                )
              : Column(children: [
                  for (final i in items) Padding(padding: const EdgeInsets.only(bottom: Space.sm), child: ScheduleTile(item: i)),
                ]),
        ),
      ]),
    );
  }
}

/// Compact list of what is coming up, for the home page.
class UpcomingSchedule extends StatelessWidget {
  const UpcomingSchedule({super.key, required this.onOpen});
  final ValueChanged<DateTime?> onOpen;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ScheduleStore>();
    final items = store.upcoming().take(4).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final course = context.read<AppState>();
    return LayoutBuilder(builder: (context, c) {
      final cols = (c.maxWidth / 260).floor().clamp(1, 4);
      final w = (c.maxWidth - Space.md * (cols - 1)) / cols;
      return Wrap(spacing: Space.md, runSpacing: Space.md, children: [
        for (final it in items.take(cols * (cols == 1 ? 3 : 1)))
          SizedBox(
            width: w,
            child: Material(
              color: cs.surfaceContainer,
              borderRadius: BorderRadius.circular(Corners.lg),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onOpen(it.day),
                child: Padding(
                  padding: const EdgeInsets.all(Space.md),
                  child: Row(children: [
                    DateLeaf(date: it.day, style: KindStyle.of(context, it.kind), size: 44),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(it.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.titleSmall),
                        const SizedBox(height: 2),
                        Text(
                          [fmtCountdown(it), if (it.courseTitle.isNotEmpty) it.courseTitle else course.course(it.courseId)?.title ?? ''].where((s) => s.isNotEmpty).join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.bodySmall?.copyWith(color: it.overdue ? cs.error : cs.onSurfaceVariant),
                        ),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
          ),
      ]);
    });
  }
}
