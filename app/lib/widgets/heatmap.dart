import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';

/// Midnight of [d]'s local day.
DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

/// Monday of the week containing [d].
DateTime weekStart(DateTime d) => dayOf(d).subtract(Duration(days: d.weekday - 1));

/// Week columns from [from] to [to], Monday first. Days outside the range are
/// null so a column always has seven slots.
List<List<DateTime?>> heatWeeks(DateTime from, DateTime to) {
  final a = dayOf(from), b = dayOf(to);
  final weeks = <List<DateTime?>>[];
  for (var w = weekStart(a); !w.isAfter(b); w = DateTime(w.year, w.month, w.day + 7)) {
    weeks.add([
      for (var i = 0; i < 7; i++)
        switch (DateTime(w.year, w.month, w.day + i)) {
          final d when d.isBefore(a) || d.isAfter(b) => null,
          final d => d,
        },
    ]);
  }
  return weeks;
}

/// Upper bounds of levels 1–3: the quartiles of the non-zero values, so light
/// and heavy users both see contrast. Level 4 is anything above the last.
List<double> heatThresholds(Iterable<num> values) {
  final v = values.where((x) => x > 0).map((x) => x.toDouble()).toList()..sort();
  if (v.isEmpty) return const [0, 0, 0];
  double q(double p) {
    final i = (v.length - 1) * p;
    final lo = i.floor(), hi = i.ceil();
    return v[lo] + (v[hi] - v[lo]) * (i - lo);
  }

  return [q(.25), q(.5), q(.75)];
}

/// 0 for no activity, else 1–4 against [thresholds].
int heatLevel(num value, List<double> thresholds) {
  if (value <= 0) return 0;
  for (var i = 0; i < 3; i++) {
    if (value <= thresholds[i]) return i + 1;
  }
  return 4;
}

/// The five cell colors: an empty step, then four steps toward primary,
/// computed from the active scheme so dark mode gets its own ramp.
List<Color> heatColors(ColorScheme cs) => [
      cs.surfaceContainerHighest,
      for (final t in const [.3, .52, .76, 1.0]) Color.lerp(cs.surfaceContainerHighest, cs.primary, t)!,
    ];

/// Contribution-style calendar heatmap: one column per week, Monday on top.
class ContributionHeatmap extends StatefulWidget {
  const ContributionHeatmap({
    super.key,
    required this.from,
    required this.to,
    required this.value,
    required this.describe,
    this.tooltip,
    this.onTap,
    this.today,
    this.cell = 12,
  });

  final DateTime from, to;

  /// Intensity of a day; the level comes from its quartile in the range.
  final num Function(DateTime day) value;

  /// Screen-reader label, e.g. "10月14日，学习 42 分钟".
  final String Function(DateTime day) describe;

  /// Tooltip lines: a title and detail rows.
  final (String, List<String>) Function(DateTime day)? tooltip;
  final ValueChanged<DateTime>? onTap;

  /// Days after this are left blank. Defaults to now.
  final DateTime? today;
  final double cell;

  static const gap = 3.0;
  static const labelWidth = 28.0;
  static const monthHeight = 18.0;

  /// Columns that fit [width] at [cell] size.
  static int weeksFor(double width, {double cell = 12}) =>
      ((width - labelWidth + gap) / (cell + gap)).floor().clamp(1, 53);

  @override
  State<ContributionHeatmap> createState() => _ContributionHeatmapState();
}

class _ContributionHeatmapState extends State<ContributionHeatmap> {
  final _focus = FocusNode(debugLabel: 'heatmap');
  (int, int)? _hover; // (week, weekday)
  (int, int)? _focused;

  late List<List<DateTime?>> _weeks;
  late List<double> _thresholds;
  late DateTime _today;

  @override
  void initState() {
    super.initState();
    _layout();
  }

  @override
  void didUpdateWidget(ContributionHeatmap old) {
    super.didUpdateWidget(old);
    _layout();
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _layout() {
    _today = dayOf(widget.today ?? DateTime.now());
    _weeks = heatWeeks(widget.from, widget.to);
    _thresholds = heatThresholds([for (final w in _weeks) for (final d in w) if (d != null && !d.isAfter(_today)) widget.value(d)]);
    if (_hover case (final c, _) when c >= _weeks.length) _hover = null;
    if (_focused case (final c, _) when c >= _weeks.length) _focused = null;
  }

  DateTime? _at((int, int)? p) {
    if (p == null) return null;
    final d = _weeks[p.$1][p.$2];
    return d == null || d.isAfter(_today) ? null : d;
  }

  (int, int)? _hit(Offset o) {
    final step = widget.cell + ContributionHeatmap.gap;
    final x = o.dx - ContributionHeatmap.labelWidth, y = o.dy - ContributionHeatmap.monthHeight;
    if (x < 0 || y < 0) return null;
    final c = (x / step).floor(), r = (y / step).floor();
    if (c >= _weeks.length || r >= 7 || x - c * step > widget.cell || y - r * step > widget.cell) return null;
    return _at((c, r)) == null ? null : (c, r);
  }

  KeyEventResult _key(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final p = _focused ?? _todayPos();
    if (p == null) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.enter || e.logicalKey == LogicalKeyboardKey.space) {
      final d = _at(p);
      if (d != null) widget.onTap?.call(d);
      return KeyEventResult.handled;
    }
    final (dc, dr) = switch (e.logicalKey) {
      LogicalKeyboardKey.arrowLeft => (-1, 0),
      LogicalKeyboardKey.arrowRight => (1, 0),
      LogicalKeyboardKey.arrowUp => (0, -1),
      LogicalKeyboardKey.arrowDown => (0, 1),
      _ => (0, 0),
    };
    if (dc == 0 && dr == 0) return KeyEventResult.ignored;
    final n = (p.$1 + dc, p.$2 + dr);
    if (n.$1 >= 0 && n.$1 < _weeks.length && n.$2 >= 0 && n.$2 < 7 && _at(n) != null) setState(() => _focused = n);
    return KeyEventResult.handled;
  }

  (int, int)? _todayPos() {
    for (var c = _weeks.length - 1; c >= 0; c--) {
      for (var r = 6; r >= 0; r--) {
        if (_at((c, r)) != null) return (c, r);
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final step = widget.cell + ContributionHeatmap.gap;
    final width = ContributionHeatmap.labelWidth + _weeks.length * step - ContributionHeatmap.gap;
    final height = ContributionHeatmap.monthHeight + 7 * step - ContributionHeatmap.gap;
    final shown = _hover ?? (_focus.hasFocus ? _focused : null);
    final tipDay = _at(shown);

    final grid = CustomPaint(
      size: Size(width, height),
      painter: _HeatPainter(
        weeks: _weeks,
        today: _today,
        level: (d) => heatLevel(widget.value(d), _thresholds),
        describe: widget.describe,
        colors: heatColors(cs),
        cell: widget.cell,
        label: tt.labelSmall!.copyWith(color: cs.onSurfaceVariant),
        todayRing: cs.outline,
        focusRing: cs.onSurface,
        focused: _focus.hasFocus ? _focused : null,
        hover: _hover,
        textDirection: Directionality.of(context),
      ),
    );

    return Focus(
      focusNode: _focus,
      onKeyEvent: _key,
      onFocusChange: (f) => setState(() => _focused ??= f ? _todayPos() : null),
      child: MouseRegion(
        cursor: widget.onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
        onHover: (e) {
          final h = _hit(e.localPosition);
          if (h != _hover) setState(() => _hover = h);
        },
        onExit: (_) => setState(() => _hover = null),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (e) => setState(() => _hover = _hit(e.localPosition)),
          onTapUp: (e) {
            final d = _at(_hit(e.localPosition));
            if (d != null) {
              setState(() => _focused = _hit(e.localPosition));
              widget.onTap?.call(d);
            }
          },
          onTapCancel: () => setState(() => _hover = null),
          child: SizedBox(
            width: width,
            height: height,
            child: Stack(clipBehavior: Clip.none, children: [
              grid,
              if (tipDay != null && widget.tooltip != null)
                _HeatTooltip(
                  content: widget.tooltip!(tipDay),
                  anchor: Offset(ContributionHeatmap.labelWidth + shown!.$1 * step + widget.cell / 2, ContributionHeatmap.monthHeight + shown.$2 * step),
                  width: width,
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _HeatPainter extends CustomPainter {
  _HeatPainter({
    required this.weeks,
    required this.today,
    required this.level,
    required this.describe,
    required this.colors,
    required this.cell,
    required this.label,
    required this.todayRing,
    required this.focusRing,
    required this.focused,
    required this.hover,
    required this.textDirection,
  });

  final List<List<DateTime?>> weeks;
  final DateTime today;
  final int Function(DateTime) level;
  final String Function(DateTime) describe;
  final List<Color> colors;
  final double cell;
  final TextStyle label;
  final Color todayRing, focusRing;
  final (int, int)? focused, hover;
  final TextDirection textDirection;

  double get _step => cell + ContributionHeatmap.gap;

  Rect _rect(int c, int r) =>
      Rect.fromLTWH(ContributionHeatmap.labelWidth + c * _step, ContributionHeatmap.monthHeight + r * _step, cell, cell);

  void _text(Canvas canvas, String s, Offset at, {bool center = false}) {
    final tp = TextPainter(text: TextSpan(text: s, style: label), textDirection: textDirection)..layout();
    tp.paint(canvas, center ? at - Offset(0, tp.height / 2) : at);
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final (r, s) in const [(0, '周一'), (2, '周三'), (4, '周五')]) {
      _text(canvas, s, Offset(0, _rect(0, r).center.dy), center: true);
    }
    // A month label sits over the column holding that month's 1st; the first
    // column is labelled too unless a month starts right after it.
    final months = <int, int>{
      for (var c = 0; c < weeks.length; c++)
        if (weeks[c].firstWhere((d) => d?.day == 1, orElse: () => null) case final d?) c: d.month,
    };
    if (!months.containsKey(0) && !months.keys.any((c) => c < 3) && weeks.isNotEmpty) {
      months[0] = weeks[0].firstWhere((d) => d != null)!.month;
    }
    var last = -3;
    for (final c in months.keys.toList()..sort()) {
      if (c - last < 3) continue;
      _text(canvas, '${months[c]}月', Offset(_rect(c, 0).left, 0));
      last = c;
    }
    final radius = Radius.circular(math.min(3, cell / 4));
    final paint = Paint();
    for (var c = 0; c < weeks.length; c++) {
      for (var r = 0; r < 7; r++) {
        final d = weeks[c][r];
        if (d == null || d.isAfter(today)) continue;
        final rr = RRect.fromRectAndRadius(_rect(c, r), radius);
        canvas.drawRRect(rr, paint..color = colors[level(d)]..style = PaintingStyle.fill);
        if (d == today) canvas.drawRRect(rr.inflate(1), Paint()..color = todayRing..style = PaintingStyle.stroke..strokeWidth = 1.5);
      }
    }
    for (final p in [focused, hover]) {
      if (p == null) continue;
      canvas.drawRRect(RRect.fromRectAndRadius(_rect(p.$1, p.$2), radius).inflate(1.5),
          Paint()..color = focusRing..style = PaintingStyle.stroke..strokeWidth = 2);
    }
  }

  @override
  SemanticsBuilderCallback get semanticsBuilder => (size) => [
        for (var c = 0; c < weeks.length; c++)
          for (var r = 0; r < 7; r++)
            if (weeks[c][r] case final d? when !d.isAfter(today))
              CustomPainterSemantics(rect: _rect(c, r), properties: SemanticsProperties(label: describe(d), textDirection: textDirection)),
      ];

  @override
  bool shouldRepaint(_HeatPainter old) => true;

  @override
  bool shouldRebuildSemantics(_HeatPainter old) => old.weeks != weeks || old.today != today;
}

class _HeatTooltip extends StatelessWidget {
  const _HeatTooltip({required this.content, required this.anchor, required this.width});
  final (String, List<String>) content;
  final Offset anchor;
  final double width;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    const w = 176.0;
    final x = (anchor.dx - w / 2).clamp(0.0, math.max(0.0, width - w)).toDouble();
    final figs = tt.bodySmall?.copyWith(color: cs.onInverseSurface, fontFeatures: const [FontFeature.tabularFigures()]);
    return Positioned(
      left: x,
      top: anchor.dy - Space.sm,
      width: w,
      child: IgnorePointer(
        child: FractionalTranslation(
          translation: const Offset(0, -1),
          child: Container(
            padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.md, Space.sm),
            decoration: BoxDecoration(color: cs.inverseSurface, borderRadius: Corners.all(Corners.sm)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(content.$1, style: tt.labelMedium?.copyWith(color: cs.onInverseSurface)),
              for (final l in content.$2) Padding(padding: const EdgeInsets.only(top: 2), child: Text(l, style: figs)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// "少 ▢▢▢▢▢ 多" under a heatmap.
class HeatLegend extends StatelessWidget {
  const HeatLegend({super.key, this.cell = 12});
  final double cell;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant);
    return ExcludeSemantics(
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('少', style: style),
        const SizedBox(width: Space.xs),
        for (final c in heatColors(cs))
          Container(
            width: cell,
            height: cell,
            margin: const EdgeInsets.symmetric(horizontal: ContributionHeatmap.gap / 2),
            decoration: BoxDecoration(color: c, borderRadius: Corners.all(math.min(3, cell / 4))),
          ),
        const SizedBox(width: Space.xs),
        Text('多', style: style),
      ]),
    );
  }
}

/// "42 分钟" or "1 小时 5 分".
String fmtMinutes(num minutes) {
  final m = minutes.round();
  if (m < 60) return '$m 分钟';
  return m % 60 == 0 ? '${m ~/ 60} 小时' : '${m ~/ 60} 小时 ${m % 60} 分';
}

/// "10月14日"
String fmtMonthDay(DateTime d) => '${d.month}月${d.day}日';
