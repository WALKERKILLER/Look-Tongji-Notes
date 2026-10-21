import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../theme/prefs.dart';
import '../../widgets/organic_shapes.dart';

// The resident bot's mascot: a smooth, matte body lit softly from above, two
// ink capsule eyes with a catchlight, blush that comes with warm moods and a
// contact shadow that keeps it on the ground. No mouth; eyes and posture
// carry every mood.
// Source: bloub by Jérémy Perret (MIT) — https://github.com/jeremy-prt/bloub
// Derived: bodies as polar radius profiles that morph by interpolating radii,
// ease-out-quint morphs (design only; written for Flutter on the app's shape
// library). The single-shape, capsule-eyed character follows Grok Bot's mascot.

enum BotMood { idle, listening, thinking, working, talking, happy, confused, dreaming, notify }

const kBotMoodLabels = <BotMood, String>{
  BotMood.idle: '在这儿',
  BotMood.listening: '在听',
  BotMood.thinking: '在想',
  BotMood.working: '在做事',
  BotMood.talking: '在说',
  BotMood.happy: '完成了',
  BotMood.confused: '出了点问题',
  BotMood.dreaming: '在整理记忆',
  BotMood.notify: '有卡片等你确认',
};

/// Body shapes by the bot.json key, in picker order (agent/src/bot.mjs SHAPES).
const kBotShapes = <String, (OrganicShape, String)>{
  'pebble': (OrganicShape.pebble, '鹅卵石'),
  'mochi': (OrganicShape.mochi, '团子'),
  'bean': (OrganicShape.bean, '豆豆'),
  'circle': (OrganicShape.circle, '圆圆'),
  'squircle': (OrganicShape.squircle, '方糖'),
  'capsule': (OrganicShape.capsule, '胶囊'),
  'droplet': (OrganicShape.droplet, '水滴'),
  'ghost': (OrganicShape.ghost, '小幽灵'),
};

/// Colour keys of bot.json: `theme` follows the app, the rest are kSeedPalette in order.
const kBotColorKeys = ['theme', 'blue', 'teal', 'green', 'amber', 'red', 'rose', 'violet', 'graphite'];

String botColorLabel(String key) {
  final i = kBotColorKeys.indexOf(key);
  return i <= 0 ? '跟随主题' : kSeedPalette[i - 1].$1;
}

final _schemes = <(String, Brightness), ColorScheme>{};

ColorScheme _schemeOf(ColorScheme cs, String key) {
  final i = kBotColorKeys.indexOf(key);
  if (i <= 0) return cs;
  return _schemes.putIfAbsent((key, cs.brightness), () => ColorScheme.fromSeed(seedColor: kSeedPalette[i - 1].$2, brightness: cs.brightness));
}

/// The bot's colours from M3 fixed roles, so it looks the same in light and
/// dark themes: body (primary fixed dim), eyes (on primary fixed), blush
/// (tertiary fixed dim).
({Color body, Color ink, Color blush}) botPalette(ColorScheme cs, String key) {
  final s = _schemeOf(cs, key);
  return (body: s.primaryFixedDim, ink: s.onPrimaryFixed, blush: s.tertiaryFixedDim);
}

/// Body and accent colour of the bot (chips, swatches).
(Color, Color) botColors(ColorScheme cs, String key) {
  final s = _schemeOf(cs, key);
  return (s.primaryFixedDim, s.tertiary);
}

OrganicShape _shapeOf(String key) => (kBotShapes[key] ?? kBotShapes['pebble']!).$1;

/// Where the eyes sit (fraction of the radius below centre) for a body.
double _eyeLine(String key) => switch (key) {
      'droplet' => 0.2,
      'ghost' => -0.06,
      'bean' => 0.06,
      'mochi' => 0.02,
      _ => -0.02,
    };

/// The animated mascot. [animate] off draws a still pose (lists of shapes,
/// tests); reduced motion keeps only blinking.
class BotAvatar extends StatefulWidget {
  const BotAvatar({
    super.key,
    this.size = 40,
    this.shape = 'pebble',
    this.color = 'theme',
    this.mood = BotMood.idle,
    this.animate = true,
    this.followPointer = true,
  });

  final double size;
  final String shape;
  final String color;
  final BotMood mood;
  final bool animate;
  final bool followPointer;

  @override
  State<BotAvatar> createState() => _BotAvatarState();
}

/// Everything the painter needs; mutated by the ticker, repainted through [frame].
class _Pose {
  double eyeW = 0.13, eyeH = 0.28, gazeX = 0, gazeY = 0, arc = 0, asym = 0, blush = 0.2;
  double sx = 1, sy = 1, tilt = 0, lift = 0, badge = 0, dream = 0, time = 0;
  late Float64List radii;
  String shape = 'pebble';
}

class _BotAvatarState extends State<BotAvatar> with SingleTickerProviderStateMixin {
  final _pose = _Pose();
  final _frame = ValueNotifier<int>(0);
  final _rand = math.Random();
  Ticker? _ticker;
  Duration _last = Duration.zero;

  // Shape morph.
  late Float64List _from;
  double _morphAt = -1;
  // Blink and gaze schedules (seconds of ticker time).
  double _nextBlink = 1.5, _blinkAt = -1, _nextGaze = 0.8;
  Offset _gazeTarget = Offset.zero;
  Offset? _pointer;
  double _moodAt = 0;

  static const _morphSecs = 0.6;
  static const Curve _quint = Cubic(0.22, 1, 0.36, 1); // ease-out quint

  @override
  void initState() {
    super.initState();
    _pose.radii = shapeRadii(_shapeOf(widget.shape));
    _pose.shape = widget.shape;
    _from = _pose.radii;
    _settle(widget.mood, 0, still: true);
    if (widget.animate) _ticker = createTicker(_tick)..start();
  }

  @override
  void didUpdateWidget(BotAvatar old) {
    super.didUpdateWidget(old);
    if (old.shape != widget.shape) {
      _from = Float64List.fromList(_pose.radii);
      _pose.shape = widget.shape;
      if (_ticker == null) {
        _pose.radii = shapeRadii(_shapeOf(widget.shape));
      } else {
        _morphAt = _pose.time;
      }
    }
    if (old.mood != widget.mood) _moodAt = _pose.time;
    if (old.animate != widget.animate) {
      _ticker?.dispose();
      _ticker = widget.animate ? (createTicker(_tick)..start()) : null;
    }
    if (_ticker == null) {
      _settle(widget.mood, 0, still: true);
      _frame.value++;
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _frame.dispose();
    super.dispose();
  }

  void _tick(Duration elapsed) {
    final t = elapsed.inMicroseconds / 1e6;
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = elapsed;
    _pose.time = t;
    final still = MediaQuery.disableAnimationsOf(context);

    if (_morphAt >= 0) {
      final k = still ? 1.0 : _quint.transform(((t - _morphAt) / _morphSecs).clamp(0.0, 1.0));
      final to = shapeRadii(_shapeOf(widget.shape));
      final out = Float64List(to.length);
      for (var i = 0; i < to.length; i++) {
        out[i] = _from[i] + (to[i] - _from[i]) * k;
      }
      _pose.radii = out;
      if (k >= 1) _morphAt = -1;
    }
    _settle(widget.mood, dt, still: still);
    _frame.value++;
  }

  /// Moves the pose toward the mood's target; dt 0 with still jumps there.
  void _settle(BotMood mood, double dt, {required bool still}) {
    final p = _pose;
    final t = p.time;
    final since = t - _moodAt;
    var eyeW = 0.13, eyeH = 0.28, gx = 0.0, gy = 0.0, arc = 0.0, asym = 0.0, blush = 0.2;
    var sx = 1.0, sy = 1.0, tilt = 0.0, lift = 0.0, badge = 0.0, dream = 0.0;

    // Idle gaze wanders; a near pointer wins.
    if (!still && t >= _nextGaze) {
      _gazeTarget = Offset(_rand.nextDouble() * 1.2 - 0.6, _rand.nextDouble() * 0.7 - 0.35);
      if (_rand.nextDouble() < 0.35) _gazeTarget = Offset.zero;
      _nextGaze = t + 1.4 + _rand.nextDouble() * 2.6;
    }
    final look = _pointer ?? _gazeTarget;
    final breath = still ? 0.0 : math.sin(2 * math.pi * t / 4.2);

    switch (mood) {
      case BotMood.idle:
        gx = look.dx;
        gy = look.dy;
        sy = 1 + 0.018 * breath;
        sx = 1 - 0.008 * breath;
      case BotMood.listening:
        eyeH = 0.31;
        eyeW = 0.14;
        blush = 0.35;
        gx = _pointer?.dx ?? 0;
        gy = _pointer?.dy ?? 0.35;
        tilt = still ? 0 : 0.05;
        sy = 1 + 0.012 * breath;
      case BotMood.thinking:
        eyeH = 0.22;
        gx = 0.55;
        gy = -0.6;
        tilt = still ? 0 : 0.05 * math.sin(t * 1.6);
        sy = 1 + 0.015 * breath;
      case BotMood.working:
        eyeH = 0.2;
        eyeW = 0.14;
        gx = still ? 0 : math.sin(t * 3.4) * 0.75;
        gy = 0.1;
        sy = still ? 1 : 1 + 0.012 * math.sin(t * 9);
      case BotMood.talking:
        gx = look.dx * 0.4;
        gy = look.dy * 0.4;
        final beat = still ? 0.0 : math.sin(2 * math.pi * t * 3.1).abs();
        sy = 1 + 0.035 * beat;
        sx = 1 - 0.015 * beat;
        blush = 0.4;
      case BotMood.happy:
        arc = 1;
        blush = 0.75;
        lift = still || since > 1.4 ? 0 : -0.1 * math.sin(math.pi * (since * 2.2 % 1)).abs();
        sy = 1 + (lift < 0 ? 0.03 : 0.018 * breath);
      case BotMood.confused:
        asym = 0.4;
        tilt = -0.13;
        gx = still ? -0.2 : -0.2 + 0.12 * math.sin(t * 7);
        gy = -0.15;
      case BotMood.dreaming:
        arc = -1;
        final slow = still ? 0.0 : math.sin(2 * math.pi * t / 6);
        sy = 1 + 0.04 * slow;
        sx = 1 - 0.015 * slow;
        dream = 1;
        blush = 0.3;
      case BotMood.notify:
        eyeH = 0.31;
        badge = 1;
        final hop = still ? 0.0 : (t % 2.6 < 0.5 ? math.sin(math.pi * (t % 2.6) / 0.5) : 0.0);
        lift = -0.08 * hop;
        sy = 1 + 0.03 * hop;
    }

    // Blinks every 3–6 s, not while the eyes are arcs.
    var blink = 0.0;
    if (dt > 0 || !still) {
      if (t >= _nextBlink && arc == 0) {
        _blinkAt = t;
        _nextBlink = t + 3 + _rand.nextDouble() * 3;
        if (_rand.nextDouble() < 0.2) _nextBlink = t + 0.32; // a double blink now and then
      }
      if (_blinkAt >= 0 && t - _blinkAt < 0.16) blink = math.sin(math.pi * (t - _blinkAt) / 0.16);
    }

    final k = dt == 0 ? 1.0 : 1 - math.exp(-dt * (still ? 30 : 11));
    double to(double cur, double target) => cur + (target - cur) * k;
    p.eyeW = to(p.eyeW, eyeW);
    p.eyeH = to(p.eyeH, eyeH);
    p.gazeX = to(p.gazeX, gx);
    p.gazeY = to(p.gazeY, gy);
    p.arc = to(p.arc, arc);
    p.asym = to(p.asym, asym);
    p.blush = to(p.blush, blush);
    p.sx = to(p.sx, sx);
    p.sy = to(p.sy, sy);
    p.tilt = to(p.tilt, tilt);
    p.lift = to(p.lift, lift);
    p.badge = to(p.badge, badge);
    p.dream = to(p.dream, dream);
    if (blink > 0) p.eyeH = p.eyeH + (0.035 - p.eyeH) * blink;
  }

  void _hover(PointerEvent e) {
    if (!widget.followPointer) return;
    final r = widget.size / 2;
    final d = (e.localPosition - Offset(r, r)) / (r * 2.2);
    _pointer = Offset(d.dx.clamp(-1.0, 1.0), d.dy.clamp(-1.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pal = botPalette(cs, widget.color);
    Widget paint = CustomPaint(
      size: Size.square(widget.size),
      painter: _BotPainter(_pose, _frame,
          body: pal.body, ink: pal.ink, blush: pal.blush, accent: cs.tertiary, ring: cs.surfaceContainerLow, shadow: cs.shadow),
    );
    if (widget.followPointer && widget.animate) {
      // The hover area reaches past the body so the eyes turn as the pointer nears.
      paint = MouseRegion(
        hitTestBehavior: HitTestBehavior.translucent,
        onHover: _hover,
        onExit: (_) => _pointer = null,
        child: paint,
      );
    }
    return RepaintBoundary(child: paint);
  }
}

class _BotPainter extends CustomPainter {
  _BotPainter(this.p, Listenable frame,
      {required this.body, required this.ink, required this.blush, required this.accent, required this.ring, required this.shadow})
      : super(repaint: frame);
  final _Pose p;
  final Color body, ink, blush, accent, ring, shadow;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2 * 0.76;
    final c = size.center(Offset.zero).translate(0, -r * 0.04);
    final fine = size.shortestSide >= 44; // details that only read at larger sizes

    // Contact shadow: tighter and darker when the body is down, fainter as it lifts.
    final up = (-p.lift).clamp(0.0, 0.2) / 0.2;
    canvas.drawOval(
      Rect.fromCenter(center: c + Offset(0, r * 1.02), width: r * 1.25 * (1 - 0.25 * up) * p.sx, height: r * 0.16 * (1 - 0.3 * up)),
      Paint()
        ..color = shadow.withValues(alpha: 0.16 * (1 - 0.5 * up))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(1, r * 0.06)),
    );

    canvas.save();
    canvas.translate(c.dx, c.dy + p.lift * r);
    canvas.rotate(p.tilt);
    // Squash and stretch about the base so the body sits on the ground.
    canvas.translate(0, r);
    canvas.scale(p.sx, p.sy);
    canvas.translate(0, -r);

    final box = Rect.fromCircle(center: Offset.zero, radius: r);
    final path = shapePath(p.radii, box);
    // Matte body: a soft light from the upper left, a little depth toward the base.
    canvas.drawPath(
      path,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.4, -0.55),
          radius: 1.15,
          colors: [Color.lerp(body, Colors.white, 0.22)!, body, Color.lerp(body, Colors.black, 0.07)!],
          stops: const [0, 0.55, 1],
        ).createShader(box),
    );

    final y = (_eyeLine(p.shape) + p.gazeY * 0.08) * r;
    final dx = 0.25 * r;

    // Blush under the eyes.
    if (p.blush > 0.02) {
      final bp = Paint()
        ..color = blush.withValues(alpha: 0.55 * p.blush.clamp(0.0, 1.0))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(0.6, r * 0.035));
      for (final side in const [-1, 1]) {
        canvas.drawOval(Rect.fromCenter(center: Offset(side * r * 0.47 + p.gazeX * 0.05 * r, y + r * 0.2), width: r * 0.2, height: r * 0.1), bp);
      }
    }

    final inkPaint = Paint()..color = ink;
    for (final side in const [-1, 1]) {
      final ec = Offset(side * dx + p.gazeX * 0.1 * r, y);
      final arc = p.arc.abs();
      if (arc < 0.5) {
        final grow = 1 + side * p.asym * 0.5;
        final w = p.eyeW * r * (1 + side * p.asym * 0.15);
        final h = math.max(w * 0.32, p.eyeH * r * grow * (1 - arc * 2));
        final eye = RRect.fromRectAndRadius(Rect.fromCenter(center: ec, width: w, height: h), Radius.circular(math.min(w, h) / 2));
        canvas.drawRRect(eye, inkPaint);
        // Catchlight, offset toward the light, only while the eye is open.
        if (fine && h > w * 1.3) {
          canvas.drawCircle(
            ec + Offset(-w * 0.18, -h * 0.24),
            w * 0.2,
            Paint()..color = Colors.white.withValues(alpha: 0.85 * ((h / w - 1.3) / 0.5).clamp(0.0, 1.0)),
          );
        }
      } else {
        // Smiling (∩) or sleeping (∪) eyes as soft ink strokes.
        final k = (arc - 0.5) * 2;
        final w = p.eyeW * r * 2;
        final stroke = Paint()
          ..color = ink
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = p.eyeW * r * 0.58 * k;
        final rect = Rect.fromCenter(center: ec + Offset(0, p.arc > 0 ? w * 0.2 : -w * 0.2), width: w, height: w * 0.8);
        canvas.drawArc(rect, p.arc > 0 ? math.pi * 1.12 : math.pi * 0.12, math.pi * 0.76, false, stroke);
      }
    }

    if (p.badge > 0.02) {
      final at = Offset(r * 0.74, -r * 0.7);
      final pulse = 1 + 0.08 * math.sin(p.time * 4);
      final rad = r * 0.17 * p.badge * pulse;
      canvas.drawCircle(at, rad + math.max(1.5, r * 0.06), Paint()..color = ring);
      canvas.drawCircle(at, rad, Paint()..color = accent);
    }
    canvas.restore();

    if (p.dream > 0.02) {
      // Three small dots drift up and away from the sleeping head.
      for (var i = 0; i < 3; i++) {
        final ph = (p.time / 2.8 + i / 3) % 1;
        final o = c + Offset(r * (0.55 + ph * 0.45), -r * (0.62 + ph * 0.6));
        canvas.drawCircle(o, r * (0.045 + 0.04 * ph), Paint()..color = ink.withValues(alpha: p.dream * (1 - ph) * 0.45));
      }
    }
  }

  @override
  bool shouldRepaint(_BotPainter o) =>
      o.body != body || o.ink != ink || o.blush != blush || o.accent != accent || o.ring != ring || o.shadow != shadow || o.p != p;
}
