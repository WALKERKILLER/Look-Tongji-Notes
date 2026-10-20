import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// A library of soft, M3 Expressive–style shapes (cookies, clovers, bursts,
/// rounded polygons…). Every shape is resampled to the same polar form — a
/// radius per angle around its centre — so any two shapes morph by plain
/// interpolation.
enum OrganicShape {
  circle,
  squircle,
  cookie4,
  cookie6,
  cookie7,
  cookie9,
  cookie12,
  clover4,
  clover8,
  sunny,
  verySunny,
  softBurst,
  flower,
  puffy,
  triangle,
  pentagon,
  diamond,
  gem,
  pill,
  oval,
  arch,
  heart,
  pebble,
  droplet,
  ghost,
}

const int kShapeSamples = 180;

final Map<OrganicShape, Float64List> _cache = {};

/// Unit-radius polar samples for [s] (index i ↔ angle 2πi/N, starting at −π/2).
Float64List shapeRadii(OrganicShape s) => _cache.putIfAbsent(s, () => _normalise(_polarOf(_outline(s))));

/// Interpolated radii between two shapes.
Float64List morphRadii(OrganicShape a, OrganicShape b, double t) {
  final ra = shapeRadii(a), rb = shapeRadii(b);
  if (t <= 0) return ra;
  if (t >= 1) return rb;
  final out = Float64List(kShapeSamples);
  for (var i = 0; i < kShapeSamples; i++) {
    out[i] = ra[i] + (rb[i] - ra[i]) * t;
  }
  return out;
}

/// Builds a smooth closed path for [radii], rotated by [rotation] radians and
/// scaled so its bounds fit inside [rect] (centred, aspect preserved).
Path shapePath(Float64List radii, Rect rect, {double rotation = 0}) {
  final n = radii.length;
  final pts = List<Offset>.generate(n, (i) {
    final a = -math.pi / 2 + 2 * math.pi * i / n + rotation;
    return Offset(math.cos(a) * radii[i], math.sin(a) * radii[i]);
  });
  var minX = double.infinity, minY = double.infinity, maxX = -double.infinity, maxY = -double.infinity;
  for (final p in pts) {
    minX = math.min(minX, p.dx);
    maxX = math.max(maxX, p.dx);
    minY = math.min(minY, p.dy);
    maxY = math.max(maxY, p.dy);
  }
  final s = math.min(rect.width / (maxX - minX), rect.height / (maxY - minY));
  final c = Offset((minX + maxX) / 2, (minY + maxY) / 2);
  final mapped = [for (final p in pts) rect.center + (p - c) * s];
  // Catmull-Rom through the samples for a curve without facets.
  final path = Path()..moveTo(mapped[0].dx, mapped[0].dy);
  for (var i = 0; i < n; i++) {
    final p0 = mapped[(i - 1 + n) % n], p1 = mapped[i], p2 = mapped[(i + 1) % n], p3 = mapped[(i + 2) % n];
    final c1 = p1 + (p2 - p0) / 6, c2 = p2 - (p3 - p1) / 6;
    path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
  }
  return path..close();
}

// ---------------------------------------------------------------- outlines

/// Dense, star-shaped outline around the origin.
List<Offset> _outline(OrganicShape s) {
  const n = 720;
  List<Offset> polar(double Function(double) r) => [
        for (var i = 0; i < n; i++) Offset.fromDirection(2 * math.pi * i / n - math.pi / 2, r(2 * math.pi * i / n)),
      ];
  double bump(double t, int k, double p) => math.pow((1 + math.cos(k * t)) / 2, p).toDouble();
  switch (s) {
    case OrganicShape.circle:
      return polar((_) => 1);
    case OrganicShape.squircle:
      return polar((t) => math.pow(math.pow(math.cos(t).abs(), 4) + math.pow(math.sin(t).abs(), 4), -0.25).toDouble());
    case OrganicShape.cookie4:
      return polar((t) => 1 + 0.11 * math.cos(4 * t));
    case OrganicShape.cookie6:
      return polar((t) => 1 + 0.085 * math.cos(6 * t));
    case OrganicShape.cookie7:
      return polar((t) => 1 + 0.075 * math.cos(7 * t));
    case OrganicShape.cookie9:
      return polar((t) => 1 + 0.065 * math.cos(9 * t));
    case OrganicShape.cookie12:
      return polar((t) => 1 + 0.05 * math.cos(12 * t));
    case OrganicShape.clover4:
      return polar((t) => 0.6 + 0.4 * math.pow(math.cos(2 * t).abs(), 0.55));
    case OrganicShape.clover8:
      return polar((t) => 0.74 + 0.26 * math.pow(math.cos(4 * t).abs(), 0.6));
    case OrganicShape.sunny:
      return polar((t) => 0.86 + 0.14 * bump(t, 8, 1.6));
    case OrganicShape.verySunny:
      return polar((t) => 0.8 + 0.2 * bump(t, 12, 2.6));
    case OrganicShape.softBurst:
      return polar((t) => 0.78 + 0.22 * bump(t, 10, 1.4));
    case OrganicShape.flower:
      return polar((t) => 0.55 + 0.45 * math.pow(math.cos(3 * t).abs(), 0.7));
    case OrganicShape.puffy:
      return polar((t) => 0.84 + 0.16 * math.pow(math.cos(5 * t).abs(), 0.35));
    case OrganicShape.triangle:
      return _roundedPolygon(3, 0.32);
    case OrganicShape.pentagon:
      return _roundedPolygon(5, 0.26);
    case OrganicShape.diamond:
      return [for (final p in _roundedPolygon(4, 0.24)) Offset(p.dx * 0.82, p.dy * 1.12)];
    case OrganicShape.gem:
      return [for (final p in _roundedPolygon(6, 0.2, phase: math.pi / 6)) Offset(p.dx * 0.86, p.dy * 1.1)];
    case OrganicShape.pill:
      return _stadium(1, 0.56);
    case OrganicShape.oval:
      return polar((t) => 1 / math.sqrt(math.pow(math.cos(t) / 1.0, 2) + math.pow(math.sin(t) / 0.72, 2)));
    case OrganicShape.arch:
      return _arch();
    case OrganicShape.pebble:
      // A river stone: wider than tall, a little lopsided.
      return polar((t) => (1 + 0.035 * math.sin(2 * t + 0.6)) / math.sqrt(math.pow(math.cos(t), 2) + math.pow(math.sin(t) / 0.8, 2)));
    case OrganicShape.droplet:
      // Round bottom drawn up to a soft point at the top (t = 0).
      return polar((t) => 0.7 + 0.32 * math.pow((1 + math.cos(t)) / 2, 5));
    case OrganicShape.ghost:
      return _ghost();
    case OrganicShape.heart:
      return [
        for (var i = 0; i < n; i++)
          () {
            final t = 2 * math.pi * i / n;
            final x = 16 * math.pow(math.sin(t), 3);
            final y = -(13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t));
            return Offset(x / 17, y / 17 + 0.08);
          }(),
      ];
  }
}

/// Regular k-gon with corners rounded by [round] (0–1 of the radius), sampled
/// by normal direction (support parametrisation of a dilated polygon).
List<Offset> _roundedPolygon(int k, double round, {double phase = 0}) {
  final verts = [
    for (var i = 0; i < k; i++) Offset.fromDirection(-math.pi / 2 + phase + 2 * math.pi * i / k, 1 - round),
  ];
  final out = <Offset>[];
  for (var i = 0; i < 720; i++) {
    final a = 2 * math.pi * i / 720;
    final nrm = Offset(math.cos(a), math.sin(a));
    var best = verts[0];
    var bd = -double.infinity;
    for (final v in verts) {
      final d = v.dx * nrm.dx + v.dy * nrm.dy;
      if (d > bd) {
        bd = d;
        best = v;
      }
    }
    out.add(best + nrm * round);
  }
  return out;
}

List<Offset> _stadium(double w, double h) {
  final r = h;
  final out = <Offset>[];
  for (var i = 0; i < 720; i++) {
    final a = 2 * math.pi * i / 720;
    final c = Offset(math.cos(a) >= 0 ? w - r : -(w - r), 0);
    out.add(c + Offset(math.cos(a), math.sin(a)) * r);
  }
  return out;
}

List<Offset> _arch() {
  final out = <Offset>[];
  // Semicircular top.
  for (var i = 0; i <= 180; i++) {
    final a = math.pi + math.pi * i / 180;
    out.add(Offset(math.cos(a), math.sin(a) * 1.0 - 0.15));
  }
  // Right side, rounded bottom corners, bottom edge, left side.
  for (var i = 1; i <= 40; i++) {
    out.add(Offset(1, -0.15 + 0.85 * i / 40));
  }
  const rc = 0.28;
  for (var i = 0; i <= 30; i++) {
    final a = 2 * math.pi * i / 120; // 0..90°
    out.add(Offset(1 - rc + rc * math.cos(a), 0.7 + rc * math.sin(a)));
  }
  for (var i = 1; i < 40; i++) {
    out.add(Offset(1 - rc - (2 - 2 * rc) * i / 40, 0.98));
  }
  for (var i = 0; i <= 30; i++) {
    final a = math.pi / 2 + 2 * math.pi * i / 120;
    out.add(Offset(-1 + rc + rc * math.cos(a), 0.7 + rc * math.sin(a)));
  }
  for (var i = 1; i < 40; i++) {
    out.add(Offset(-1, 0.7 - 0.85 * i / 40));
  }
  return out;
}

/// A dome over straight sides and a three-scallop hem.
List<Offset> _ghost() {
  final out = <Offset>[];
  for (var i = 0; i <= 180; i++) {
    final a = math.pi + math.pi * i / 180;
    out.add(Offset(math.cos(a) * 0.86, math.sin(a) * 0.86 - 0.1));
  }
  for (var i = 1; i <= 40; i++) {
    out.add(Offset(0.86, -0.1 + 0.82 * i / 40));
  }
  for (var i = 0; i <= 120; i++) {
    final x = 0.86 - 1.72 * i / 120;
    out.add(Offset(x, 0.72 + 0.1 * (1 - math.cos(3 * math.pi * i / 60)) / 2));
  }
  for (var i = 1; i < 40; i++) {
    out.add(Offset(-0.86, 0.72 - 0.82 * i / 40));
  }
  return out;
}

// ---------------------------------------------------------------- resampling

/// Ray-casts the outline from its centroid at uniform angles.
Float64List _polarOf(List<Offset> pts) {
  var cx = 0.0, cy = 0.0;
  for (final p in pts) {
    cx += p.dx;
    cy += p.dy;
  }
  final c = Offset(cx / pts.length, cy / pts.length);
  final rel = [for (final p in pts) p - c];
  final out = Float64List(kShapeSamples);
  for (var i = 0; i < kShapeSamples; i++) {
    final a = -math.pi / 2 + 2 * math.pi * i / kShapeSamples;
    final d = Offset(math.cos(a), math.sin(a));
    var best = 0.0;
    for (var j = 0; j < rel.length; j++) {
      final p = rel[j], q = rel[(j + 1) % rel.length];
      final hit = _raySegment(d, p, q);
      if (hit != null && hit > best) best = hit;
    }
    out[i] = best;
  }
  return out;
}

double? _raySegment(Offset d, Offset p, Offset q) {
  final e = q - p;
  final den = d.dx * e.dy - d.dy * e.dx;
  if (den.abs() < 1e-12) return null;
  final t = (p.dx * e.dy - p.dy * e.dx) / den; // distance along ray
  final u = (p.dx * d.dy - p.dy * d.dx) / den; // position on segment
  if (t <= 0 || u < -1e-9 || u > 1 + 1e-9) return null;
  return t;
}

Float64List _normalise(Float64List r) {
  var m = 0.0;
  for (final v in r) {
    m = math.max(m, v);
  }
  for (var i = 0; i < r.length; i++) {
    r[i] /= m;
  }
  return r;
}
