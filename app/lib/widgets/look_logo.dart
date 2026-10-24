import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The app's drawn mark, the launcher icon itself (app/branding/icon.svg):
/// an ink cookie holding a play glyph on a paper tile.
class LookLogo extends StatelessWidget {
  const LookLogo({super.key, required this.size, this.label = 'Look Studio'});
  final double size;

  /// Read by screen readers; null when the name is written beside the mark.
  final String? label;

  static const asset = 'branding/icon.svg';

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
        asset,
        width: size,
        height: size,
        semanticsLabel: label,
        excludeFromSemantics: label == null,
      );
}
