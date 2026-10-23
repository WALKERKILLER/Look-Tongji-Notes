import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/models.dart';
import '../theme/tokens.dart';
import 'organic_shapes.dart';
import '../l10n/l10n.dart';

/// Stable per-course tonal palette: user color if set, else hashed hue.
ColorScheme courseScheme(BuildContext context, Course c) {
  final b = Theme.of(context).brightness;
  Color seed;
  if (c.color.startsWith('#') && c.color.length == 7) {
    seed = Color(int.parse('FF${c.color.substring(1)}', radix: 16));
  } else {
    var h = 0;
    for (final r in c.rawTitle.runes) {
      h = (h * 31 + r) & 0x7fffffff;
    }
    seed = HSLColor.fromAHSL(1, (h % 360).toDouble(), 0.45, 0.45).toColor();
  }
  return ColorScheme.fromSeed(seedColor: seed, brightness: b, dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot);
}

/// Small organic badge for a course: its signature shape with a nested accent.
class CourseGlyph extends StatelessWidget {
  const CourseGlyph({super.key, required this.course, this.size = 48, this.hover = false});
  final Course course;
  final double size;
  final bool hover;
  @override
  Widget build(BuildContext context) {
    final s = courseScheme(context, course);
    final spec = CourseArtSpec.of(course.id.isEmpty ? course.rawTitle : course.id);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: hover ? 1 : 0),
      duration: Motion.long2,
      curve: Motion.emphasized,
      builder: (_, t, _) => CustomPaint(size: Size.square(size), painter: _GlyphPainter(spec, s, t)),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.spec, this.s, this.t);
  final CourseArtSpec spec;
  final ColorScheme s;
  final double t;
  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawPath(shapePath(morphRadii(spec.main, spec.partner, t), r, rotation: spec.rot + t * 0.5), Paint()..color = spec.containerOf(s));
    final inner = Rect.fromCenter(center: r.center, width: size.width * 0.42, height: size.height * 0.42);
    canvas.drawPath(shapePath(shapeRadii(spec.accent), inner, rotation: spec.accentRot - t * 0.8), Paint()..color = spec.fillOf(s));
  }

  @override
  bool shouldRepaint(_GlyphPainter o) => o.t != t || o.s != s || o.spec != spec;
}

/// Deterministic recipe for a course's generative cover, seeded by its id.
class CourseArtSpec {
  CourseArtSpec._(this.seed);
  final int seed;
  late final OrganicShape main, partner, accent;
  late final int layout, texture, tone;
  late final double rot, accentRot, jitter;
  late final List<(OrganicShape, double, double, double, int)> cluster; // shape, x, y, size, colour

  static final _memo = <String, CourseArtSpec>{};

  factory CourseArtSpec.of(String key) => _memo.putIfAbsent(key, () {
        var h = 0x811c9dc5;
        for (final c in key.codeUnits) {
          h = ((h ^ c) * 0x01000193) & 0xffffffff;
        }
        return CourseArtSpec._(h).._build();
      });

  // Shapes that read well as the large hero form, and softer partners.
  static const _heroes = [
    OrganicShape.cookie9, OrganicShape.cookie12, OrganicShape.clover4, OrganicShape.clover8, OrganicShape.sunny,
    OrganicShape.verySunny, OrganicShape.softBurst, OrganicShape.flower, OrganicShape.puffy, OrganicShape.cookie6,
    OrganicShape.pentagon, OrganicShape.gem, OrganicShape.arch, OrganicShape.squircle, OrganicShape.cookie7,
  ];
  static const _accents = [
    OrganicShape.circle, OrganicShape.pill, OrganicShape.diamond, OrganicShape.triangle, OrganicShape.cookie4,
    OrganicShape.oval, OrganicShape.heart, OrganicShape.squircle, OrganicShape.clover4,
  ];

  void _build() {
    final r = math.Random(seed);
    main = _heroes[r.nextInt(_heroes.length)];
    var p = _heroes[r.nextInt(_heroes.length)];
    if (p == main) p = OrganicShape.circle;
    partner = p;
    accent = _accents[r.nextInt(_accents.length)];
    layout = r.nextInt(4);
    texture = r.nextInt(4);
    tone = r.nextInt(3);
    rot = r.nextDouble() * math.pi;
    accentRot = r.nextDouble() * math.pi;
    jitter = r.nextDouble();
    cluster = [
      for (var i = 0; i < 5; i++)
        (
          [..._heroes, ..._accents][r.nextInt(_heroes.length + _accents.length)],
          0.12 + 0.19 * i + (r.nextDouble() - 0.5) * 0.06,
          0.3 + (i.isEven ? 0.0 : 0.38) + (r.nextDouble() - 0.5) * 0.14,
          0.3 + r.nextDouble() * 0.22,
          r.nextInt(3),
        ),
    ];
  }

  Color containerOf(ColorScheme s) => [s.primaryContainer, s.tertiaryContainer, s.secondaryContainer][tone];
  Color fillOf(ColorScheme s) => [s.primary, s.tertiary, s.secondary][tone];
  Color altOf(ColorScheme s) => [s.tertiary, s.primary, s.primary][tone];
  Color onOf(ColorScheme s) => [s.onPrimaryContainer, s.onTertiaryContainer, s.onSecondaryContainer][tone];
}

/// Generative cover for a course: organic shapes, a light texture and a
/// course-tinted palette. [t] morphs the hero shape (hover/press); [spin] adds
/// a slow idle rotation (0–1 turns).
class CourseArt extends StatelessWidget {
  const CourseArt({super.key, required this.course, this.t = 0, this.spin = 0, this.layout});
  final Course course;
  final double t;
  final double spin;
  final int? layout;

  @override
  Widget build(BuildContext context) {
    final s = courseScheme(context, course);
    final spec = CourseArtSpec.of(course.id.isEmpty ? course.rawTitle : course.id);
    return RepaintBoundary(
      child: CustomPaint(painter: CourseArtPainter(spec: spec, s: s, t: t, spin: spin, layout: layout ?? spec.layout), child: const SizedBox.expand()),
    );
  }
}

class CourseArtPainter extends CustomPainter {
  CourseArtPainter({required this.spec, required this.s, required this.t, required this.spin, required this.layout});
  final CourseArtSpec spec;
  final ColorScheme s;
  final double t, spin;
  final int layout;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final bg = spec.containerOf(s);
    final fill = spec.fillOf(s);
    final alt = spec.altOf(s);
    final on = spec.onOf(s);
    canvas.drawRect(Offset.zero & size, Paint()..color = bg);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final turn = spin * 2 * math.pi;
    final mainRadii = morphRadii(spec.main, spec.partner, t);
    Rect sq(double cx, double cy, double d) => Rect.fromCenter(center: Offset(cx, cy), width: d, height: d);

    switch (layout) {
      case 0: // hero: one large form, an outlined companion and dot texture
        _dots(canvas, Rect.fromLTWH(w * 0.04, h * 0.5, w * 0.36, h * 0.46), on.withValues(alpha: 0.16), h / 14);
        canvas.drawPath(shapePath(mainRadii, sq(w * 0.68, h * 0.56, h * 1.02), rotation: spec.rot + turn + t * 0.45), Paint()..color = fill);
        canvas.drawPath(
          shapePath(shapeRadii(spec.accent), sq(w * 0.2, h * 0.3, h * (0.34 + 0.04 * t)), rotation: spec.accentRot - turn * 1.6),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1.5, h / 70)
            ..color = on.withValues(alpha: 0.55),
        );
      case 1: // pair: two overlapping forms inside faint concentric rings
        _rings(canvas, Offset(w * 0.42, h * 0.55), h * 0.2, on.withValues(alpha: 0.1), h / 9);
        canvas.drawPath(shapePath(mainRadii, sq(w * 0.4, h * 0.56, h * 0.86), rotation: spec.rot + turn + t * 0.4), Paint()..color = fill);
        canvas.drawPath(
          shapePath(shapeRadii(spec.partner == spec.main ? spec.accent : spec.accent), sq(w * 0.7, h * 0.42, h * 0.62), rotation: spec.accentRot - turn - t * 0.6),
          Paint()..color = alt.withValues(alpha: 0.88),
        );
      case 2: // cluster: a small constellation of mixed shapes
        _lines(canvas, size, on.withValues(alpha: 0.08), h / 8);
        for (var i = 0; i < spec.cluster.length; i++) {
          final (shape, x, y, d, c) = spec.cluster[i];
          final colour = [fill, alt, on.withValues(alpha: 0.22)][c];
          final radii = i == 1 ? mainRadii : shapeRadii(shape);
          canvas.drawPath(shapePath(radii, sq(w * x, h * y, h * d * (i == 1 ? 1 + 0.12 * t : 1)), rotation: spec.rot * (i + 1) + turn * (i.isEven ? 1 : -1)), Paint()..color = colour);
        }
      default: // peek: a huge form bleeding off the corner with a nested echo
        _lines(canvas, Size(w * 0.55, h * 0.55), on.withValues(alpha: 0.1), h / 10);
        final big = sq(w * 0.86, h * 0.98, h * 1.7);
        canvas.drawPath(shapePath(mainRadii, big, rotation: spec.rot + turn + t * 0.3), Paint()..color = fill);
        canvas.drawPath(shapePath(mainRadii, Rect.fromCenter(center: big.center, width: big.width * 0.56, height: big.height * 0.56), rotation: spec.rot - turn + t * 0.9),
            Paint()..color = bg.withValues(alpha: 0.9));
        canvas.drawPath(shapePath(shapeRadii(spec.accent), sq(w * 0.2, h * 0.32, h * 0.26), rotation: spec.accentRot + turn), Paint()..color = alt);
    }
    canvas.restore();
  }

  void _dots(Canvas c, Rect r, Color color, double gap) {
    final p = Paint()..color = color;
    for (var y = r.top; y < r.bottom; y += gap) {
      for (var x = r.left; x < r.right; x += gap) {
        c.drawCircle(Offset(x, y), gap * 0.13, p);
      }
    }
  }

  void _rings(Canvas c, Offset center, double start, Color color, double gap) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = color;
    for (var r = start; r < start + gap * 6; r += gap) {
      c.drawCircle(center, r, p);
    }
  }

  void _lines(Canvas c, Size size, Color color, double gap) {
    final p = Paint()
      ..strokeWidth = 1.2
      ..color = color;
    for (var x = -size.height; x < size.width; x += gap) {
      c.drawLine(Offset(x, size.height), Offset(x + size.height, 0), p);
    }
  }

  @override
  bool shouldRepaint(CourseArtPainter o) => o.t != t || o.spin != spin || o.s != s || o.spec != spec || o.layout != layout;
}

/// Small status markers for local artifacts.
class AssetBadges extends StatelessWidget {
  const AssetBadges({super.key, required this.assets, this.segments = 0});
  final List<String> assets;
  final int segments;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = <(IconData, String)>[
      if (assets.contains('video')) (Icons.movie_outlined, l10n.assetVideo),
      if (assets.contains('slides')) (Icons.slideshow_outlined, 'PPT'),
      if (assets.contains('courseware')) (Icons.attach_file_rounded, l10n.assetCourseware),
      if (segments > 0 || assets.contains('transcript')) (Icons.subject_rounded, l10n.assetTranscript),
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: Space.xs, runSpacing: Space.xs, children: [
      for (final (icon, label) in items)
        Tooltip(
          message: l10n.courseDownloadedKind(label),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: cs.tertiaryContainer, borderRadius: BorderRadius.circular(Corners.xs)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 12, color: cs.onTertiaryContainer),
              const SizedBox(width: 3),
              Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onTertiaryContainer)),
            ]),
          ),
        ),
    ]);
  }
}

class JobProgressLine extends StatelessWidget {
  const JobProgressLine({super.key, required this.job});
  final Job job;
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final parts = <String>[
      kindLabels[job.kind] ?? job.kind,
      if (job.stage.isNotEmpty) job.stage,
      if (job.speed > 0) fmtSpeed(job.speed),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      TweenAnimationBuilder<double>(
        tween: Tween(end: job.state == 'queued' ? 0 : job.progress),
        duration: Motion.medium2,
        curve: Motion.standard,
        builder: (_, v, _) => LinearProgressIndicator(value: job.state == 'queued' ? null : v, borderRadius: BorderRadius.circular(4)),
      ),
      const SizedBox(height: 4),
      Text(parts.join(' · '), style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
    ]);
  }
}
