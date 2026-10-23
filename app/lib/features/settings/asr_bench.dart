import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

/// One measure on the board; shorter bars are always better.
class BenchMetric {
  const BenchMetric({required this.label, required this.hint, required this.format, required this.source});
  final String label;
  final String hint;
  final String Function(double) format;

  /// Where the numbers come from, shown in the footnote and tooltips.
  final String source;
}

class BenchRow {
  const BenchRow({required this.id, required this.name, required this.values, this.tag});
  final String id;
  final String name;

  /// One value per metric; null when it was not measured.
  final List<double?> values;
  final String? tag;
}

/// Benchmark board for choosing a model: one row per model and one small
/// bar chart per measure, each with its own scale, sorted by the chosen
/// measure. On narrow windows only the chosen measure is drawn.
class AsrBenchBoard extends StatefulWidget {
  const AsrBenchBoard({super.key, required this.metrics, required this.rows, this.selected, this.onSelect, this.animate = true});
  final List<BenchMetric> metrics;
  final List<BenchRow> rows;
  final String? selected;
  final ValueChanged<String>? onSelect;
  final bool animate;

  @override
  State<AsrBenchBoard> createState() => _AsrBenchBoardState();
}

class _AsrBenchBoardState extends State<AsrBenchBoard> {
  int _sort = 0;
  String? _hover;

  static double _niceMax(double v) {
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
    final rows = [...widget.rows]..sort((a, b) => (a.values[_sort] ?? double.infinity).compareTo(b.values[_sort] ?? double.infinity));
    final maxes = [
      for (var m = 0; m < widget.metrics.length; m++) _niceMax(widget.rows.map((r) => r.values[m] ?? 0).fold<double>(0, math.max)),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 620;
        final shown = wide ? [for (var i = 0; i < widget.metrics.length; i++) i] : [_sort];
        final nameW = wide ? 168.0 : math.min(140.0, c.maxWidth * 0.38);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                segments: [
                  for (var i = 0; i < widget.metrics.length; i++)
                    ButtonSegment(value: i, label: Text(wide ? '按${widget.metrics[i].label}' : widget.metrics[i].label)),
                ],
                selected: {_sort},
                onSelectionChanged: (s) => setState(() => _sort = s.first),
              ),
            ),
            const SizedBox(height: Space.md),
            Row(
              children: [
                SizedBox(width: nameW),
                for (final m in shown)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: Space.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.metrics[m].label,
                            style: tt.labelMedium?.copyWith(
                              color: m == _sort ? cs.onSurface : cs.onSurfaceVariant,
                              fontWeight: m == _sort ? FontWeight.w600 : null,
                            ),
                          ),
                          Text(widget.metrics[m].hint, style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: Space.xs),
            for (final r in rows) _row(context, r, shown, maxes, nameW),
            const SizedBox(height: Space.sm),
            for (final m in shown)
              Text(
                '${widget.metrics[m].label}：${widget.metrics[m].source}',
                style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant, height: 1.5),
              ),
          ],
        );
      },
    );
  }

  Widget _row(BuildContext context, BenchRow r, List<int> shown, List<double> maxes, double nameW) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final sel = r.id == widget.selected;
    final hover = r.id == _hover;
    final summary = [
      for (var m = 0; m < widget.metrics.length; m++)
        '${widget.metrics[m].label} ${r.values[m] == null ? '未测' : widget.metrics[m].format(r.values[m]!)}',
    ].join('，');
    final valueStyle = tt.labelSmall?.copyWith(color: cs.onSurface, fontFeatures: const [FontFeature.tabularFigures()]);
    return Semantics(
      button: widget.onSelect != null,
      selected: sel,
      label: '${r.name}，$summary',
      excludeSemantics: true,
      child: Tooltip(
        message: '${r.name}\n$summary',
        waitDuration: const Duration(milliseconds: 400),
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = r.id),
          onExit: (_) => setState(() => _hover = null),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onSelect == null ? null : () => widget.onSelect!(r.id),
            child: AnimatedContainer(
              duration: Motion.short4,
              curve: Motion.standard,
              margin: const EdgeInsets.only(bottom: Space.xxs),
              padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.sm),
              decoration: BoxDecoration(
                color: sel ? cs.secondaryContainer : (hover ? cs.surfaceContainerHighest : Colors.transparent),
                borderRadius: Corners.all(Corners.md),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: nameW - Space.sm,
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            r.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tt.bodyMedium?.copyWith(
                              color: sel ? cs.onSecondaryContainer : cs.onSurface,
                              fontWeight: sel ? FontWeight.w600 : FontWeight.w500,
                            ),
                          ),
                        ),
                        if (r.tag != null) ...[
                          const SizedBox(width: Space.xs),
                          Icon(Icons.star_rounded, size: 14, color: cs.primary, semanticLabel: r.tag),
                        ],
                      ],
                    ),
                  ),
                  for (final m in shown)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: Space.md),
                        child: LayoutBuilder(
                          builder: (context, c) {
                            final v = r.values[m];
                            final label = v == null ? '未测' : widget.metrics[m].format(v);
                            final lw = (TextPainter(
                              text: TextSpan(text: label, style: valueStyle),
                              textDirection: TextDirection.ltr,
                            )..layout()).width;
                            final track = math.max(0.0, c.maxWidth - lw - Space.sm);
                            final w = v == null ? 0.0 : math.max(4.0, track * (v / maxes[m]).clamp(0.0, 1.0));
                            return Row(
                              children: [
                                TweenAnimationBuilder<double>(
                                  tween: Tween(end: w),
                                  duration: widget.animate ? Motion.medium2 : Duration.zero,
                                  curve: Motion.emphasized,
                                  builder: (_, x, _) => Container(
                                    width: x,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: cs.primary,
                                      borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: Space.sm),
                                Text(label, style: v == null ? valueStyle?.copyWith(color: cs.onSurfaceVariant) : valueStyle),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
