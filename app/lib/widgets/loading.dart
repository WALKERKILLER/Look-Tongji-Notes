import 'dart:math' as math;

import 'package:flutter/material.dart';

/// M3 Expressive loading indicator: a rounded "cookie" shape that morphs
/// between lobe counts while rotating. Use for short waits (< 5 s).
class ExpressiveLoader extends StatefulWidget {
  const ExpressiveLoader({super.key, this.size = 48, this.contained = false, this.color});
  final double size;
  final bool contained;
  final Color? color;

  @override
  State<ExpressiveLoader> createState() => _ExpressiveLoaderState();
}

class _ExpressiveLoaderState extends State<ExpressiveLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 4200))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = widget.color ?? (widget.contained ? cs.onPrimaryContainer : cs.primary);
    final indicator = RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => CustomPaint(
          size: Size.square(widget.size * (widget.contained ? 0.79 : 1)),
          painter: _MorphPainter(_c.value, fg),
        ),
      ),
    );
    final child = Semantics(label: '加载中', child: indicator);
    if (!widget.contained) return SizedBox.square(dimension: widget.size, child: Center(child: child));
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(color: cs.primaryContainer, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: child,
    );
  }
}

class _MorphPainter extends CustomPainter {
  _MorphPainter(this.t, this.color);
  final double t;
  final Color color;

  // Sequence of (lobes, amplitude) shapes, like the M3E shape set.
  static const _shapes = [(7, 0.10), (4, 0.16), (9, 0.08), (5, 0.14), (2, 0.20), (6, 0.12), (3, 0.18)];

  @override
  void paint(Canvas canvas, Size size) {
    final n = _shapes.length;
    final pos = t * n;
    final i = pos.floor() % n;
    final local = pos - pos.floor();
    // Hold each shape, then morph with an emphasized ease.
    final m = Curves.easeInOutCubicEmphasized.transform(((local - 0.45) / 0.55).clamp(0, 1));
    final a = _shapes[i], b = _shapes[(i + 1) % n];
    final center = size.center(Offset.zero);
    final base = size.shortestSide / 2 * 0.86;
    final rot = t * math.pi * 2 * 3 + m * math.pi / 3;
    final path = Path();
    const steps = 120;
    for (var k = 0; k <= steps; k++) {
      final th = k / steps * math.pi * 2;
      final ra = 1 + a.$2 * math.cos(a.$1 * th);
      final rb = 1 + b.$2 * math.cos(b.$1 * th);
      final r = base * (ra + (rb - ra) * m) / (1 + math.max(a.$2, b.$2));
      final p = center + Offset(math.cos(th + rot), math.sin(th + rot)) * r;
      k == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path..close(), Paint()..color = color..isAntiAlias = true);
  }

  @override
  bool shouldRepaint(_MorphPainter old) => old.t != t || old.color != color;
}
