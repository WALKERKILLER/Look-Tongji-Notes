import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/prefs.dart';

/// The study canvas follows the app's theme: paper, cards and ink are toned
/// for dark mode (see studyPaperTone and inkOnDark); printed pages (PDF,
/// images) keep their own light background.
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
    final cs = Theme.of(context).colorScheme;
    final dark = cs.brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: fullscreen || dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: Material(
        color: fullscreen ? Colors.black : cs.surfaceContainerLow,
        child: SafeArea(
          top: !fullscreen,
          bottom: !fullscreen,
          left: !fullscreen,
          right: !fullscreen,
          // The canvas's glass panes share one backdrop capture.
          child: BackdropGroup(child: child),
        ),
      ),
    );
  }
}
