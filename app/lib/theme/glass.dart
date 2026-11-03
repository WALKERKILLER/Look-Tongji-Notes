import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'tokens.dart';

/// The app's glass material: translucent, frosted chrome that floats over
/// content (the phone dock, canvas toolbars, the canvas composer). Pages,
/// cards and lists stay tonal Material 3 surfaces; glass is only for what
/// floats above them, so it reads as a layer rather than a texture.
///
/// Design notes, not code, from FlClash's surface guidance
/// (https://github.com/chen08209/FlClash, .agents/surfaces.md, read
/// 2026-11-03): surfaces separate by a step in lightness rather than a
/// border, glass replaces fills only on floating chrome, the tint comes
/// from the scheme's container surface in dark mode and from white in
/// light mode, and the shadow is drawn outside the pane so it never shows
/// through. The frost, rim and sheen here are drawn independently.
@immutable
class GlassStyle extends ThemeExtension<GlassStyle> {
  const GlassStyle({this.enabled = true});

  /// False under 液态玻璃 off or high contrast: panes become opaque tonal
  /// surfaces with the same shape and rim.
  final bool enabled;

  static GlassStyle of(BuildContext context) =>
      Theme.of(context).extension<GlassStyle>() ?? const GlassStyle();

  @override
  GlassStyle copyWith({bool? enabled}) =>
      GlassStyle(enabled: enabled ?? this.enabled);

  @override
  GlassStyle lerp(GlassStyle? other, double t) =>
      t < .5 ? this : (other ?? this);
}

/// How much a pane lifts off what is under it.
enum GlassDepth {
  /// Toolbars and docks: thin frost, light tint.
  bar,

  /// Message bubbles and panels holding text: denser tint for reading.
  panel,

  /// Menus and the composer: the densest, nearly opaque.
  float,
}

/// A frosted pane in the shape of [radius] (a continuous superellipse).
/// Inside a [BackdropGroup] the panes share one backdrop capture.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.radius = Corners.xl,
    this.depth = GlassDepth.bar,
    this.padding = EdgeInsets.zero,
    this.tint,
    this.shadow = true,
    this.selected = false,
  });

  final Widget child;
  final double radius;
  final GlassDepth depth;
  final EdgeInsetsGeometry padding;

  /// Replaces the neutral tint, e.g. with primary container for the user's
  /// own messages.
  final Color? tint;
  final bool shadow;

  /// Draws the rim in the primary colour (a drop target accepting, a pane in focus).
  final bool selected;

  /// The fill the pane paints over its frost; tests compose it over the
  /// backdrop to measure contrast.
  static Color fillOf(
    BuildContext context, {
    GlassDepth depth = GlassDepth.bar,
    Color? tint,
  }) {
    final cs = Theme.of(context).colorScheme;
    final dark = cs.brightness == Brightness.dark;
    final on = GlassStyle.of(context).enabled;
    final base =
        tint ??
        (dark
            ? Color.lerp(cs.surfaceContainerHigh, cs.surfaceBright, .35)!
            : cs.surfaceContainerLowest);
    if (!on) return Color.alphaBlend(base, cs.surface);
    final alpha = switch (depth) {
      GlassDepth.bar => dark ? .58 : .62,
      GlassDepth.panel => dark ? .74 : .78,
      GlassDepth.float => dark ? .86 : .88,
    };
    return base.withValues(alpha: alpha);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = cs.brightness == Brightness.dark;
    final on = GlassStyle.of(context).enabled;
    final shape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(radius),
    );
    Widget pane = CustomPaint(
      foregroundPainter: _Rim(
        shape: shape,
        dark: dark,
        accent: selected ? cs.primary : null,
      ),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          shape: shape,
          color: fillOf(context, depth: depth, tint: tint),
        ),
        // Ink paints on the pane, above the frost, not on the page below.
        child: Material(
          type: MaterialType.transparency,
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
    if (on) {
      final sigma = switch (depth) {
        GlassDepth.bar => 16.0,
        GlassDepth.panel => 22.0,
        GlassDepth.float => 28.0,
      };
      pane = ClipPath(
        clipper: ShapeBorderClipper(shape: shape),
        child: BackdropFilter.grouped(
          filter: ui.ImageFilter.compose(
            outer: _saturate(dark ? 1.5 : 1.8),
            inner: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          ),
          child: pane,
        ),
      );
    }
    if (!shadow) return pane;
    return CustomPaint(
      painter: _OuterShadow(
        shape: shape,
        dark: dark,
        deep: depth != GlassDepth.bar,
      ),
      child: pane,
    );
  }
}

/// Saturation as a colour matrix (luminance weights from Rec. 709).
ui.ColorFilter _saturate(double s) {
  const r = .2126, g = .7152, b = .0722;
  final i = 1 - s;
  return ui.ColorFilter.matrix(<double>[
    r * i + s, g * i, b * i, 0, 0, //
    r * i, g * i + s, b * i, 0, 0,
    r * i, g * i, b * i + s, 0, 0,
    0, 0, 0, 1, 0,
  ]);
}

/// A light catching the upper edge, fading along the sides, and a hairline
/// that keeps the pane's edge on light content.
class _Rim extends CustomPainter {
  _Rim({required this.shape, required this.dark, this.accent});
  final ShapeBorder shape;
  final bool dark;
  final Color? accent;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = shape.getInnerPath(rect.deflate(.5));
    canvas.drawPath(
      shape.getOuterPath(rect),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .6
        ..color = Colors.black.withValues(alpha: dark ? .5 : .07),
    );
    if (accent != null) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = accent!,
      );
      return;
    }
    final light = Colors.white.withValues(alpha: dark ? .2 : .85);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            light,
            light.withValues(alpha: 0),
            Colors.white.withValues(alpha: dark ? .05 : .3),
          ],
          stops: const [0, .55, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_Rim o) =>
      o.dark != dark || o.accent != accent || o.shape != shape;
}

/// The pane's shadow, clipped to outside the pane so the glass stays clear.
class _OuterShadow extends CustomPainter {
  _OuterShadow({required this.shape, required this.dark, required this.deep});
  final ShapeBorder shape;
  final bool dark, deep;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final outline = shape.getOuterPath(rect);
    canvas.save();
    canvas.clipPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(rect.inflate(64)),
        outline,
      ),
    );
    final a = dark ? .42 : .1;
    canvas.drawPath(
      outline.shift(Offset(0, deep ? 10 : 6)),
      Paint()
        ..color = Colors.black.withValues(alpha: a)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, deep ? 18 : 12),
    );
    canvas.drawPath(
      outline.shift(const Offset(0, 1)),
      Paint()
        ..color = Colors.black.withValues(alpha: a * .6)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OuterShadow o) =>
      o.dark != dark || o.deep != deep || o.shape != shape;
}
