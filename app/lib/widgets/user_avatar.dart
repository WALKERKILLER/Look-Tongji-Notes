import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/profile.dart';
import 'course_visuals.dart';
import 'organic_shapes.dart';

/// Background tones for emoji/initial avatars; null follows the theme.
const kAvatarTones = <Color?>[
  null,
  Color(0xFFE57373),
  Color(0xFFFFB74D),
  Color(0xFFDCE775),
  Color(0xFF81C784),
  Color(0xFF4DB6AC),
  Color(0xFF4FC3F7),
  Color(0xFF7986CB),
  Color(0xFFBA68C8),
  Color(0xFFA1887F),
];

final _schemes = <(int, Brightness), ColorScheme>{};

ColorScheme _schemeOf(Color seed, Brightness b) =>
    _schemes.putIfAbsent((seed.toARGB32(), b), () => ColorScheme.fromSeed(seedColor: seed, brightness: b));

/// (container, onContainer) colours for a tone index.
(Color, Color) avatarToneColors(BuildContext context, int tone) {
  final t = Theme.of(context);
  final seed = kAvatarTones[tone.clamp(0, kAvatarTones.length - 1)];
  final s = seed == null ? t.colorScheme : _schemeOf(seed, t.brightness);
  return (s.primaryContainer, s.onPrimaryContainer);
}

String userDisplayName(BuildContext context) {
  final a = context.select<AppState, (String, String)>((s) => (s.auth.realname, s.auth.username));
  final fallback = a.$1.isNotEmpty ? a.$1 : a.$2;
  return context.select<UserProfile, String>((p) => p.displayName(fallback));
}

/// The configured user avatar.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, this.size = 40});
  final double size;
  @override
  Widget build(BuildContext context) {
    final p = context.watch<UserProfile>();
    return AvatarView(kind: p.kind, value: p.value, tone: p.tone, frame: p.frame, name: userDisplayName(context), size: size);
  }
}

/// Renders an avatar from explicit values (used for previews and pickers).
class AvatarView extends StatelessWidget {
  const AvatarView({
    super.key,
    required this.kind,
    required this.value,
    this.tone = 0,
    this.frame = AvatarFrame.circle,
    this.name = '',
    this.size = 40,
  });
  final AvatarKind kind;
  final String value;
  final int tone;
  final AvatarFrame frame;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = avatarToneColors(context, tone);
    Widget initial() => ColoredBox(
          color: bg,
          child: Center(
            child: Text(
              name.isEmpty ? '?' : name.characters.first.toUpperCase(),
              style: TextStyle(fontSize: size * 0.42, fontWeight: FontWeight.w600, color: fg, height: 1),
            ),
          ),
        );
    final Widget child = switch (kind) {
      AvatarKind.emoji => ColoredBox(
          color: bg,
          child: Center(child: Text(value, style: TextStyle(fontSize: size * 0.54, height: 1.15), textAlign: TextAlign.center)),
        ),
      AvatarKind.art => _ArtAvatar(seed: value),
      AvatarKind.file => Image.file(File(value), fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, _, _) => initial()),
      AvatarKind.url => Image.network(value, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, _, _) => initial()),
      AvatarKind.initial => initial(),
    };
    return SizedBox.square(
      dimension: size,
      child: frame == AvatarFrame.circle ? ClipOval(child: child) : ClipPath(clipper: _FrameClipper(frame), child: child),
    );
  }
}

class _FrameClipper extends CustomClipper<Path> {
  const _FrameClipper(this.frame);
  final AvatarFrame frame;
  @override
  Path getClip(Size size) {
    final shape = switch (frame) {
      AvatarFrame.squircle => OrganicShape.squircle,
      AvatarFrame.cookie => OrganicShape.cookie9,
      _ => OrganicShape.clover8,
    };
    return shapePath(shapeRadii(shape), Offset.zero & size);
  }

  @override
  bool shouldReclip(_FrameClipper old) => old.frame != frame;
}

/// Generated organic avatar, from the same vocabulary as the course covers.
class _ArtAvatar extends StatelessWidget {
  const _ArtAvatar({required this.seed});
  final String seed;
  @override
  Widget build(BuildContext context) {
    final spec = CourseArtSpec.of('avatar:$seed');
    final hue = (spec.seed % 360).toDouble();
    final s = _schemeOf(HSLColor.fromAHSL(1, hue, 0.5, 0.5).toColor(), Theme.of(context).brightness);
    return CustomPaint(painter: CourseArtPainter(spec: spec, s: s, t: 0, spin: 0, layout: spec.layout == 2 ? 1 : spec.layout), child: const SizedBox.expand());
  }
}
