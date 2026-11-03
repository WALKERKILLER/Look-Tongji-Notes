import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/prefs.dart';
import '../../theme/theme.dart';

/// Paper and material cards use light surfaces, including in a dark app theme.
class StudyCanvasSurface extends StatelessWidget {
  const StudyCanvasSurface({
    super.key,
    required this.prefs,
    required this.child,
    this.fullscreen = false,
  });

  final UiPrefs prefs;
  final Widget child;
  final bool fullscreen;

  @override
  Widget build(BuildContext context) {
    final ambient = Theme.of(context);
    final scheme = ambient.brightness == Brightness.light
        ? ambient.colorScheme
        : buildScheme(
            prefs,
            Brightness.light,
            systemAccent: ambient.colorScheme.primary,
          );
    final paper = buildTheme(scheme, prefs);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: fullscreen
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: Theme(
        data: paper,
        child: Material(
          color: fullscreen ? Colors.black : scheme.surface,
          child: SafeArea(
            top: !fullscreen,
            bottom: !fullscreen,
            left: !fullscreen,
            right: !fullscreen,
            child: child,
          ),
        ),
      ),
    );
  }
}
