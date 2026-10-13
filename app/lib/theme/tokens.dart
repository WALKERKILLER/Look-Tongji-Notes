import 'package:flutter/animation.dart';
import 'package:flutter/widgets.dart';

/// 8dp spacing scale (M3 2026 spacing system).
abstract final class Space {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
  static const double huge = 64;

  static const EdgeInsets page = EdgeInsets.symmetric(horizontal: 24);
  static const EdgeInsets pageCompact = EdgeInsets.symmetric(horizontal: 16);
}

/// M3 shape scale, including the Expressive increased corners.
abstract final class Corners {
  static const double none = 0;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double lgIncreased = 20;
  static const double xl = 28;
  static const double xlIncreased = 32;
  static const double xxl = 48;
  static const double full = 999;

  static BorderRadius all(double r) => BorderRadius.circular(r);
}

/// M3 motion tokens. Springs are approximated with emphasized curves where
/// Flutter components expect durations.
abstract final class Motion {
  static const Curve emphasized = Cubic(0.2, 0, 0, 1);
  static const Curve emphasizedDecelerate = Cubic(0.05, 0.7, 0.1, 1);
  static const Curve emphasizedAccelerate = Cubic(0.3, 0, 0.8, 0.15);
  static const Curve standard = Cubic(0.2, 0, 0, 1);
  static const Curve standardDecelerate = Cubic(0, 0, 0, 1);
  static const Curve standardAccelerate = Cubic(0.3, 0, 1, 1);

  static const Duration short1 = Duration(milliseconds: 50);
  static const Duration short2 = Duration(milliseconds: 100);
  static const Duration short3 = Duration(milliseconds: 150);
  static const Duration short4 = Duration(milliseconds: 200);
  static const Duration medium1 = Duration(milliseconds: 250);
  static const Duration medium2 = Duration(milliseconds: 300);
  static const Duration medium3 = Duration(milliseconds: 350);
  static const Duration medium4 = Duration(milliseconds: 400);
  static const Duration long2 = Duration(milliseconds: 500);
  static const Duration long4 = Duration(milliseconds: 600);

  /// Expressive "fast spatial" spring, as a Flutter spring description.
  static const SpringDescription springFast = SpringDescription(mass: 1, stiffness: 1400, damping: 67);
  static const SpringDescription springDefault = SpringDescription(mass: 1, stiffness: 700, damping: 48);
}

/// Window size classes (dp).
enum SizeClass { compact, medium, expanded, large, extraLarge }

SizeClass sizeClassOf(double width) {
  if (width < 600) return SizeClass.compact;
  if (width < 840) return SizeClass.medium;
  if (width < 1200) return SizeClass.expanded;
  if (width < 1600) return SizeClass.large;
  return SizeClass.extraLarge;
}

extension SizeClassX on BuildContext {
  SizeClass get sizeClass => sizeClassOf(MediaQuery.sizeOf(this).width);
  bool get isCompact => sizeClass == SizeClass.compact;
}

/// Readable content width on large windows.
const double kMaxContentWidth = 1040;
