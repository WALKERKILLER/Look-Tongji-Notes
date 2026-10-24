import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../theme/prefs.dart';
import '../../widgets/organic_shapes.dart';
import '../../l10n/l10n.dart';

// The resident bot's mascot, built like a desk companion robot: a soft matte
// shell, a recessed dark face screen and two glowing eyes that carry every
// mood (no mouth). Each body wears one rounded topper (antenna, ears, sprout,
// headphones) that lags behind the body on a spring.
// Source: fonzu/RobotEye (MIT) — https://github.com/fonzu/RobotEye
// Derived: an expression is a set of eye parameters (rounded rectangle, a top
// lid cut with a slope, a bottom ellipse mask) eased between moods; a blink
// hides each expression change; idle glances that return, squints and drift.
// Source: FluxGarage RoboEyes (GPL-3.0) — https://github.com/FluxGarage/RoboEyes
// Ideas only, no code: the outer eye grows when looking aside (curiosity) and
// tired lids for sleep.
// Source: bloub by Jérémy Perret (MIT) — https://github.com/jeremy-prt/bloub
// Derived: bodies as polar radius profiles that morph by interpolating radii,
// ease-out-quint morphs (design only; written for Flutter on the app's shape
// library).

enum BotMood { idle, listening, thinking, working, talking, happy, confused, dreaming, notify }

final kBotMoodLabels = <BotMood, String>{
  BotMood.idle: l10n.botMoodIdle,
  BotMood.listening: l10n.botMoodListening,
  BotMood.thinking: l10n.botMoodThinking,
  BotMood.working: l10n.botMoodWorking,
  BotMood.talking: l10n.botMoodTalking,
  BotMood.happy: l10n.botMoodHappy,
  BotMood.confused: l10n.botMoodConfused,
  BotMood.dreaming: l10n.botMoodDreaming,
  BotMood.notify: l10n.botMoodNotify,
};

/// Body shapes by the bot.json key, in picker order (agent/src/bot.mjs SHAPES).
/// The label names the character the body and its topper make.
final kBotShapes = <String, (OrganicShape, String)>{
  'pebble': (OrganicShape.pebble, l10n.botAccessoryAntenna),
  'mochi': (OrganicShape.mochi, l10n.botAccessoryCatEars),
  'bean': (OrganicShape.bean, l10n.botAccessorySprout),
  'circle': (OrganicShape.circle, l10n.botAccessoryBunnyEars),
  'squircle': (OrganicShape.squircle, l10n.botAccessoryFeelers),
  'capsule': (OrganicShape.capsule, l10n.botAccessoryHeadphones),
  'droplet': (OrganicShape.droplet, l10n.botAccessoryDrop),
  'ghost': (OrganicShape.ghost, l10n.botAccessoryGhost),
};

/// The body a new bot wears (agent/src/bot.mjs DEFAULT_BOT): cat ears.
const kDefaultBotShape = 'mochi';

/// Colour keys of bot.json: `theme` follows the app, the rest are kSeedPalette in order.
const kBotColorKeys = ['theme', 'blue', 'teal', 'green', 'amber', 'red', 'rose', 'violet', 'graphite'];

String botColorLabel(String key) {
  final i = kBotColorKeys.indexOf(key);
  return i <= 0 ? l10n.commonFollowTheme : kSeedPalette[i - 1].$1;
}

final _schemes = <(String, Brightness), ColorScheme>{};

ColorScheme _schemeOf(ColorScheme cs, String key) {
  final i = kBotColorKeys.indexOf(key);
  if (i <= 0) return cs;
  return _schemes.putIfAbsent((key, cs.brightness), () => ColorScheme.fromSeed(seedColor: kSeedPalette[i - 1].$2, brightness: cs.brightness));
}

typedef BotPalette = ({Color body, Color ink, Color eye, Color blush, Color trim, Color leaf});

/// The bot's colours from M3 fixed roles, so it looks the same in light and
/// dark themes: shell (primary fixed dim), face screen (on primary fixed),
/// eyes (primary fixed, lifted toward white), blush (tertiary fixed dim).
BotPalette botPalette(ColorScheme cs, String key) {
  final s = _schemeOf(cs, key);
  return (
    body: s.primaryFixedDim,
    ink: s.onPrimaryFixed,
    eye: Color.lerp(s.primaryFixed, Colors.white, 0.4)!,
    blush: s.tertiaryFixedDim,
    trim: Color.lerp(s.primaryFixedDim, s.onPrimaryFixed, 0.32)!,
    leaf: Color.lerp(const Color(0xFF86B872), s.primaryFixedDim, 0.2)!,
  );
}

/// Body and accent colour of the bot (chips, swatches).
(Color, Color) botColors(ColorScheme cs, String key) {
  final s = _schemeOf(cs, key);
  return (s.primaryFixedDim, s.tertiary);
}

OrganicShape _shapeOf(String key) => (kBotShapes[key] ?? kBotShapes[kDefaultBotShape]!).$1;

/// Where the face screen sits on a body, in body radii: centre height, width,
/// height, and the top of the head on the centre line (toppers stand there).
typedef _Face = ({double y, double w, double h, double top});

const _faces = <String, _Face>{
  'pebble': (y: -0.06, w: 1.22, h: 0.82, top: -1),
  'mochi': (y: -0.04, w: 1.4, h: 0.88, top: -0.86),
  'bean': (y: 0.04, w: 1.3, h: 0.7, top: -0.65),
  'circle': (y: -0.02, w: 1.4, h: 0.94, top: -1),
  'squircle': (y: -0.02, w: 1.46, h: 0.98, top: -1),
  'capsule': (y: 0, w: 1.4, h: 0.76, top: -0.74),
  'droplet': (y: 0.2, w: 1.1, h: 0.7, top: -1),
  'ghost': (y: -0.1, w: 1.3, h: 0.82, top: -1),
};

_Face _faceOf(String key) => _faces[key] ?? _faces[kDefaultBotShape]!;

_Face _lerpFace(_Face a, _Face b, double k) =>
    (y: a.y + (b.y - a.y) * k, w: a.w + (b.w - a.w) * k, h: a.h + (b.h - a.h) * k, top: a.top + (b.top - a.top) * k);

/// The animated mascot. [animate] off draws a still pose (lists of shapes,
/// tests); reduced motion keeps only blinking.
class BotAvatar extends StatefulWidget {
  const BotAvatar({
    super.key,
    this.size = 40,
    this.shape = kDefaultBotShape,
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
/// Eye sizes are in body radii; lids are fractions of the eye's height.
class _Pose {
  double eyeW = 0.24, eyeH = 0.32, open = 1, lidT = 0, lidS = 0, lidB = 0, asym = 0;
  double gazeX = 0, gazeY = 0, glow = 1, tip = 0, blush = 0.25, droop = 0;
  double sx = 1, sy = 1, tilt = 0, lift = 0, badge = 0, dream = 0, time = 0;
  // Secondary motion: topper sway and bob (springs), an ear flick.
  double sway = 0, swayV = 0, bob = 0, bobV = 0, flick = 0;
  // The topper of [from] shrinks while the one of [shape] grows; 1 when settled.
  double morph = 1;
  late Float64List radii;
  String shape = kDefaultBotShape, from = kDefaultBotShape;
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
  // Blink, gaze, squint and ear-flick schedules (seconds of ticker time).
  double _nextBlink = 1.5, _blinkAt = -1, _nextGaze = 0.8, _nextSquint = 7, _squintAt = -9, _nextFlick = 3, _flickAt = -1;
  int _flickSide = 1;
  Offset _gazeTarget = Offset.zero;
  Offset? _pointer;
  double _moodAt = 0, _lastLift = 0;

  static const _morphSecs = 0.6;
  static const Curve _quint = Cubic(0.22, 1, 0.36, 1); // ease-out quint

  @override
  void initState() {
    super.initState();
    _pose.radii = shapeRadii(_shapeOf(widget.shape));
    _pose.shape = _pose.from = widget.shape;
    _from = _pose.radii;
    _settle(widget.mood, 0, still: true);
    if (widget.animate) _ticker = createTicker(_tick)..start();
  }

  @override
  void didUpdateWidget(BotAvatar old) {
    super.didUpdateWidget(old);
    if (old.shape != widget.shape) {
      _from = Float64List.fromList(_pose.radii);
      _pose.from = _pose.morph < 0.5 ? _pose.from : _pose.shape;
      _pose.shape = widget.shape;
      if (_ticker == null) {
        _pose.radii = shapeRadii(_shapeOf(widget.shape));
        _pose.from = widget.shape;
        _pose.morph = 1;
      } else {
        _pose.morph = 0;
        _morphAt = _pose.time;
      }
    }
    if (old.mood != widget.mood) {
      _moodAt = _pose.time;
      // Blink switch: the new expression appears behind a blink.
      if (_ticker != null) _blinkAt = _pose.time;
    }
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
      _pose.morph = k;
      if (k >= 1) {
        _morphAt = -1;
        _pose.from = _pose.shape;
      }
    }
    _settle(widget.mood, dt, still: still);
    _frame.value++;
  }

  /// Moves the pose toward the mood's target; dt 0 with still jumps there.
  void _settle(BotMood mood, double dt, {required bool still}) {
    final p = _pose;
    final t = p.time;
    final since = t - _moodAt;
    var eyeW = 0.24, eyeH = 0.32, lidT = 0.0, lidS = 0.0, lidB = 0.0, asym = 0.0, gx = 0.0, gy = 0.0;
    var glow = 1.0, tip = 0.0, blush = 0.25, droop = 0.0;
    var sx = 1.0, sy = 1.0, tilt = 0.0, lift = 0.0, badge = 0.0, dream = 0.0;

    // Idle glances wander and often return to the middle; a near pointer wins.
    if (!still && t >= _nextGaze) {
      _gazeTarget = Offset(_rand.nextDouble() * 1.2 - 0.6, _rand.nextDouble() * 0.7 - 0.35);
      if (_rand.nextDouble() < 0.35) _gazeTarget = Offset.zero;
      _nextGaze = t + 1.4 + _rand.nextDouble() * 2.6;
    }
    if (!still && t >= _nextSquint) {
      _squintAt = t;
      _nextSquint = t + 9 + _rand.nextDouble() * 9;
    }
    final squint = !still && t - _squintAt < 1.1;
    final look = _pointer ?? _gazeTarget;
    final breath = still ? 0.0 : math.sin(2 * math.pi * t / 4.2);
    double hop(double period) => still ? 0.0 : (t % period < 0.5 ? math.sin(math.pi * (t % period) / 0.5) : 0.0);

    switch (mood) {
      case BotMood.idle:
        gx = look.dx;
        gy = look.dy;
        tilt = look.dx * 0.03;
        sy = 1 + 0.018 * breath;
        sx = 1 - 0.008 * breath;
        if (squint) {
          lidT = 0.26;
          lidB = 0.22;
          blush = 0.4;
        }
      case BotMood.listening:
        eyeW = 0.26;
        eyeH = 0.37;
        blush = 0.4;
        gx = _pointer?.dx ?? 0;
        gy = _pointer?.dy ?? 0.3;
        tilt = still ? 0 : 0.07;
        tip = 0.8;
        droop = -0.25;
        sy = 1 + 0.012 * breath;
      case BotMood.thinking:
        eyeW = 0.22;
        eyeH = 0.28;
        lidT = 0.22;
        lidB = 0.12;
        gx = 0.6;
        gy = -0.65;
        tilt = still ? 0.04 : 0.05 * math.sin(t * 1.6);
        tip = still ? 1 : 0.55 + 0.45 * math.sin(t * 5);
        sy = 1 + 0.015 * breath;
      case BotMood.working:
        eyeH = 0.26;
        lidT = 0.3;
        lidS = 0.35;
        gx = still ? 0 : math.sin(t * 3.4) * 0.7;
        gy = 0.15;
        tip = still ? 1 : 0.75 + 0.25 * math.sin(t * 13);
        sy = still ? 1 : 1 + 0.012 * math.sin(t * 9);
      case BotMood.talking:
        final beat = still ? 0.0 : math.sin(2 * math.pi * t * 3.1).abs();
        gx = look.dx * 0.4;
        gy = look.dy * 0.4 - 0.15 * beat;
        lidB = 0.2 * beat;
        sy = 1 + 0.035 * beat;
        sx = 1 - 0.015 * beat;
        blush = 0.45;
        tip = beat;
      case BotMood.happy:
        eyeH = 0.34;
        lidB = 0.62;
        blush = 0.85;
        droop = -0.2;
        lift = still || since > 1.4 ? 0 : -0.1 * math.sin(math.pi * (since * 2.2 % 1)).abs();
        sy = 1 + (lift < 0 ? 0.03 : 0.018 * breath);
      case BotMood.confused:
        asym = 0.42;
        lidT = 0.24;
        lidS = -0.5;
        tilt = -0.13;
        gx = still ? -0.25 : -0.25 + 0.12 * math.sin(t * 7);
        gy = -0.2;
        glow = 0.85;
        droop = 0.35;
      case BotMood.dreaming:
        eyeW = 0.26;
        lidT = 0.8;
        lidS = -0.3;
        gy = 0.35;
        glow = 0.45;
        final slow = still ? 0.0 : math.sin(2 * math.pi * t / 6);
        sy = 1 + 0.04 * slow;
        sx = 1 - 0.015 * slow;
        dream = 1;
        blush = 0.3;
        droop = 1;
      case BotMood.notify:
        eyeW = 0.26;
        eyeH = 0.38;
        badge = 1;
        tip = 1;
        final h = hop(2.6);
        lift = -0.08 * h;
        sy = 1 + 0.03 * h;
    }
    // The ghost floats.
    if (p.shape == 'ghost') lift += still ? -0.05 : -0.05 + 0.03 * math.sin(2 * math.pi * t / 2.8);

    // Blinks every 3–6 s and on every mood change; close fast, open slower.
    var close = 0.0;
    if (dt > 0 || !still) {
      if (t >= _nextBlink) {
        _blinkAt = t;
        _nextBlink = t + 2.8 + _rand.nextDouble() * 3.4;
        if (_rand.nextDouble() < 0.18) _nextBlink = t + 0.34; // a double blink now and then
      }
      final u = t - _blinkAt;
      if (_blinkAt >= 0 && u < 0.2) close = u < 0.08 ? math.sin(math.pi / 2 * u / 0.08) : math.cos(math.pi / 2 * (u - 0.08) / 0.12);
    }
    if (!still && t >= _nextFlick) {
      _flickAt = t;
      _flickSide = _rand.nextBool() ? 1 : -1;
      _nextFlick = t + 4 + _rand.nextDouble() * 6;
    }
    final fu = t - _flickAt;
    p.flick = !still && _flickAt >= 0 && fu < 0.3 ? _flickSide * math.sin(math.pi * fu / 0.3) : 0;

    final k = dt == 0 ? 1.0 : 1 - math.exp(-dt * (still ? 30 : 11));
    double to(double cur, double target) => cur + (target - cur) * k;
    p.eyeW = to(p.eyeW, eyeW);
    p.eyeH = to(p.eyeH, eyeH);
    p.lidT = to(p.lidT, lidT);
    p.lidS = to(p.lidS, lidS);
    p.lidB = to(p.lidB, lidB);
    p.asym = to(p.asym, asym);
    p.gazeX = to(p.gazeX, gx);
    p.gazeY = to(p.gazeY, gy);
    p.glow = to(p.glow, glow);
    p.tip = to(p.tip, tip);
    p.blush = to(p.blush, blush);
    p.droop = to(p.droop, droop);
    p.sx = to(p.sx, sx);
    p.sy = to(p.sy, sy);
    p.tilt = to(p.tilt, tilt);
    p.lift = to(p.lift, lift);
    p.badge = to(p.badge, badge);
    p.dream = to(p.dream, dream);
    p.open = 1 - 0.9 * close;

    // Toppers lag behind the head: a spring toward the lean, a bob against lift.
    final swayTo = -p.tilt * 1.6 - p.gazeX * 0.1 + (still ? 0 : 0.035 * math.sin(t * 1.3));
    if (dt == 0 || still) {
      p.sway = swayTo;
      p.swayV = p.bob = p.bobV = 0;
    } else {
      final lv = (p.lift - _lastLift) / dt;
      p.swayV += (-80 * (p.sway - swayTo) - 7 * p.swayV) * dt;
      p.sway += p.swayV * dt;
      p.bobV += (-110 * (p.bob - (lv * 0.12).clamp(-0.15, 0.15)) - 9 * p.bobV) * dt;
      p.bob = (p.bob + p.bobV * dt).clamp(-0.2, 0.2);
    }
    _lastLift = p.lift;
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
    Widget paint = CustomPaint(
      size: Size.square(widget.size),
      painter: _BotPainter(_pose, _frame, pal: botPalette(cs, widget.color), accent: cs.tertiary, shadow: cs.shadow),
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

/// A closed polygon with every corner rounded by [radius].
Path _roundedPoly(List<Offset> pts, double radius) {
  final path = Path();
  final n = pts.length;
  for (var i = 0; i < n; i++) {
    final prev = pts[(i - 1 + n) % n], cur = pts[i], next = pts[(i + 1) % n];
    final d1 = prev - cur, d2 = next - cur;
    final a = cur + d1 / d1.distance * math.min(radius, d1.distance / 2);
    final b = cur + d2 / d2.distance * math.min(radius, d2.distance / 2);
    i == 0 ? path.moveTo(a.dx, a.dy) : path.lineTo(a.dx, a.dy);
    path.quadraticBezierTo(cur.dx, cur.dy, b.dx, b.dy);
  }
  return path..close();
}

class _BotPainter extends CustomPainter {
  _BotPainter(this.p, Listenable frame, {required this.pal, required this.accent, required this.shadow}) : super(repaint: frame);
  final _Pose p;
  final BotPalette pal;
  final Color accent, shadow;

  @override
  void paint(Canvas canvas, Size size) {
    // Toppers need head room: the body is smaller than the box and sits low.
    final r = size.shortestSide / 2 * 0.7;
    final c = size.center(Offset.zero).translate(0, r * 0.12);
    final fine = size.shortestSide >= 44; // details that only read at larger sizes
    final f = _lerpFace(_faceOf(p.from), _faceOf(p.shape), p.morph);
    final body = shapePath(p.radii, Rect.fromCircle(center: Offset.zero, radius: r));
    final b = body.getBounds();

    // Contact shadow: tighter and darker when the body is down, fainter as it lifts.
    final up = (-p.lift).clamp(0.0, 0.2) / 0.2;
    canvas.drawOval(
      Rect.fromCenter(center: c + Offset(0, b.bottom + r * 0.05), width: b.width * 0.66 * (1 - 0.25 * up) * p.sx, height: r * 0.15 * (1 - 0.3 * up)),
      Paint()
        ..color = shadow.withValues(alpha: 0.16 * (1 - 0.5 * up))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(1, r * 0.06)),
    );

    canvas.save();
    canvas.translate(c.dx, c.dy + p.lift * r);
    canvas.rotate(p.tilt);
    // Squash and stretch about the base so the body sits on the ground.
    canvas.translate(0, b.bottom);
    canvas.scale(p.sx, p.sy);
    canvas.translate(0, -b.bottom);

    _toppers(canvas, r, f, front: false);

    // Matte shell: a soft light from the upper left, a little depth toward the base.
    canvas.drawPath(
      body,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.6),
          radius: 1.2,
          colors: [Color.lerp(pal.body, Colors.white, 0.26)!, pal.body, Color.lerp(pal.body, Colors.black, 0.1)!],
          stops: const [0, 0.5, 1],
        ).createShader(b),
    );
    if (fine) {
      canvas.save();
      canvas.clipPath(body);
      final hy = (f.top + f.y - f.h / 2) / 2 * r;
      canvas.drawOval(
        Rect.fromCenter(center: Offset(-0.3 * r, hy), width: r * 0.5, height: r * 0.22),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.2)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.07),
      );
      canvas.restore();
    }

    // The face screen turns a touch toward the gaze, set into a bezel that is
    // shaded from above.
    final vc = Offset(p.gazeX * 0.03 * r, f.y * r);
    final vr = Rect.fromCenter(center: vc, width: f.w * r, height: f.h * r);
    final rad = Radius.circular(f.h * r * 0.42);
    final bez = vr.inflate(r * 0.05);
    canvas.drawRSuperellipse(
      RSuperellipse.fromRectAndRadius(bez, rad + Radius.circular(r * 0.05)),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(pal.body, Colors.black, 0.22)!, Color.lerp(pal.body, Colors.white, 0.18)!],
        ).createShader(bez),
    );
    final visor = RSuperellipse.fromRectAndRadius(vr, rad);
    canvas.drawRSuperellipse(
      visor,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(pal.ink, Colors.white, 0.08)!, pal.ink],
        ).createShader(vr),
    );
    canvas.save();
    canvas.clipRSuperellipse(visor);
    _face(canvas, vc, f, r);
    if (fine) {
      // Glass: a faint reflection across the upper left.
      canvas.drawOval(
        Rect.fromCenter(center: vc + Offset(-0.28 * vr.width, -0.52 * vr.height), width: vr.width * 0.9, height: vr.height * 0.5),
        Paint()..color = Colors.white.withValues(alpha: 0.06),
      );
    }
    canvas.restore();
    if (fine) {
      canvas.drawRSuperellipse(
        visor,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(0.6, r * 0.014)
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.center,
            colors: [Colors.white.withValues(alpha: 0.18), Colors.white.withValues(alpha: 0)],
          ).createShader(vr),
      );
    }

    _toppers(canvas, r, f, front: true);

    if (p.badge > 0.02) {
      // A notification light on the screen's corner.
      final at = Offset(vr.right - r * 0.04, vr.top + r * 0.04);
      final pulse = 1 + 0.08 * math.sin(p.time * 4);
      final rad = r * 0.15 * p.badge * pulse;
      canvas.drawCircle(at, rad + math.max(1.5, r * 0.055), Paint()..color = pal.body);
      canvas.drawCircle(at, rad, Paint()..color = accent);
    }
    canvas.restore();

    if (p.dream > 0.02) {
      // Three small dots drift up and away from the sleeping head.
      for (var i = 0; i < 3; i++) {
        final ph = (p.time / 2.8 + i / 3) % 1;
        final o = c + Offset(r * (0.62 + ph * 0.45), r * (f.top * 0.7 - ph * 0.6));
        canvas.drawCircle(o, r * (0.045 + 0.04 * ph), Paint()..color = pal.trim.withValues(alpha: p.dream * (1 - ph) * 0.7));
      }
    }
  }

  /// Blush and eyes on the screen. Each eye is a rounded rectangle cut by a
  /// sloped top lid and a bottom ellipse (the smile), with a soft bloom.
  void _face(Canvas canvas, Offset vc, _Face f, double r) {
    final spread = f.w / 1.32;
    final dx = 0.25 * spread * r;
    final y = vc.dy + p.gazeY * 0.08 * r;
    if (p.blush > 0.02) {
      final bp = Paint()
        ..color = pal.blush.withValues(alpha: 0.6 * p.blush.clamp(0.0, 1.0))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(0.8, r * 0.04));
      for (final side in const [-1, 1]) {
        canvas.drawOval(Rect.fromCenter(center: Offset(vc.dx + side * (dx + 0.07 * r), y + r * 0.21), width: r * 0.2, height: r * 0.08), bp);
      }
    }
    final bloom = Paint()
      ..color = pal.eye.withValues(alpha: 0.5 * p.glow)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(0.8, r * 0.07));
    final fill = Paint()..color = Color.lerp(pal.ink, pal.eye, 0.35 + 0.65 * p.glow)!;
    for (final side in const [-1, 1]) {
      // Looking aside, the outer eye grows (curiosity).
      final cur = 1 + 0.22 * math.max(0.0, side * p.gazeX) - 0.06 * math.max(0.0, -side * p.gazeX);
      final w = p.eyeW * r * (1 + side * p.asym * 0.12);
      final h = math.max(0.035 * r, p.eyeH * r * cur * (1 + side * p.asym * 0.4) * p.open);
      final ec = Offset(vc.dx + side * dx + p.gazeX * 0.13 * spread * r, y - side * p.asym * 0.04 * r);
      final rect = Rect.fromCenter(center: ec, width: w, height: h);
      var eye = Path()..addRSuperellipse(RSuperellipse.fromRectAndRadius(rect, Radius.circular(math.min(w, h) * 0.45)));
      if (p.lidT > 0.01) {
        // Positive slope lowers the inner end (determined), negative the outer (sleepy, worried).
        final lid = rect.top + h * p.lidT;
        final inner = ec.dx - side * w, outer = ec.dx + side * w;
        final yi = lid + p.lidS * h * 0.4, yo = lid - p.lidS * h * 0.4;
        eye = Path.combine(
          PathOperation.difference,
          eye,
          Path()
            ..moveTo(outer, rect.top - h)
            ..lineTo(inner, rect.top - h)
            ..lineTo(inner, yi)
            ..quadraticBezierTo(ec.dx, (yi + yo) / 2 + h * 0.1, outer, yo)
            ..close(),
        );
      }
      if (p.lidB > 0.01) {
        final top = rect.bottom - h * p.lidB * 0.8;
        eye = Path.combine(PathOperation.difference, eye, Path()..addOval(Rect.fromLTWH(ec.dx - w * 0.9, top, w * 1.8, h * 1.5)));
      }
      if (p.glow > 0.05) canvas.drawPath(eye, bloom);
      canvas.drawPath(eye, fill);
    }
  }

  void _toppers(Canvas canvas, double r, _Face f, {required bool front}) {
    if (p.from != p.shape && p.morph < 1) _topper(canvas, p.from, 1 - p.morph, r, f, front);
    _topper(canvas, p.shape, p.from == p.shape ? 1 : p.morph, r, f, front);
  }

  /// One body's topper, scaled by [k] about where it meets the head.
  void _topper(Canvas canvas, String shape, double k, double r, _Face f, bool front) {
    if (k < 0.02) return;
    final top = f.top * r;
    final at = shape == 'capsule' ? Offset.zero : Offset(0, top);
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.scale(k);
    canvas.translate(-at.dx, -at.dy);
    switch ((shape, front)) {
      case ('pebble', false):
        _antenna(canvas, Offset(0, top + 0.12 * r), 0, 0.4 * r, 0.1 * r);
      case ('squircle', false):
        for (final side in const [-1, 1]) {
          _antenna(canvas, Offset(side * 0.3 * r, top + 0.12 * r), side * 0.32, 0.36 * r, 0.075 * r);
        }
      case ('mochi', false):
        for (final side in const [-1, 1]) {
          _ear(canvas, side, Offset(side * 0.5 * r, top + 0.16 * r), r, cat: true);
        }
      case ('circle', false):
        for (final side in const [-1, 1]) {
          _ear(canvas, side, Offset(side * 0.3 * r, top + 0.12 * r), r, cat: false);
        }
      case ('bean', false):
        _sprout(canvas, Offset(0.02 * r, top + 0.1 * r), r);
      case ('capsule', false):
        // Headphone band over the head.
        canvas.drawArc(
          Rect.fromCenter(center: Offset(0, -0.04 * r), width: 2.06 * r, height: 1.74 * r),
          math.pi + 0.28,
          math.pi - 0.56,
          false,
          Paint()
            ..color = pal.trim
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = math.max(1.2, r * 0.09),
        );
      case ('capsule', true):
        for (final side in const [-1, 1]) {
          final cup = Rect.fromCenter(center: Offset(side * 0.99 * r, 0.02 * r), width: 0.22 * r, height: 0.52 * r);
          canvas.drawRSuperellipse(
            RSuperellipse.fromRectAndRadius(cup, Radius.circular(0.11 * r)),
            Paint()
              ..shader = LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color.lerp(pal.trim, Colors.white, 0.2)!, pal.trim],
              ).createShader(cup),
          );
          _light(canvas, cup.center, 0.035 * r, Color.lerp(pal.trim, Colors.white, 0.35)!);
        }
      default:
    }
    canvas.restore();
  }

  /// A small light that turns to the eye colour and glows while the bot works.
  void _light(Canvas canvas, Offset at, double rad, Color rest) {
    final lit = Color.lerp(rest, pal.eye, p.tip.clamp(0.0, 1.0))!;
    if (p.tip > 0.02) {
      canvas.drawCircle(
        at,
        rad * 1.6,
        Paint()
          ..color = pal.eye.withValues(alpha: 0.5 * p.tip.clamp(0.0, 1.0))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(0.8, rad * 0.8)),
      );
    }
    canvas.drawCircle(
      at,
      rad,
      Paint()
        ..shader = RadialGradient(center: const Alignment(-0.4, -0.45), colors: [Color.lerp(lit, Colors.white, 0.45)!, lit])
            .createShader(Rect.fromCircle(center: at, radius: rad)),
    );
  }

  /// A stem from [base] (inside the head) leaning [angle] plus the sway, ending in a ball.
  void _antenna(Canvas canvas, Offset base, double angle, double len, double ball) {
    final a = angle + p.sway;
    final tip = base + Offset(math.sin(a), -math.cos(a)) * len * (1 + p.bob);
    final ctrl = base + Offset(math.sin(angle), -math.cos(angle)) * len * 0.55;
    canvas.drawPath(
      Path()
        ..moveTo(base.dx, base.dy)
        ..quadraticBezierTo(ctrl.dx, ctrl.dy, tip.dx, tip.dy),
      Paint()
        ..color = pal.trim
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(1.2, ball * 0.65),
    );
    _light(canvas, tip, ball, pal.blush);
  }

  /// A cat ear (rounded triangle) or a bunny ear (long oval), drawn behind
  /// the head; ears perk with interest, droop when sleepy and flick now and then.
  void _ear(Canvas canvas, int side, Offset base, double r, {required bool cat}) {
    final droop = p.droop + (side > 0 ? p.asym * 1.2 : 0);
    final flick = math.max(0.0, side * p.flick);
    final rot = side * ((cat ? 0.26 : 0.14) + 0.22 * flick + droop * (cat ? 0.35 : 0.9)) + p.sway * (cat ? 0.35 : 0.5);
    canvas.save();
    canvas.translate(base.dx, base.dy);
    canvas.rotate(rot);
    final outer = Paint()..color = Color.lerp(pal.body, Colors.black, 0.04)!;
    final inner = Paint()..color = pal.blush.withValues(alpha: 0.85);
    if (cat) {
      canvas.drawPath(_roundedPoly([Offset(-0.24 * r, 0.06 * r), Offset(0, -0.46 * r), Offset(0.24 * r, 0.06 * r)], 0.12 * r), outer);
      canvas.drawPath(_roundedPoly([Offset(-0.12 * r, 0.02 * r), Offset(0, -0.3 * r), Offset(0.12 * r, 0.02 * r)], 0.06 * r), inner);
    } else {
      canvas.drawOval(Rect.fromCenter(center: Offset(0, -0.27 * r), width: 0.26 * r, height: 0.64 * r), outer);
      canvas.drawOval(Rect.fromCenter(center: Offset(0, -0.3 * r), width: 0.12 * r, height: 0.42 * r), inner);
    }
    canvas.restore();
  }

  /// A seedling: a short stem and two leaves that sway with the head.
  void _sprout(Canvas canvas, Offset base, double r) {
    final a = p.sway * 1.2;
    final tip = base + Offset(math.sin(a), -math.cos(a)) * 0.3 * r * (1 + p.bob);
    final ctrl = base + Offset(0, -0.18 * r);
    canvas.drawPath(
      Path()
        ..moveTo(base.dx, base.dy)
        ..quadraticBezierTo(ctrl.dx, ctrl.dy, tip.dx, tip.dy),
      Paint()
        ..color = Color.lerp(pal.leaf, Colors.black, 0.15)!
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(1.2, r * 0.055),
    );
    for (final (ang, len) in const [(-1.0, 0.26), (0.9, 0.21)]) {
      canvas.save();
      canvas.translate(tip.dx, tip.dy);
      canvas.rotate(a + ang);
      final leaf = Rect.fromCenter(center: Offset(0, -len / 2 * r), width: len * 0.52 * r, height: len * r);
      canvas.drawOval(
        leaf,
        Paint()
          ..shader = LinearGradient(colors: [Color.lerp(pal.leaf, Colors.white, 0.2)!, pal.leaf]).createShader(leaf),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_BotPainter o) => o.pal != pal || o.accent != accent || o.shadow != shadow || o.p != p;
}
