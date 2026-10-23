import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/format.dart';
import '../theme/tokens.dart';
import '../l10n/l10n.dart';

/// Headline number with a label and an optional comparison line.
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.note, this.icon});
  final String label;
  final String value;
  final String? note;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.md),
      decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: Corners.all(Corners.lg)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          if (icon != null) ...[Icon(icon, size: 16, color: cs.onSurfaceVariant), const SizedBox(width: Space.xs + 2)],
          Flexible(child: Text(label, style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant), overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: Space.sm),
        Text(value, style: tt.headlineSmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]), maxLines: 1),
        if (note != null) ...[
          const SizedBox(height: Space.xxs),
          Text(note!, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ]),
    );
  }
}

/// Responsive grid of [StatTile]s: four across on wide windows, two on compact.
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth >= 640 ? 4 : 2;
        final w = (c.maxWidth - Space.md * (cols - 1)) / cols;
        return Wrap(spacing: Space.md, runSpacing: Space.md, children: [for (final t in children) SizedBox(width: w, child: t)]);
      });
}

class ChartSeries {
  const ChartSeries(this.label, this.color);
  final String label;
  final Color color;
}

/// Color swatch + label pairs shown above a multi-series chart.
class ChartLegend extends StatelessWidget {
  const ChartLegend({super.key, required this.series});
  final List<ChartSeries> series;
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Wrap(spacing: Space.lg, runSpacing: Space.xs, children: [
      for (final s in series)
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: s.color, borderRadius: Corners.all(3))),
          const SizedBox(width: Space.xs + 2),
          Text(s.label, style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
        ]),
    ]);
  }
}

/// Stacked daily bars with one y-axis, a recessive grid and a per-day tooltip
/// on hover or press. `values[day][series]`; series stack bottom-up.
class DailyBarChart extends StatefulWidget {
  const DailyBarChart({
    super.key,
    required this.days,
    required this.values,
    required this.series,
    required this.format,
    this.height = 208,
    this.semanticLabel,
    this.background,
  });
  final List<DateTime> days;
  final List<List<double>> values;
  final List<ChartSeries> series;
  final String Function(double) format;
  final double height;
  final String? semanticLabel;

  /// Surface the chart sits on; stacked segments are separated by gaps of this color.
  final Color? background;

  @override
  State<DailyBarChart> createState() => _DailyBarChartState();
}

class _DailyBarChartState extends State<DailyBarChart> {
  int? _hover;

  static const _axisGap = Space.sm;
  static const _bottom = 22.0;

  double _niceMax(double v) {
    if (v <= 0) return 1;
    final p = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
    for (final m in [1, 2, 2.5, 5, 10]) {
      if (v <= m * p) return m * p;
    }
    return 10 * p;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final totals = [for (final d in widget.values) d.fold<double>(0, (a, b) => a + b)];
    final top = _niceMax(totals.fold<double>(0, math.max));
    final labelStyle = tt.labelSmall!.copyWith(color: cs.onSurfaceVariant, fontFeatures: const [FontFeature.tabularFigures()]);
    final axisW = [0.0, top / 2, top]
            .map((v) => (TextPainter(text: TextSpan(text: widget.format(v), style: labelStyle), textDirection: TextDirection.ltr)..layout()).width)
            .reduce(math.max) +
        _axisGap;

    return Semantics(
      label: widget.semanticLabel,
      child: SizedBox(
        height: widget.height,
        child: LayoutBuilder(builder: (context, c) {
          final plotW = c.maxWidth - axisW;
          final n = widget.days.length;
          final slot = n == 0 ? 0.0 : plotW / n;
          int? indexAt(Offset p) {
            if (n == 0 || p.dx < axisW) return null;
            return ((p.dx - axisW) / slot).floor().clamp(0, n - 1);
          }

          final h = _hover;
          return MouseRegion(
            onHover: (e) => setState(() => _hover = indexAt(e.localPosition)),
            onExit: (_) => setState(() => _hover = null),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (e) => setState(() => _hover = indexAt(e.localPosition)),
              onHorizontalDragUpdate: (e) => setState(() => _hover = indexAt(e.localPosition)),
              child: Stack(clipBehavior: Clip.none, children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _BarsPainter(
                      values: widget.values,
                      totals: totals,
                      days: widget.days,
                      colors: [for (final s in widget.series) s.color],
                      top: top,
                      axisW: axisW,
                      bottom: _bottom,
                      hover: h,
                      grid: cs.outlineVariant,
                      band: cs.onSurface.withValues(alpha: 0.06),
                      gap: widget.background ?? cs.surfaceContainerLow,
                      labelStyle: labelStyle,
                      format: widget.format,
                    ),
                  ),
                ),
                if (h != null && h < n)
                  _Tooltip(
                    left: axisW + slot * h + slot / 2,
                    width: c.maxWidth,
                    title: fmtDayLabel(widget.days[h]),
                    rows: [
                      for (var i = widget.series.length - 1; i >= 0; i--) (widget.series[i], widget.format(widget.values[h][i])),
                    ],
                    total: widget.series.length > 1 ? widget.format(totals[h]) : null,
                  ),
              ]),
            ),
          );
        }),
      ),
    );
  }
}

class _Tooltip extends StatelessWidget {
  const _Tooltip({required this.left, required this.width, required this.title, required this.rows, this.total});
  final double left;
  final double width;
  final String title;
  final List<(ChartSeries, String)> rows;
  final String? total;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    const w = 168.0;
    final x = (left + Space.md + w > width ? left - Space.md - w : left + Space.md).clamp(0.0, math.max(0.0, width - w)).toDouble();
    final figs = tt.bodySmall?.copyWith(color: cs.onInverseSurface, fontFeatures: const [FontFeature.tabularFigures()]);
    return Positioned(
      left: x,
      top: 0,
      width: w,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.md, Space.sm),
          decoration: BoxDecoration(color: cs.inverseSurface, borderRadius: Corners.all(Corners.sm)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(title, style: tt.labelMedium?.copyWith(color: cs.onInverseSurface)),
            const SizedBox(height: Space.xs),
            for (final (s, v) in rows)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: s.color, borderRadius: Corners.all(2))),
                  const SizedBox(width: Space.xs + 2),
                  Expanded(child: Text(s.label, style: figs)),
                  Text(v, style: figs),
                ]),
              ),
            if (total != null)
              Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: Row(children: [
                  Expanded(child: Text(l10n.chartTotal, style: figs?.copyWith(fontWeight: FontWeight.w600))),
                  Text(total!, style: figs?.copyWith(fontWeight: FontWeight.w600)),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.values,
    required this.totals,
    required this.days,
    required this.colors,
    required this.top,
    required this.axisW,
    required this.bottom,
    required this.hover,
    required this.grid,
    required this.band,
    required this.gap,
    required this.labelStyle,
    required this.format,
  });
  final List<List<double>> values;
  final List<double> totals;
  final List<DateTime> days;
  final List<Color> colors;
  final double top;
  final double axisW;
  final double bottom;
  final int? hover;
  final Color grid;
  final Color band;
  final Color gap;
  final TextStyle labelStyle;
  final String Function(double) format;

  void _text(Canvas c, String s, Offset at, {bool right = false, bool center = false}) {
    final tp = TextPainter(text: TextSpan(text: s, style: labelStyle), textDirection: TextDirection.ltr)..layout();
    final dx = right ? at.dx - tp.width : center ? at.dx - tp.width / 2 : at.dx;
    tp.paint(c, Offset(dx, at.dy - tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final plotH = size.height - bottom;
    final plotW = size.width - axisW;
    final n = values.length;
    double y(double v) => plotH - v / top * (plotH - 6);

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final v in [0.0, top / 2, top]) {
      final yy = y(v).roundToDouble() + 0.5;
      canvas.drawLine(Offset(axisW, yy), Offset(size.width, yy), gridPaint..color = v == 0 ? grid : grid.withValues(alpha: 0.5));
      _text(canvas, format(v), Offset(axisW - _DailyBarChartState._axisGap, yy), right: true);
    }
    if (n == 0) return;
    final slot = plotW / n;
    final barW = (slot * 0.62).clamp(2.0, 18.0);
    if (hover != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(axisW + slot * hover!, 0, slot, plotH), const Radius.circular(4)),
        Paint()..color = band,
      );
    }
    for (var i = 0; i < n; i++) {
      final cx = axisW + slot * i + slot / 2;
      var base = plotH;
      final last = values[i].lastIndexWhere((v) => v > 0);
      for (var s = 0; s < values[i].length; s++) {
        final v = values[i][s];
        if (v <= 0) continue;
        final hgt = math.max(1.0, v / top * (plotH - 6));
        final rect = Rect.fromLTWH(cx - barW / 2, base - hgt, barW, hgt);
        final r = Radius.circular(math.min(4, barW / 2));
        final rr = s == last ? RRect.fromRectAndCorners(rect, topLeft: r, topRight: r) : RRect.fromRectAndCorners(rect);
        canvas.drawRRect(rr, Paint()..color = colors[s % colors.length]);
        base -= hgt;
        // 2 px surface gap between stacked segments.
        if (s != last && hgt > 3) {
          canvas.drawRect(Rect.fromLTWH(cx - barW / 2, base, barW, 2), Paint()..color = gap);
        }
      }
    }
    // Date labels, spaced at least 56 px apart; month starts preferred on long ranges.
    final every = math.max(1, (56 / slot).ceil());
    final long = n > 62;
    for (var i = 0; i < n; i++) {
      final d = days[i];
      final show = long ? d.day == 1 : (i % every == 0);
      if (!show) continue;
      _text(canvas, long ? l10n.dateMonth(d.month) : '${d.month}/${d.day}', Offset(axisW + slot * i + slot / 2, plotH + bottom / 2 + 2), center: true);
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.values != values || old.hover != hover || old.top != top || old.colors != colors || old.grid != grid;
}

/// A ranked row: label, thin proportional bar, and right-aligned figures.
class RankedRow extends StatelessWidget {
  const RankedRow({super.key, required this.label, required this.fraction, required this.trailing, this.sublabel, this.onTap, this.leading});
  final String label;
  final String? sublabel;
  final double fraction;
  final String trailing;
  final Widget? leading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      borderRadius: Corners.all(Corners.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.sm + 2),
        child: Row(children: [
          if (leading != null) ...[leading!, const SizedBox(width: Space.md)],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(label, style: tt.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: Space.md),
                Text(trailing, style: tt.bodyMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
              ]),
              if (sublabel != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(sublabel!, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontFeatures: const [FontFeature.tabularFigures()]),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              const SizedBox(height: Space.xs + 2),
              ClipRRect(
                borderRadius: Corners.all(Corners.full),
                child: SizedBox(
                  height: 4,
                  child: Stack(children: [
                    Positioned.fill(child: ColoredBox(color: cs.surfaceContainerHighest)),
                    FractionallySizedBox(widthFactor: fraction.clamp(0.0, 1.0), child: ColoredBox(color: cs.primary)),
                  ]),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
