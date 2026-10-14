import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../theme/tokens.dart';
import '../../widgets/charts.dart';
import '../../widgets/heatmap.dart';
import '../../widgets/states.dart';
import '../courses/course_page.dart';
import '../library/note_reader.dart';
import '../player/player_page.dart';

/// Timed kinds in display order.
const kActivityKinds = ['watch', 'read', 'practice'];

String activityKindLabel(String k) => switch (k) {
      'watch' => '看课',
      'read' => '阅读',
      'practice' => '练习',
      _ => k,
    };

/// Fetches a lookd path; a seam for widget tests.
typedef ActivityFetch = Future<dynamic> Function(String path, Map<String, String> query);

ActivityFetch _apiFetch(BuildContext context) {
  final api = context.read<AppState>().api;
  return (path, query) => api.get(path, query);
}

int _int(Object? v) => (v as num?)?.toInt() ?? 0;

/// One day of `GET /api/activity`.
class ActivityDay {
  ActivityDay(this.j);
  final Map<String, dynamic> j;

  String get date => '${j['date']}';
  int get minutes => _int(j['minutes']);
  int get asks => _int(j['asks']);
  int get notesCreated => _int(j['notes_created']);
  int get notesEdited => _int(j['notes_edited']);
  int get transcripts => _int(j['transcripts']);

  /// Minutes per timed kind.
  int kindMinutes(String k) => (_int((j['by_kind'] as Map?)?[k]) / 60).round();

  bool get active => minutes >= 1 || asks > 0 || notesCreated > 0 || notesEdited > 0;

  /// Heatmap intensity: minutes, with days of only questions or notes shown
  /// at the lowest step so they match the streak.
  num get intensity => minutes > 0 ? minutes : (active ? .5 : 0);

  static final empty = ActivityDay(const {});

  /// Tooltip title and lines.
  (String, List<String>) tooltip(DateTime d) => (
        fmtDayLabel(d),
        [
          if (!active) '没有学习记录' else if (minutes > 0) '学习 ${fmtMinutes(minutes)}',
          if (minutes > 0) [for (final k in kActivityKinds) if (kindMinutes(k) > 0) '${activityKindLabel(k)} ${kindMinutes(k)}'].join(' · '),
          if (asks > 0 || notesCreated + notesEdited > 0)
            [if (asks > 0) '提问 $asks 次', if (notesCreated + notesEdited > 0) '笔记 ${notesCreated + notesEdited} 篇'].join(' · '),
        ],
      );

  String describe(DateTime d) => '${fmtMonthDay(d)}，${minutes > 0 ? '学习 ${fmtMinutes(minutes)}' : active ? '有学习记录' : '没有学习'}';
}

/// `GET /api/activity` for a range.
class ActivityData {
  ActivityData(Map<String, dynamic> j)
      : days = {for (final d in (j['days'] as List? ?? const [])) '${d['date']}': ActivityDay((d as Map).cast<String, dynamic>())},
        current = _int((j['streak'] as Map?)?['current']),
        longest = _int((j['streak'] as Map?)?['longest']),
        minutes = _int((j['totals'] as Map?)?['minutes']),
        activeDays = _int((j['totals'] as Map?)?['active_days']),
        courses = [for (final c in (j['courses'] as List? ?? const [])) (c as Map).cast<String, dynamic>()];

  final Map<String, ActivityDay> days;
  final int current, longest, minutes, activeDays;
  final List<Map<String, dynamic>> courses;

  ActivityDay on(DateTime d) => days[fmtIsoDay(d)] ?? ActivityDay.empty;

  int minutesSince(DateTime from, DateTime to) {
    var m = 0;
    for (var d = dayOf(from); !d.isAfter(to); d = DateTime(d.year, d.month, d.day + 1)) {
      m += on(d).minutes;
    }
    return m;
  }

  bool get isEmpty => days.values.every((d) => !d.active);
}

/// Reloads when lookd reports new activity or notes, at most every 2 s.
mixin _LiveActivity<T extends StatefulWidget> on State<T> {
  StreamSubscription? _sub;
  Timer? _debounce;

  Future<void> reload();

  void listenActivity() {
    _sub = context.read<AppState>().events.listen((e) {
      if (e['type'] == 'activity_changed' || e['type'] == 'notes_changed') {
        _debounce?.cancel();
        _debounce = Timer(const Duration(seconds: 2), reload);
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _debounce?.cancel();
    super.dispose();
  }
}

/// Home card 学习足迹: as many recent weeks as fit, with this week's time and
/// streaks.
class ActivityCard extends StatefulWidget {
  const ActivityCard({super.key, this.fetch, this.today});
  final ActivityFetch? fetch;
  final DateTime? today;
  @override
  State<ActivityCard> createState() => _ActivityCardState();
}

class _ActivityCardState extends State<ActivityCard> with _LiveActivity {
  ActivityData? _data;
  late DateTime _today = dayOf(widget.today ?? DateTime.now());

  @override
  void initState() {
    super.initState();
    reload();
    if (widget.fetch == null) listenActivity();
  }

  @override
  Future<void> reload() async {
    _today = dayOf(widget.today ?? DateTime.now());
    final from = weekStart(_today).subtract(const Duration(days: 52 * 7));
    try {
      final r = await (widget.fetch ?? _apiFetch(context))('/api/activity', {'from': fmtIsoDay(from), 'to': fmtIsoDay(_today)});
      if (mounted) setState(() => _data = ActivityData((r as Map).cast<String, dynamic>()));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final d = _data;
    return Container(
      padding: const EdgeInsets.fromLTRB(Space.xl, Space.lg, Space.xl, Space.lg),
      decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: Corners.all(Corners.xl)),
      child: LayoutBuilder(builder: (context, c) {
        final weeks = ContributionHeatmap.weeksFor(c.maxWidth);
        final from = weekStart(_today).subtract(Duration(days: (weeks - 1) * 7));
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: Space.xxl, runSpacing: Space.md, children: [
            _Figure(value: d == null ? '—' : fmtMinutes(d.minutesSince(weekStart(_today), _today)), label: '本周'),
            _Figure(value: d == null ? '—' : '${d.current} 天', label: '连续学习'),
            _Figure(value: d == null ? '—' : '${d.longest} 天', label: '最长连续'),
          ]),
          const SizedBox(height: Space.lg),
          ContributionHeatmap(
            from: from,
            to: _today,
            today: _today,
            value: (day) => d?.on(day).intensity ?? 0,
            describe: (day) => (d?.on(day) ?? ActivityDay.empty).describe(day),
            tooltip: (day) => (d?.on(day) ?? ActivityDay.empty).tooltip(day),
            onTap: (day) => showActivityDay(context, day, fetch: widget.fetch),
          ),
          const SizedBox(height: Space.md),
          Row(children: [
            Expanded(
              child: d != null && d.isEmpty
                  ? Text('开始看课或做题后，这里会记录你的学习足迹', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant))
                  : const SizedBox.shrink(),
            ),
            const HeatLegend(),
          ]),
        ]);
      }),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.value, required this.label});
  final String value, label;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return MergeSemantics(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(value, style: tt.titleLarge?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
      ]),
    );
  }
}

/// 学习统计: a year of activity with kind and course totals.
class ActivityPage extends StatefulWidget {
  const ActivityPage({super.key, this.fetch, this.today});
  final ActivityFetch? fetch;
  final DateTime? today;
  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage> with _LiveActivity {
  late final DateTime _today = dayOf(widget.today ?? DateTime.now());
  late int _year = _today.year;
  ActivityData? _data;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    reload();
    if (widget.fetch == null) listenActivity();
  }

  @override
  Future<void> reload() async {
    setState(() => _loading = true);
    final year = _year;
    try {
      final r = await (widget.fetch ?? _apiFetch(context))('/api/activity', {'from': '$year-01-01', 'to': '$year-12-31'});
      if (!mounted || year != _year) return;
      setState(() {
        _data = ActivityData((r as Map).cast<String, dynamic>());
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _setYear(int y) {
    setState(() {
      _year = y;
      _data = null;
    });
    reload();
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final d = _data;
    final Widget body;
    if (d == null && _loading) {
      body = const CenteredLoader();
    } else if (d == null) {
      body = ErrorState(error: _error ?? '没有数据', onRetry: reload);
    } else {
      body = RefreshIndicator(
        onRefresh: reload,
        child: ListView(padding: const EdgeInsets.fromLTRB(0, Space.sm, 0, Space.xxxl), children: [
          ContentWidth(
            child: Padding(
              padding: context.isCompact ? Space.pageCompact : Space.page,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                StatGrid(children: [
                  StatTile(icon: Icons.schedule_rounded, label: '学习时长', value: fmtMinutes(d.minutes)),
                  StatTile(icon: Icons.event_available_outlined, label: '学习天数', value: '${d.activeDays} 天'),
                  StatTile(icon: Icons.local_fire_department_outlined, label: '当前连续', value: '${d.current} 天'),
                  StatTile(icon: Icons.emoji_events_outlined, label: '最长连续', value: '${d.longest} 天'),
                ]),
                const SizedBox(height: Space.lg),
                _Section(
                  title: '$_year 年',
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    LayoutBuilder(builder: (context, c) {
                      final from = DateTime(_year), to = DateTime(_year, 12, 31);
                      final cols = heatWeeks(from, to).length;
                      final cell = ((c.maxWidth - ContributionHeatmap.labelWidth + ContributionHeatmap.gap) / cols - ContributionHeatmap.gap).clamp(9.0, 13.0);
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        reverse: _year == _today.year,
                        child: ContributionHeatmap(
                          from: from,
                          to: to,
                          today: _today,
                          cell: cell.floorToDouble(),
                          value: (day) => d.on(day).intensity,
                          describe: (day) => d.on(day).describe(day),
                          tooltip: (day) => d.on(day).tooltip(day),
                          onTap: (day) => showActivityDay(context, day, fetch: widget.fetch),
                        ),
                      );
                    }),
                    const SizedBox(height: Space.md),
                    const Align(alignment: Alignment.centerRight, child: HeatLegend()),
                  ]),
                ),
                const SizedBox(height: Space.lg),
                _Section(title: '按类型', child: _kinds(d)),
                const SizedBox(height: Space.lg),
                _Section(
                  title: '按课程',
                  child: d.courses.isEmpty
                      ? Padding(padding: const EdgeInsets.symmetric(vertical: Space.md), child: Text('还没有按课程记录的学习时间', style: tt.bodyMedium))
                      : Column(children: [
                          for (final c in d.courses)
                            RankedRow(
                              label: '${c['title'] ?? ''}'.isEmpty ? '未归类' : '${c['title']}',
                              fraction: _int(c['minutes']) / math.max(1, _int(d.courses.first['minutes'])),
                              trailing: fmtMinutes(_int(c['minutes'])),
                              onTap: '${c['course_id'] ?? ''}'.isEmpty
                                  ? null
                                  : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CoursePage(courseId: '${c['course_id']}'))),
                            ),
                        ]),
                ),
              ]),
            ),
          ),
        ]),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('学习统计'), actions: [
        IconButton(tooltip: '上一年', onPressed: () => _setYear(_year - 1), icon: const Icon(Icons.chevron_left_rounded)),
        Text('$_year', style: tt.titleMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
        IconButton(tooltip: '下一年', onPressed: _year >= _today.year ? null : () => _setYear(_year + 1), icon: const Icon(Icons.chevron_right_rounded)),
        const SizedBox(width: Space.sm),
      ]),
      body: body,
    );
  }

  Widget _kinds(ActivityData d) {
    final totals = {for (final k in kActivityKinds) k: d.days.values.fold<int>(0, (s, day) => s + _int((day.j['by_kind'] as Map?)?[k]))};
    final top = totals.values.fold<int>(1, math.max);
    var asks = 0, notes = 0;
    for (final day in d.days.values) {
      asks += day.asks;
      notes += day.notesCreated;
    }
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final k in kActivityKinds) RankedRow(label: activityKindLabel(k), fraction: totals[k]! / top, trailing: fmtMinutes(totals[k]! / 60)),
      Padding(
        padding: const EdgeInsets.only(top: Space.sm),
        child: Text('向助手提问 $asks 次 · 新建笔记 $notes 篇', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
      ),
    ]);
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.lg),
      decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: Corners.all(Corners.xl)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(height: 40, child: Align(alignment: Alignment.centerLeft, child: Text(title, style: Theme.of(context).textTheme.titleMedium))),
        const SizedBox(height: Space.sm),
        child,
      ]),
    );
  }
}

/// Bottom sheet with what happened on [day].
Future<void> showActivityDay(BuildContext context, DateTime day, {ActivityFetch? fetch}) => showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (c) => _DaySheet(day: day, load: (fetch ?? _apiFetch(context))('/api/activity/day', {'date': fmtIsoDay(day)})),
    );

class _DaySheet extends StatelessWidget {
  const _DaySheet({required this.day, required this.load});
  final DateTime day;
  final Future<dynamic> load;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
      child: FutureBuilder(
        future: load,
        builder: (context, snap) {
          if (snap.hasError) return Padding(padding: const EdgeInsets.all(Space.xl), child: ErrorState(error: snap.error!));
          if (!snap.hasData) return const SizedBox(height: 200, child: CenteredLoader());
          final j = (snap.data as Map).cast<String, dynamic>();
          final d = ActivityDay(j);
          final lectures = _byLecture(j['lectures'] as List? ?? const []);
          final notes = [for (final n in (j['notes'] as List? ?? const [])) (n as Map).cast<String, dynamic>()];
          final transcribed = [for (final t in (j['transcribed'] as List? ?? const [])) (t as Map).cast<String, dynamic>()];
          final counts = [
            if (d.asks > 0) '提问 ${d.asks} 次',
            if (d.notesCreated > 0) '新建笔记 ${d.notesCreated} 篇',
            if (d.notesEdited > 0) '编辑笔记 ${d.notesEdited} 篇',
            if (d.transcripts > 0) '完成转写 ${d.transcripts} 节',
          ];
          void open(Widget page) {
            Navigator.pop(context);
            Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => page));
          }

          return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(0, 0, 0, Space.xl), children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.xl),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(fmtDayLabel(day), style: tt.titleLarge),
                const SizedBox(height: Space.xs),
                Text(d.minutes > 0 ? '学习 ${fmtMinutes(d.minutes)}' : d.active ? '没有计时的学习' : '这天没有学习记录',
                    style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                if (d.minutes > 0) ...[
                  const SizedBox(height: Space.lg),
                  Wrap(spacing: Space.xxl, runSpacing: Space.md, children: [
                    for (final k in kActivityKinds) _Figure(value: fmtMinutes(d.kindMinutes(k)), label: activityKindLabel(k)),
                  ]),
                ],
                if (counts.isNotEmpty) ...[
                  const SizedBox(height: Space.lg),
                  Text(counts.join(' · '), style: tt.bodyMedium),
                ],
              ]),
            ),
            if (lectures.isNotEmpty) ...[
              _subheader(context, '课程'),
              for (final l in lectures)
                ListTile(
                  leading: const Icon(Icons.play_circle_outline_rounded),
                  title: Text('${l['title']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text([if ('${l['course_title'] ?? ''}'.isNotEmpty) '${l['course_title']}', l['detail']].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () => open(PlayerPage(lectureId: '${l['lecture_id']}')),
                ),
            ],
            if (notes.isNotEmpty) ...[
              _subheader(context, '笔记'),
              for (final n in notes)
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: Text('${n['title']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(n['created'] == true ? '新建' : '编辑'),
                  onTap: () => open(NotePage(noteId: '${n['id']}')),
                ),
            ],
            if (transcribed.isNotEmpty) ...[
              _subheader(context, '完成转写'),
              for (final t in transcribed)
                ListTile(
                  leading: const Icon(Icons.subject_rounded),
                  title: Text('${t['title']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: '${t['course_title'] ?? ''}'.isEmpty ? null : Text('${t['course_title']}'),
                  onTap: () => open(PlayerPage(lectureId: '${t['lecture_id']}')),
                ),
            ],
          ]);
        },
      ),
    );
  }

  /// Merges per-kind rows into one row per lecture: "看课 32 分钟 · 阅读 5 分钟".
  static List<Map<String, Object?>> _byLecture(List rows) {
    final out = <String, Map<String, Object?>>{};
    final secs = <String, Map<String, int>>{};
    for (final r in rows.cast<Map>()) {
      final id = '${r['lecture_id']}';
      out[id] ??= {'lecture_id': id, 'title': r['title'], 'course_title': r['course_title']};
      (secs[id] ??= {}).update('${r['kind']}', (v) => v + _int(r['seconds']), ifAbsent: () => _int(r['seconds']));
    }
    for (final MapEntry(:key, :value) in out.entries) {
      final s = secs[key]!;
      value['detail'] = [for (final k in kActivityKinds) if ((s[k] ?? 0) >= 60) '${activityKindLabel(k)} ${fmtMinutes(s[k]! / 60)}'].join(' · ');
      value['total'] = s.values.fold<int>(0, (a, b) => a + b);
    }
    return out.values.toList()..sort((a, b) => (b['total'] as int).compareTo(a['total'] as int));
  }

  Widget _subheader(BuildContext context, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(Space.xl, Space.xl, Space.xl, Space.xs),
        child: Text(t, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}

