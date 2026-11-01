import 'dart:math' as math;

/// Stored with each new stroke; absent settings preserve version-1 ink replay.
class StudyBrush {
  const StudyBrush({
    this.family = 'fountain',
    this.opacity = 1,
    this.pressure = .65,
    this.smoothing = .2,
    this.squareTip = false,
  });
  final String family;
  final double opacity, pressure, smoothing;
  final bool squareTip;
  StudyBrush copyWith({
    String? family,
    double? opacity,
    double? pressure,
    double? smoothing,
    bool? squareTip,
  }) => StudyBrush(
    family: family ?? this.family,
    opacity: opacity ?? this.opacity,
    pressure: pressure ?? this.pressure,
    smoothing: smoothing ?? this.smoothing,
    squareTip: squareTip ?? this.squareTip,
  );
  double radiusScale(double raw) {
    if (family == 'ballpoint' || family == 'highlighter') return 1;
    final shaped = math
        .pow(raw.clamp(0, 1), family == 'brush' ? 1.6 : .85)
        .toDouble();
    return (1 - pressure) + pressure * (.15 + .85 * shaped);
  }

  Map<String, dynamic> json() => {
    'family': family,
    'opacity': opacity,
    'pressure': pressure,
    'smoothing': smoothing,
    'square_tip': squareTip,
  };
  factory StudyBrush.fromJson(Map m) => StudyBrush(
    family:
        const {
          'ballpoint',
          'fountain',
          'pencil',
          'brush',
          'highlighter',
        }.contains(m['family'])
        ? '${m['family']}'
        : 'fountain',
    opacity: ((m['opacity'] as num? ?? 1).toDouble()).clamp(.05, 1),
    pressure: ((m['pressure'] as num? ?? .65).toDouble()).clamp(0, 1),
    smoothing: ((m['smoothing'] as num? ?? .2).toDouble()).clamp(0, 1),
    squareTip: m['square_tip'] == true,
  );
}

class StudyPenPreset {
  StudyPenPreset(
    this.name,
    this.color,
    this.width,
    this.brush, {
    this.shapeAssist = true,
  });
  String name;
  int color;
  double width;
  StudyBrush brush;
  bool shapeAssist;
  Map<String, dynamic> json() => {
    'name': name,
    'color': color,
    'width': width,
    'brush': brush.json(),
    'shape_assist': shapeAssist,
  };
  factory StudyPenPreset.fromJson(Map m) => StudyPenPreset(
    '${m['name'] ?? '收藏笔'}',
    (m['color'] as num? ?? 0xff25344a).toInt(),
    ((m['width'] as num? ?? 3).toDouble()).clamp(.2, 80),
    StudyBrush.fromJson(m['brush'] as Map? ?? {}),
    shapeAssist: m['shape_assist'] != false,
  );
  static List<StudyPenPreset> defaults() => [
    StudyPenPreset('钢笔', 0xff26354a, 3, const StudyBrush()),
    StudyPenPreset(
      '圆珠笔',
      0xff6254d7,
      2,
      const StudyBrush(family: 'ballpoint', pressure: 0),
    ),
    StudyPenPreset(
      '铅笔',
      0xff4d5969,
      4,
      const StudyBrush(family: 'pencil', opacity: .72),
    ),
    StudyPenPreset(
      '软笔',
      0xffd65360,
      7,
      const StudyBrush(family: 'brush', pressure: .9, smoothing: .35),
    ),
    StudyPenPreset(
      '荧光笔',
      0xffffd34f,
      22,
      const StudyBrush(
        family: 'highlighter',
        opacity: .35,
        pressure: 0,
        squareTip: true,
      ),
    ),
  ];
}
