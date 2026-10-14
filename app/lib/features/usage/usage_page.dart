import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../theme/tokens.dart';
import '../../widgets/charts.dart';
import '../../widgets/states.dart';

/// What each ledger `purpose` means to the user.
const kUsagePurposes = <String, (String, IconData)>{
  'chat': ('对话', Icons.chat_bubble_outline_rounded),
  'timeline': ('大纲', Icons.view_timeline_outlined),
  'vision': ('识图', Icons.image_search_outlined),
  'title': ('标题', Icons.title_rounded),
  'test': ('连接测试', Icons.network_check_rounded),
  'task': ('定时任务', Icons.schedule_rounded),
  'quiz': ('出题', Icons.quiz_outlined),
};

String purposeLabel(String p) => kUsagePurposes[p]?.$1 ?? p;

enum UsageRange {
  week('7 天', 7),
  month('30 天', 30),
  quarter('90 天', 90),
  year('今年', 0);

  const UsageRange(this.label, this.days);
  final String label;
  final int days;

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
      body = ErrorState(error: _error ?? '没有数据', onRetry: _load);
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
                  const Padding(
                    padding: EdgeInsets.only(top: Space.xxl),
                    child: EmptyState(
                      icon: Icons.insights_outlined,
                      title: '这段时间没有用量',
                      body: '和助手对话、生成大纲或识图后，这里会按天统计 token 和估算费用。',
                    ),
                  )
                else ...[
                  _section(context, title: '每日用量', trailing: _chartControls(), child: _chart(context, s)),
                  const SizedBox(height: Space.lg),
                  _section(context, title: '明细', trailing: _breakdownControl(), child: _breakdown(context, s)),
                  const SizedBox(height: Space.lg),
                  _section(
                    context,
                    title: '最近调用',
                    trailing: TextButton(onPressed: () => _openCalls(_rangeFilter(title: '${_range.label}内的调用')), child: const Text('全部')),
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
        title: const Text('用量与费用'),
        bottom: _loading && s != null ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2)) : null,
        actions: [IconButton(tooltip: '刷新', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded))],
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
          segments: const [ButtonSegment(value: _Metric.cost, label: Text('费用')), ButtonSegment(value: _Metric.tokens, label: Text('Tokens'))],
          selected: {_metric},
          onSelectionChanged: (v) => setState(() => _metric = v.first),
        ),
        const SizedBox(width: Space.xs),
        IconButton(
          tooltip: _table ? '图表' : '表格',
          isSelected: _table,
          onPressed: () => setState(() => _table = !_table),
          icon: const Icon(Icons.table_rows_outlined),
          selectedIcon: const Icon(Icons.bar_chart_rounded),
        ),
      ]);

  Widget _breakdownControl() => SegmentedButton<_Breakdown>(
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        segments: const [
          ButtonSegment(value: _Breakdown.model, label: Text('模型')),
          ButtonSegment(value: _Breakdown.purpose, label: Text('用途')),
          ButtonSegment(value: _Breakdown.session, label: Text('对话')),
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
        ? [ChartSeries('估算费用', cs.primary)]
        : [
            ChartSeries('输入', cs.primary),
            ChartSeries('缓存命中', Color.alphaBlend(cs.primary.withValues(alpha: 0.42), bg)),
            ChartSeries('输出', cs.tertiary),
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
        semanticLabel: '每日${_metric == _Metric.cost ? '估算费用' : 'token 用量'}柱状图，可切换为表格查看',
      ),
    ]);
  }

  Widget _breakdown(BuildContext context, Map<String, dynamic> s) {
    final key = switch (_by) { _Breakdown.model => 'by_model', _Breakdown.purpose => 'by_purpose', _Breakdown.session => 'by_session' };
    final rows = jsonList(s[key]).whereType<Map>().take(12).toList();
    if (rows.isEmpty) return const Padding(padding: EdgeInsets.all(Space.lg), child: Text('没有记录'));
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
            _Breakdown.session => ((r['title'] as String?) ?? '已删除的对话', '', null),
          };
          final v = byCost ? _n(r, 'cost') : _allTokens(r);
          return RankedRow(
            leading: icon == null ? null : Icon(icon, size: 20, color: cs.onSurfaceVariant),
            label: label,
            sublabel: [
              if (hint.isNotEmpty) hint,
              '${fmtCompact(_n(r, 'calls'))} 次',
              '输入 ${fmtCompact(_n(r, 'input') + _n(r, 'cache_read') + _n(r, 'cache_write'))}',
              '输出 ${fmtCompact(_n(r, 'output'))}',
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
    final span = range == UsageRange.year ? '去年同期' : '前 ${range.days} 天';
    if (before == 0) return now == 0 ? null : '$span无用量';
    final pct = (now - before) / before * 100;
    if (pct.abs() < 0.5) return '与$span持平';
    return '比$span${pct > 0 ? '多' : '少'} ${pct.abs().round()}%';
  }

  @override
  Widget build(BuildContext context) {
    final prompt = _n(totals, 'input') + _n(totals, 'cache_read');
    final hit = prompt == 0 ? null : _n(totals, 'cache_read') / prompt;
    final errors = _n(totals, 'errors');
    return StatGrid(children: [
      StatTile(icon: Icons.payments_outlined, label: '估算费用', value: fmtUsd(_n(totals, 'cost')), note: _delta(_n(totals, 'cost'), _n(previous, 'cost'))),
      StatTile(
        icon: Icons.data_usage_rounded,
        label: 'Tokens',
        value: fmtCompact(_allTokens(totals)),
        note: '输入 ${fmtCompact(prompt + _n(totals, 'cache_write'))} · 输出 ${fmtCompact(_n(totals, 'output'))}',
      ),
      StatTile(
        icon: Icons.swap_vert_rounded,
        label: '调用次数',
        value: fmtCompact(_n(totals, 'calls')),
        note: errors > 0 ? '失败 ${fmtCompact(errors)} 次' : _delta(_n(totals, 'calls'), _n(previous, 'calls')),
      ),
      StatTile(
        icon: Icons.bolt_outlined,
        label: '缓存命中率',
        value: hit == null ? '—' : '${(hit * 100).toStringAsFixed(hit < 0.1 ? 1 : 0)}%',
        note: hit == null ? null : '命中 ${fmtCompact(_n(totals, 'cache_read'))} tokens',
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
    if (rows.isEmpty) return const Text('没有记录');
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 36,
        dataRowMinHeight: 32,
        dataRowMaxHeight: 36,
        columns: [
          const DataColumn(label: Text('日期')),
          for (final s in series) DataColumn(label: Text(s.label), numeric: true),
          if (series.length > 1) const DataColumn(label: Text('合计'), numeric: true),
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
    );
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
                Text('失败', style: tt.labelSmall?.copyWith(color: cs.error)),
              ],
            ]),
            const SizedBox(height: 2),
            Text(
              [
                '${fmtCompact(_n(call, 'input') + cached + _n(call, 'cache_write'))}${cached > 0 ? '（缓存 ${fmtCompact(cached)}）' : ''} → ${fmtCompact(_n(call, 'output'))}',
                if (ms > 0) '${(ms / 1000).toStringAsFixed(1)}s',
                if (ttft != null) '首字 ${(ttft / 1000).toStringAsFixed(1)}s',
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
      final before = _calls.isEmpty ? null : '${_calls.last['ts']}';
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
                  ? const EmptyState(icon: Icons.receipt_long_outlined, title: '没有调用记录')
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
