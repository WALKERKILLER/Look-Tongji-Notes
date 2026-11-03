import 'dart:math' as math;
import 'dart:ui';

/// Local geometric fitting; results remain ordinary editable ink points.
class StudyShape {
  const StudyShape(this.kind, this.points);
  final String kind;
  final List<Offset> points;

  String get label => switch (kind) {
    'line' => '直线',
    'circle' => '圆',
    'ellipse' => '椭圆',
    'triangle' => '三角形',
    'rectangle' => '矩形',
    'arrow' => '箭头',
    'polygon' => '多边形',
    _ => '四边形',
  };

  List<Offset> adjust(Offset heldAt, Offset target) {
    if (kind == 'line') return [points.first, _axisSnap(points.first, target)];
    final center = _bounds(points).center;
    final from = heldAt - center, to = target - center;
    if (from.distance < 1) return points;
    final scale = (to.distance / from.distance).clamp(.2, 5.0);
    final angle = math.atan2(to.dy, to.dx) - math.atan2(from.dy, from.dx);
    return [
      for (final p in points) center + _rotate(p - center, angle) * scale,
    ];
  }
}

/// Conservative recognition of a single held stroke. Tolerances use screen
/// distance, so zooming does not turn a small dot into a large shape candidate.
StudyShape? recognizeStudyShape(List<Offset> input, {double zoom = 1}) {
  if (input.length < 3 ||
      input.length > 20000 ||
      !zoom.isFinite ||
      zoom <= 0 ||
      input.any((p) => !p.dx.isFinite || !p.dy.isFinite))
    return null;
  final samples = _resample(input, 128);
  if (samples.length < 3) return null;
  final bounds = _bounds(samples),
      diagonal = bounds.size.bottomRight(Offset.zero).distance;
  if (diagonal * zoom < 28) return null;
  final length = _length(samples),
      chord = (samples.last - samples.first).distance;
  if (chord * zoom >= 24 &&
      length / chord < 1.12 &&
      samples.every(
        (p) =>
            _segmentDistance(p, samples.first, samples.last) <=
            math.max(2.5 / zoom, chord * .035),
      )) {
    return StudyShape('line', [
      samples.first,
      _axisSnap(samples.first, samples.last),
    ]);
  }
  final arrow = _arrow(samples, diagonal);
  if (arrow != null) return arrow;
  if (chord > math.max(10 / zoom, diagonal * .24) ||
      bounds.shortestSide * zoom < 18 ||
      length < diagonal * 2)
    return null;
  final ring = _resample([...samples, samples.first], 128);
  return _polygon(ring, diagonal, length) ?? _ellipse(ring, zoom);
}

StudyShape? _polygon(List<Offset> ring, double diagonal, double length) {
  // Split the closed trace into two open arcs before simplifying its corners.
  var a = 0, b = 1;
  var distance = 0.0;
  for (var i = 0; i < ring.length - 1; i++) {
    for (var j = i + 1; j < ring.length - 1; j++) {
      final d = (ring[i] - ring[j]).distanceSquared;
      if (d > distance) {
        distance = d;
        a = i;
        b = j;
      }
    }
  }
  final tolerance = diagonal * .04;
  final vertices = [
    ..._corners(ring.sublist(a, b + 1), tolerance)..removeLast(),
    ..._corners([
      ...ring.sublist(b, ring.length - 1),
      ...ring.sublist(0, a + 1),
    ], tolerance)..removeLast(),
  ];
  var pruned = true;
  while (pruned && vertices.length > 3) {
    pruned = false;
    for (var i = 0; i < vertices.length; i++) {
      if (_segmentDistance(
            vertices[i],
            vertices[(i + vertices.length - 1) % vertices.length],
            vertices[(i + 1) % vertices.length],
          ) <
          tolerance) {
        vertices.removeAt(i);
        pruned = true;
        break;
      }
    }
  }
  if (vertices.length < 3 || vertices.length > 6) return null;
  var turn = 0.0, area = 0.0;
  for (var i = 0; i < vertices.length; i++) {
    final p = vertices[i],
        q = vertices[(i + 1) % vertices.length],
        r = vertices[(i + 2) % vertices.length];
    final u = q - p, v = r - q, cross = _cross(u, v);
    if (u.distance < diagonal * .13 ||
        cross.abs() < u.distance * v.distance * .18 ||
        turn * cross < 0)
      return null;
    turn = cross;
    area += _cross(p, q);
  }
  final closed = [...vertices, vertices.first];
  if (area.abs() < diagonal * diagonal * .12 || length / _length(closed) > 1.15)
    return null;
  // Rounded arcs must not become polygons merely because simplification
  // produced a few vertices. Most samples must lie close to fitted edges.
  var error = 0.0;
  for (final p in ring) {
    error += List.generate(
      vertices.length,
      (i) =>
          _segmentDistance(p, vertices[i], vertices[(i + 1) % vertices.length]),
    ).reduce(math.min);
  }
  final edgeTolerance = vertices.length <= 4 ? .02 : .013;
  if (error / ring.length > diagonal * edgeTolerance) return null;
  if (vertices.length == 3) return StudyShape('triangle', closed);
  if (vertices.length > 4) return StudyShape('polygon', closed);
  final edges = [
    for (var i = 0; i < 4; i++) vertices[(i + 1) % 4] - vertices[i],
  ];
  if (List.generate(
    4,
    (i) =>
        _dot(edges[i], edges[(i + 1) % 4]).abs() /
        (edges[i].distance * edges[(i + 1) % 4].distance),
  ).every((v) => v < .25)) {
    final axis = edges[0] / edges[0].distance - edges[2] / edges[2].distance;
    final angle = math.atan2(axis.dy, axis.dx);
    final box = _bounds(vertices.map((p) => _rotate(p, -angle)).toList());
    final corners = [
      box.topLeft,
      box.topRight,
      box.bottomRight,
      box.bottomLeft,
      box.topLeft,
    ];
    return StudyShape('rectangle', [
      for (final p in corners) _rotate(p, angle),
    ]);
  }
  return StudyShape('quadrilateral', closed);
}

/// A continuous shaft → tip → wing → tip → opposite wing gesture. The
/// return to the tip distinguishes an arrow from an ordinary zigzag word.
StudyShape? _arrow(List<Offset> samples, double diagonal) {
  final v = _corners(samples, diagonal * .025);
  if (v.length != 5) return null;
  final start = v[0], tip = (v[1] + v[3]) / 2;
  final shaft = tip - start, length = shaft.distance;
  if (length < diagonal * .7 || (v[1] - v[3]).distance > length * .08)
    return null;
  final axis = shaft / length, normal = Offset(-axis.dy, axis.dx);
  final a = v[2] - tip, b = v[4] - tip;
  final backA = -_dot(a, axis), backB = -_dot(b, axis);
  final sideA = _dot(a, normal), sideB = _dot(b, normal);
  if (sideA * sideB >= 0 ||
      backA < length * .1 ||
      backB < length * .1 ||
      backA > length * .45 ||
      backB > length * .45 ||
      sideA.abs() < length * .06 ||
      sideB.abs() < length * .06 ||
      sideA.abs() > length * .4 ||
      sideB.abs() > length * .4 ||
      (a.distance / b.distance) < .5 ||
      (a.distance / b.distance) > 2)
    return null;
  final back = (backA + backB) / 2;
  final side = (sideA.abs() + sideB.abs()) / 2;
  return StudyShape('arrow', [
    start,
    tip,
    tip - axis * back + normal * side * sideA.sign,
    tip,
    tip - axis * back - normal * side * sideA.sign,
  ]);
}

StudyShape? _ellipse(List<Offset> ring, double zoom) {
  final trace = ring.take(ring.length - 1).toList();
  final mean =
      trace.fold(Offset.zero, (a, b) => a + b) / trace.length.toDouble();
  var xx = 0.0, yy = 0.0, xy = 0.0;
  for (final p in trace) {
    final d = p - mean;
    xx += d.dx * d.dx;
    yy += d.dy * d.dy;
    xy += d.dx * d.dy;
  }
  final angle = .5 * math.atan2(2 * xy, xx - yy);
  final projected = trace.map((p) => _rotate(p - mean, -angle)).toList();
  final box = _bounds(projected), center = box.center;
  var rx = box.width / 2, ry = box.height / 2;
  if (math.min(rx, ry) * zoom < 9) return null;
  var error = 0.0, turn = 0.0, travel = 0.0;
  double? previous, first;
  for (final p in projected) {
    final d = p - center, x = d.dx / rx, y = d.dy / ry;
    final deviation = (math.sqrt(x * x + y * y) - 1).abs();
    if (deviation > .24) return null;
    error += deviation;
    final theta = math.atan2(y, x);
    first ??= theta;
    if (previous != null) {
      final delta = _angleDelta(theta - previous);
      turn += delta;
      travel += delta.abs();
    }
    previous = theta;
  }
  final tail = _angleDelta(first! - previous!);
  turn += tail;
  travel += tail.abs();
  if (error / trace.length > .09 ||
      turn.abs() < 5.8 ||
      turn.abs() > 6.7 ||
      travel > 7.4)
    return null;
  final circle = math.min(rx, ry) / math.max(rx, ry) > .91;
  if (circle) {
    rx = ry = (rx + ry) / 2;
  }
  final start = math.atan2(
    (projected.first - center).dy / ry,
    (projected.first - center).dx / rx,
  );
  final points = <Offset>[];
  for (var i = 0; i < 96; i++) {
    final t = start + turn.sign * 2 * math.pi * i / 96;
    points.add(
      mean +
          _rotate(center + Offset(rx * math.cos(t), ry * math.sin(t)), angle),
    );
  }
  return StudyShape(circle ? 'circle' : 'ellipse', [...points, points.first]);
}

List<Offset> _resample(List<Offset> points, int count) {
  final length = _length(points);
  if (length < .001) return [];
  final result = <Offset>[points.first];
  var edge = 1, passed = 0.0;
  for (var i = 1; i < count - 1; i++) {
    final target = length * i / (count - 1);
    while (edge < points.length - 1 &&
        passed + (points[edge] - points[edge - 1]).distance < target) {
      passed += (points[edge] - points[edge - 1]).distance;
      edge++;
    }
    final d = (points[edge] - points[edge - 1]).distance;
    result.add(
      Offset.lerp(
        points[edge - 1],
        points[edge],
        d < .001 ? 0 : ((target - passed) / d).clamp(0, 1),
      )!,
    );
  }
  return [...result, points.last];
}

List<Offset> _corners(List<Offset> points, double tolerance) {
  var farthest = 0, distance = tolerance;
  for (var i = 1; i < points.length - 1; i++) {
    final d = _segmentDistance(points[i], points.first, points.last);
    if (d > distance) {
      farthest = i;
      distance = d;
    }
  }
  if (farthest == 0) return [points.first, points.last];
  return [
    ..._corners(points.sublist(0, farthest + 1), tolerance)..removeLast(),
    ..._corners(points.sublist(farthest), tolerance),
  ];
}

double _segmentDistance(Offset p, Offset a, Offset b) {
  final d = b - a;
  if (d.distanceSquared < .000001) return (p - a).distance;
  return (p - a - d * (_dot(p - a, d) / d.distanceSquared).clamp(0, 1))
      .distance;
}

double _length(List<Offset> points) {
  var result = 0.0;
  for (var i = 1; i < points.length; i++) {
    result += (points[i] - points[i - 1]).distance;
  }
  return result;
}

Rect _bounds(List<Offset> points) => points
    .skip(1)
    .fold(
      Rect.fromPoints(points.first, points.first),
      (r, p) => r.expandToInclude(Rect.fromPoints(p, p)),
    );
double _dot(Offset a, Offset b) => a.dx * b.dx + a.dy * b.dy;
double _cross(Offset a, Offset b) => a.dx * b.dy - a.dy * b.dx;
Offset _rotate(Offset p, double angle) => Offset(
  p.dx * math.cos(angle) - p.dy * math.sin(angle),
  p.dx * math.sin(angle) + p.dy * math.cos(angle),
);
double _angleDelta(double value) =>
    math.atan2(math.sin(value), math.cos(value));
Offset _axisSnap(Offset start, Offset end) {
  final d = end - start;
  if (d.dy.abs() < d.dx.abs() * .07) return Offset(end.dx, start.dy);
  if (d.dx.abs() < d.dy.abs() * .07) return Offset(start.dx, end.dy);
  return end;
}
