import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../theme/tokens.dart';
import '../../widgets/charts.dart';
import '../../widgets/horizontal_scroller.dart';
import '../../widgets/states.dart';
import '../../l10n/l10n.dart';

/// What each ledger `purpose` means to the user.
final kUsagePurposes = <String, (String, IconData)>{
  'chat': (l10n.usagePurposeChat, Icons.chat_bubble_outline_rounded),
  'timeline': (l10n.commonOutline, Icons.view_timeline_outlined),
  'vision': (l10n.modelTagVision, Icons.image_search_outlined),
  'title': (l10n.commonTitle, Icons.title_rounded),
  'test': (l10n.usagePurposeTest, Icons.network_check_rounded),
  'task': (l10n.commonScheduledTasks, Icons.schedule_rounded),
  'quiz': (l10n.panelQuiz, Icons.quiz_outlined),
  'memory': (l10n.usagePurposeMemory, Icons.bedtime_outlined),
};

String purposeLabel(String p) => kUsagePurposes[p]?.$1 ?? p;

enum UsageRange {
  week(7),
  month(30),
  quarter(90),
  year(0);

  const UsageRange(this.days);
  final int days;

  String get label => switch (this) {
        week => l10n.range7Days,
        month => l10n.range30Days,
        quarter => l10n.range90Days,
        year => l10n.rangeThisYear,
      };

  (DateTime, DateTime) bounds(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return (days == 0 ? DateTime(now.year) : today.subtract(Duration(days: days - 1)), today);
  }
}

/// Filter for the call log; null fields match everything.
class CallFilter {
  const CallFilter({this.from, this.to, this.model, this.purpose, this.sessionId, required this.title});
  final String? from;
  final String? to;
  final String? model;
  final String? purpose;
  final String? sessionId;
  final String title;

  Map<String, String> get query => {
        'from': ?from,
        'to': ?to,
        'model': ?model,
        'purpose': ?purpose,
        'session_id': ?sessionId,
      };
}

num _n(Map? m, String k) => (m?[k] as num?) ?? 0;

/// Every token the model processed: fresh input, cache reads and writes, output.
num _allTokens(Map? t) => _n(t, 'input') + _n(t, 'cache_read') + _n(t, 'cache_write') + _n(t, 'output');

/// GET helper; defaults to the lookd API (agent routes under /agent/).
typedef UsageFetch = Future<dynamic> Function(String path, Map<String, String> query);

UsageFetch _apiFetch(BuildContext context) {
  final api = context.read<AppState>().api;
  return (path, query) => api.get(path, query);
}

/// Assistant usage from the agent's ledger: totals, a daily trend, breakdowns
/// and individual calls (docs/specs/0000-usage-ledger-and-cost-stats.md).
class UsagePage extends StatefulWidget {
  const UsagePage({super.key, this.fetch});
  final UsageFetch? fetch;
  @override
  State<UsagePage> createState() => _UsagePageState();
}

enum _Metric { cost, tokens }

enum _Breakdown { model, purpose, session }

class _UsagePageState extends State<UsagePage> {
  var _range = UsageRange.month;
  var _metric = _Metric.cost;
  var _by = _Breakdown.model;
  var _table = false;
  Map<String, dynamic>? _summary;
  List<Map<String, dynamic>> _recent = const [];
  Object? _error;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final (from, to) = _range.bounds(DateTime.now());
    final q = {'from': fmtIsoDay(from), 'to': fmtIsoDay(to)};
    setState(() => _loading = true);
    try {
      final get = widget.fetch ?? _apiFetch(context);
      final res = await Future.wait([get('/agent/usage/summary', q), get('/agent/usage/calls', {...q, 'limit': '12'})]);
      if (!mounted) return;
      setState(() {
        _summary = (res[0] as Map).cast<String, dynamic>();
        _recent = jsonList(res[1]).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  void _openCalls(CallFilter f) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CallLogPage(filter: f, fetch: widget.fetch)));

  CallFilter _rangeFilter({String? model, String? purpose, String? sessionId, required String title}) =>
      CallFilter(from: _summary?['from'] as String?, to: _summary?['to'] as String?, model: model, purpose: purpose, sessionId: sessionId, title: title);

  @override
  Widget build(BuildContext context) {
    final s = _summary;
    Widget body;
    if (s == null && _loading) {
      body = const CenteredLoader();
    } else if (s == null) {
      body = ErrorState(error: _error ?? l10n.commonNoData, onRetry: _load);
    } else {
      final totals = (s['totals'] as Map?) ?? const {};
      final empty = _n(totals, 'calls') == 0;
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: EdgeInsets.fromLTRB(0, Space.sm, 0, Space.xxxl), children: [
          ContentWidth(
            child: Padding(
              padding: context.isCompact ? Space.pageCompact : Space.page,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SegmentedButton<UsageRange>(
                    showSelectedIcon: false,
                    segments: [for (final r in UsageRange.values) ButtonSegment(value: r, label: Text(r.label))],
                    selected: {_range},
                    onSelectionChanged: (v) {
                      setState(() => _range = v.first);
                      _load();
                    },
                  ),
                ),
                const SizedBox(height: Space.lg),
                _Tiles(totals: totals, previous: (s['previous'] as Map?) ?? const {}, range: _range),
                const SizedBox(height: Space.lg),
                if (empty)
                  Padding(
                    padding: EdgeInsets.only(top: Space.xxl),
                    child: EmptyState(
                      icon: Icons.insights_outlined,
                      title: l10n.usageEmpty,
                      body: l10n.usageEmptyBody,
                    ),
                  )
                else ...[
                  _section(context, title: l10n.usageDaily, trailing: _chartControls(), child: _chart(context, s)),
                  const SizedBox(height: Space.lg),
                  _section(context, title: l10n.usageBreakdown, trailing: _breakdownControl(), child: _breakdown(context, s)),
                  const SizedBox(height: Space.lg),
                  _section(
                    context,
                    title: l10n.usageRecentCalls,
                    trailing: TextButton(onPressed: () => _openCalls(_rangeFilter(title: l10n.usageCallsInRange(_range.label))), child: Text(l10n.commonAll)),
                    child: Column(children: [for (final c in _recent) CallTile(call: c)]),
                  ),
                ],
              ]),
            ),
          ),
        ]),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsUsage),
        bottom: _loading && s != null ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2)) : null,
        actions: [IconButton(tooltip: l10n.commonRefresh, onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: body,
    );
  }

  Widget _section(BuildContext context, {required String title, Widget? trailing, required Widget child}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.lg),
      decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: Corners.all(Corners.xl)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: 40,
          child: Row(children: [
            Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
            ?trailing,
          ]),
        ),
        const SizedBox(height: Space.sm),
        child,
      ]),
    );
  }

  Widget _chartControls() => Row(mainAxisSize: MainAxisSize.min, children: [
        SegmentedButton<_Metric>(
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: [ButtonSegment(value: _Metric.cost, label: Text(l10n.usageCost)), ButtonSegment(value: _Metric.tokens, label: Text('Tokens'))],
          selected: {_metric},
          onSelectionChanged: (v) => setState(() => _metric = v.first),
        ),
        const SizedBox(width: Space.xs),
        IconButton(
          tooltip: _table ? l10n.usageChart : l10n.usageTable,
          isSelected: _table,
          onPressed: () => setState(() => _table = !_table),
          icon: const Icon(Icons.table_rows_outlined),
          selectedIcon: const Icon(Icons.bar_chart_rounded),
        ),
      ]);

  Widget _breakdownControl() => SegmentedButton<_Breakdown>(
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        segments: [
          ButtonSegment(value: _Breakdown.model, label: Text(l10n.commonModel)),
          ButtonSegment(value: _Breakdown.purpose, label: Text(l10n.usagePurpose)),
          ButtonSegment(value: _Breakdown.session, label: Text(l10n.usagePurposeChat)),
        ],
        selected: {_by},
        onSelectionChanged: (v) => setState(() => _by = v.first),
      );

  Widget _chart(BuildContext context, Map<String, dynamic> s) {
    final cs = Theme.of(context).colorScheme;
    final days = jsonList(s['days']).whereType<Map>().toList();
    final dates = [for (final d in days) DateTime.parse(d['date'] as String)];
    final bg = cs.surfaceContainerLow;
    final series = _metric == _Metric.cost
        ? [ChartSeries(l10n.usageEstimatedCost, cs.primary)]
        : [
            ChartSeries(l10n.usageInput, cs.primary),
            ChartSeries(l10n.usageCacheHit, Color.alphaBlend(cs.primary.withValues(alpha: 0.42), bg)),
            ChartSeries(l10n.usageOutput, cs.tertiary),
          ];
    final values = [
      for (final d in days)
        _metric == _Metric.cost
            ? [_n(d, 'cost').toDouble()]
            : [(_n(d, 'input') + _n(d, 'cache_write')).toDouble(), _n(d, 'cache_read').toDouble(), _n(d, 'output').toDouble()],
    ];
    final format = _metric == _Metric.cost ? (double v) => fmtUsd(v) : (double v) => fmtCompact(v);
    if (_table) return _DailyTable(dates: dates, values: values, series: series, format: format);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (series.length > 1) ...[ChartLegend(series: series), const SizedBox(height: Space.md)],
      DailyBarChart(
        days: dates,
        values: values,
        series: series,
        format: format,
        background: bg,
        semanticLabel: l10n.usageChartSemantics(_metric == _Metric.cost ? l10n.usageEstimatedCost : l10n.usageTokens),
      ),
    ]);
  }

  Widget _breakdown(BuildContext context, Map<String, dynamic> s) {
    final key = switch (_by) { _Breakdown.model => 'by_model', _Breakdown.purpose => 'by_purpose', _Breakdown.session => 'by_session' };
    final rows = jsonList(s[key]).whereType<Map>().take(12).toList();
    if (rows.isEmpty) return Padding(padding: EdgeInsets.all(Space.lg), child: Text(l10n.commonNoRecords));
    final byCost = rows.any((r) => _n(r, 'cost') > 0);
    final maxV = rows.map((r) => byCost ? _n(r, 'cost') : _allTokens(r)).fold<num>(0, (a, b) => b > a ? b : a);
    final cs = Theme.of(context).colorScheme;
    return Column(children: [
      for (final r in rows)
        () {
          final k = '${r['key']}';
          final (label, hint, icon) = switch (_by) {
            _Breakdown.model => (k.contains('/') ? k.substring(k.indexOf('/') + 1) : k, k.contains('/') ? k.substring(0, k.indexOf('/')) : '', null),
            _Breakdown.purpose => (purposeLabel(k), '', kUsagePurposes[k]?.$2),
            _Breakdown.session => ((r['title'] as String?) ?? l10n.usageDeletedChat, '', null),
          };
          final v = byCost ? _n(r, 'cost') : _allTokens(r);
          return RankedRow(
            leading: icon == null ? null : Icon(icon, size: 20, color: cs.onSurfaceVariant),
            label: label,
            sublabel: [
              if (hint.isNotEmpty) hint,
              l10n.usageCalls(fmtCompact(_n(r, 'calls'))),
              l10n.usageInputTokens(fmtCompact(_n(r, 'input') + _n(r, 'cache_read') + _n(r, 'cache_write'))),
              l10n.modelTagOutput(fmtCompact(_n(r, 'output'))),
            ].join(' · '),
            trailing: byCost ? fmtUsd(_n(r, 'cost')) : fmtCompact(_allTokens(r)),
            fraction: maxV == 0 ? 0 : v / maxV,
            onTap: () => _openCalls(switch (_by) {
              _Breakdown.model => _rangeFilter(model: k, title: label),
              _Breakdown.purpose => _rangeFilter(purpose: k, title: label),
              _Breakdown.session => _rangeFilter(sessionId: k, title: label),
            }),
          );
        }(),
    ]);
  }
}

class _Tiles extends StatelessWidget {
  const _Tiles({required this.totals, required this.previous, required this.range});
  final Map totals;
  final Map previous;
  final UsageRange range;

  String? _delta(num now, num before) {
    final span = range == UsageRange.year ? l10n.usageLastYear : l10n.usagePreviousDays(range.days);
    if (before == 0) return now == 0 ? null : l10n.usageNoneIn(span);
    final pct = (now - before) / before * 100;
    if (pct.abs() < 0.5) return l10n.usageSameAs(span);
    return l10n.usageCompare(span, pct > 0 ? l10n.heatmapMore : l10n.heatmapLess, pct.abs().round());
  }

  @override
  Widget build(BuildContext context) {
    final prompt = _n(totals, 'input') + _n(totals, 'cache_read');
    final hit = prompt == 0 ? null : _n(totals, 'cache_read') / prompt;
    final errors = _n(totals, 'errors');
    return StatGrid(children: [
      StatTile(icon: Icons.payments_outlined, label: l10n.usageEstimatedCost, value: fmtUsd(_n(totals, 'cost')), note: _delta(_n(totals, 'cost'), _n(previous, 'cost'))),
      StatTile(
        icon: Icons.data_usage_rounded,
        label: 'Tokens',
        value: fmtCompact(_allTokens(totals)),
        note: l10n.usageInputOutput(fmtCompact(prompt + _n(totals, 'cache_write')), fmtCompact(_n(totals, 'output'))),
      ),
      StatTile(
        icon: Icons.swap_vert_rounded,
        label: l10n.usageCallCount,
        value: fmtCompact(_n(totals, 'calls')),
        note: errors > 0 ? l10n.usageFailedCalls(fmtCompact(errors)) : _delta(_n(totals, 'calls'), _n(previous, 'calls')),
      ),
      StatTile(
        icon: Icons.bolt_outlined,
        label: l10n.usageCacheRate,
        value: hit == null ? '—' : '${(hit * 100).toStringAsFixed(hit < 0.1 ? 1 : 0)}%',
        note: hit == null ? null : l10n.usageCacheTokens(fmtCompact(_n(totals, 'cache_read'))),
      ),
    ]);
  }
}

class _DailyTable extends StatelessWidget {
  const _DailyTable({required this.dates, required this.values, required this.series, required this.format});
  final List<DateTime> dates;
  final List<List<double>> values;
  final List<ChartSeries> series;
  final String Function(double) format;

  @override
  Widget build(BuildContext context) {
    final figs = Theme.of(context).textTheme.bodySmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    final rows = [for (var i = dates.length - 1; i >= 0; i--) i].where((i) => values[i].any((v) => v > 0)).toList();
    if (rows.isEmpty) return Text(l10n.commonNoRecords);
    return HorizontalScroller(buttons: false, builder: (c) => SingleChildScrollView(
      controller: c,
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 36,
        dataRowMinHeight: 32,
        dataRowMaxHeight: 36,
        columns: [
          DataColumn(label: Text(l10n.commonDate)),
          for (final s in series) DataColumn(label: Text(s.label), numeric: true),
          if (series.length > 1) DataColumn(label: Text(l10n.chartTotal), numeric: true),
        ],
        rows: [
          for (final i in rows)
            DataRow(cells: [
              DataCell(Text(fmtDayLabel(dates[i]), style: figs)),
              for (final v in values[i]) DataCell(Text(format(v), style: figs)),
              if (series.length > 1) DataCell(Text(format(values[i].fold(0, (a, b) => a + b)), style: figs)),
            ]),
        ],
      ),
    ));
  }
}

/// One ledger line: when, which model and why, tokens in and out, cost.
class CallTile extends StatelessWidget {
  const CallTile({super.key, required this.call});
  final Map<String, dynamic> call;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final t = DateTime.fromMillisecondsSinceEpoch((call['ts'] as num).toInt());
    final ok = call['ok'] != false;
    final purpose = '${call['purpose'] ?? ''}';
    final figs = tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontFeatures: const [FontFeature.tabularFigures()]);
    final ms = _n(call, 'ms');
    final ttft = call['ttft_ms'] as num?;
    final cached = _n(call, 'cache_read');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.sm),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 52,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}', style: tt.labelLarge?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
            Text('${t.month}/${t.day}', style: figs),
          ]),
        ),
        const SizedBox(width: Space.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text('${call['model']}', style: tt.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: Space.sm),
              Text(purposeLabel(purpose), style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
              if (!ok) ...[
                const SizedBox(width: Space.sm),
                Icon(Icons.error_outline_rounded, size: 14, color: cs.error),
                const SizedBox(width: 2),
                Text(l10n.commonFailed, style: tt.labelSmall?.copyWith(color: cs.error)),
              ],
            ]),
            const SizedBox(height: 2),
            Text(
              [
                '${fmtCompact(_n(call, 'input') + cached + _n(call, 'cache_write'))}${cached > 0 ? l10n.usageCachedSuffix(fmtCompact(cached)) : ''} → ${fmtCompact(_n(call, 'output'))}',
                if (ms > 0) '${(ms / 1000).toStringAsFixed(1)}s',
                if (ttft != null) l10n.usageFirstToken((ttft / 1000).toStringAsFixed(1)),
                if (call['title'] != null) '${call['title']}',
              ].join(' · '),
              style: figs,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ]),
        ),
        const SizedBox(width: Space.md),
        Text(fmtUsd(_n(call, 'cost')), style: tt.bodyMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
      ]),
    );
  }
}

/// Paged, newest-first list of ledger lines for one filter.
class CallLogPage extends StatefulWidget {
  const CallLogPage({super.key, required this.filter, this.fetch});
  final CallFilter filter;
  final UsageFetch? fetch;
  @override
  State<CallLogPage> createState() => _CallLogPageState();
}

class _CallLogPageState extends State<CallLogPage> {
  final _calls = <Map<String, dynamic>>[];
  var _done = false;
  var _loading = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _more();
  }

  Future<void> _more() async {
    if (_loading || _done) return;
    setState(() => _loading = true);
    try {
      final before = _calls.isEmpty ? null : '${_calls.last['cursor'] ?? _calls.last['ts']}';
      final res = await (widget.fetch ?? _apiFetch(context))('/agent/usage/calls', {...widget.filter.query, 'limit': '60', 'before': ?before});
      final page = jsonList(res).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
      if (!mounted) return;
      setState(() {
        _calls.addAll(page);
        _done = page.length < 60;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.filter;
    return Scaffold(
      appBar: AppBar(title: Text(f.title)),
      body: _calls.isEmpty && _error != null
          ? ErrorState(error: _error!, onRetry: _more)
          : _calls.isEmpty && _loading
              ? const CenteredLoader()
              : _calls.isEmpty
                  ? EmptyState(icon: Icons.receipt_long_outlined, title: l10n.usageNoCalls)
                  : NotificationListener<ScrollNotification>(
                      onNotification: (n) {
                        if (n.metrics.extentAfter < 400) _more();
                        return false;
                      },
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: Space.sm),
                        itemCount: _calls.length + (_done ? 0 : 1),
                        separatorBuilder: (_, _) => const Divider(height: 1, indent: Space.xxxl + Space.xl),
                        itemBuilder: (context, i) => i == _calls.length
                            ? const Padding(padding: EdgeInsets.all(Space.lg), child: Center(child: CircularProgressIndicator()))
                            : ContentWidth(
                                max: 840,
                                child: Padding(padding: context.isCompact ? Space.pageCompact : Space.page, child: CallTile(call: _calls[i])),
                              ),
                      ),
                    ),
    );
  }
}
