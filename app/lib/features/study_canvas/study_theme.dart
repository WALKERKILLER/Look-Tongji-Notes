part of 'study_canvas.dart';

/// Canvas chrome colours, derived from the app's [ColorScheme] so the study
/// workspace follows the same surfaces, lines and accents as the rest of the
/// app (including dark mode) instead of carrying its own palette.
@immutable
class StudyChrome {
  const StudyChrome({
    required this.ink,
    required this.inkSoft,
    required this.inkFaint,
    required this.line,
    required this.surface,
    required this.surfaceSoft,
    required this.surfaceStrong,
    required this.accent,
    required this.onAccent,
    required this.accentSoft,
    required this.onAccentSoft,
    required this.danger,
    required this.shadow,
    required this.paper,
    required this.paperInk,
  });

  factory StudyChrome.of(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return StudyChrome(
      ink: cs.onSurface,
      inkSoft: cs.onSurfaceVariant,
      inkFaint: cs.outline,
      line: cs.outlineVariant,
      surface: cs.surface,
      surfaceSoft: cs.surfaceContainerLow,
      surfaceStrong: cs.surfaceContainerHigh,
      accent: cs.primary,
      onAccent: cs.onPrimary,
      accentSoft: cs.primaryContainer,
      onAccentSoft: cs.onPrimaryContainer,
      danger: cs.error,
      shadow: cs.shadow.withValues(alpha: dark ? 0.45 : 0.12),
      // Cards sit one tonal step above the paper (lighter in dark mode).
      paper: dark ? cs.surfaceContainerHigh : Colors.white,
      paperInk: dark ? cs.onSurface : const Color(0xff25344a),
    );
  }

  /// Primary text and strokes on the chrome.
  final Color ink;

  /// Secondary text and inactive icons.
  final Color inkSoft;

  /// Hints, dividers between icons and disabled glyphs.
  final Color inkFaint;

  /// Hairlines and container borders.
  final Color line;

  /// Panel background.
  final Color surface;

  /// Slightly raised fill (chips, inactive swatches).
  final Color surfaceSoft;

  /// Pressed/hover fill and the dock's grab handle.
  final Color surfaceStrong;

  final Color accent;
  final Color onAccent;

  /// Tinted accent fill for the active tool.
  final Color accentSoft;
  final Color onAccentSoft;

  final Color danger;
  final Color shadow;

  /// The page itself, and the ink drawn on it.
  final Color paper;
  final Color paperInk;

  /// Translucent accent for selection previews.
  Color get accentWash => accent.withValues(alpha: 0.12);

  Color get inkWash => ink.withValues(alpha: 0.08);

  @override
  bool operator ==(Object other) =>
      other is StudyChrome &&
      other.ink == ink &&
      other.inkSoft == inkSoft &&
      other.inkFaint == inkFaint &&
      other.line == line &&
      other.surface == surface &&
      other.surfaceSoft == surfaceSoft &&
      other.surfaceStrong == surfaceStrong &&
      other.accent == accent &&
      other.onAccent == onAccent &&
      other.accentSoft == accentSoft &&
      other.onAccentSoft == onAccentSoft &&
      other.danger == danger &&
      other.shadow == shadow &&
      other.paper == paper &&
      other.paperInk == paperInk;

  @override
  int get hashCode => Object.hash(
    ink,
    inkSoft,
    inkFaint,
    line,
    surface,
    surfaceSoft,
    surfaceStrong,
    accent,
    onAccent,
    accentSoft,
    onAccentSoft,
    danger,
    shadow,
    paper,
    paperInk,
  );
}
