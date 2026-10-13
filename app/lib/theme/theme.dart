import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'prefs.dart';
import 'tokens.dart';

const _cjkFallback = ['HarmonyOS Sans SC', 'Noto Sans CJK SC', 'Source Han Sans SC', 'PingFang SC', 'Microsoft YaHei'];

ColorScheme buildScheme(UiPrefs p, Brightness b, {Color? systemAccent}) {
  final seed = p.dynamicColor && systemAccent != null ? systemAccent : p.seed;
  return ColorScheme.fromSeed(
    seedColor: seed,
    brightness: b,
    dynamicSchemeVariant: p.variant,
    contrastLevel: p.contrast.value,
  );
}

/// Material 3 theme with component styling tuned to the M3 spec: tonal
/// surfaces instead of shadows, full-round actions, 8dp spacing.
ThemeData buildTheme(ColorScheme cs, UiPrefs p) {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: cs,
    fontFamily: p.fontFamily,
    fontFamilyFallback: _cjkFallback,
    visualDensity: p.compactDensity ? VisualDensity.compact : VisualDensity.standard,
    splashFactory: InkSparkle.splashFactory,
  );
  final tt = base.textTheme;
  // Slightly taller line height reads better for CJK paragraphs.
  final text = tt.copyWith(
    bodyLarge: tt.bodyLarge?.copyWith(height: 1.6),
    bodyMedium: tt.bodyMedium?.copyWith(height: 1.55),
    titleLarge: tt.titleLarge?.copyWith(fontWeight: FontWeight.w500),
    headlineSmall: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w500),
    headlineMedium: tt.headlineMedium?.copyWith(fontWeight: FontWeight.w500, letterSpacing: -0.25),
    displaySmall: tt.displaySmall?.copyWith(fontWeight: FontWeight.w500, letterSpacing: -0.5),
  );
  final fullShape = const StadiumBorder();
  const btnPadding = EdgeInsets.symmetric(horizontal: 24, vertical: 10);

  return base.copyWith(
    textTheme: text,
    scaffoldBackgroundColor: cs.surface,
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
      TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
    }),
    appBarTheme: AppBarTheme(
      backgroundColor: cs.surface,
      surfaceTintColor: cs.surfaceTint,
      scrolledUnderElevation: 3,
      centerTitle: false,
      titleTextStyle: text.titleLarge?.copyWith(color: cs.onSurface),
      systemOverlayStyle: cs.brightness == Brightness.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: Corners.all(Corners.md)),
      clipBehavior: Clip.antiAlias,
    ),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(shape: fullShape, padding: btnPadding)),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(shape: fullShape, padding: btnPadding)),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(shape: fullShape)),
    elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(shape: fullShape, padding: btnPadding)),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(shape: fullShape)),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      elevation: 3,
      focusElevation: 3,
      hoverElevation: 4,
      backgroundColor: cs.primaryContainer,
      foregroundColor: cs.onPrimaryContainer,
      shape: RoundedRectangleBorder(borderRadius: Corners.all(Corners.lg)),
      extendedTextStyle: text.labelLarge,
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: Corners.all(Corners.sm)),
      side: BorderSide(color: cs.outlineVariant),
      labelStyle: text.labelLarge,
      showCheckmark: true,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: false,
      border: OutlineInputBorder(borderRadius: Corners.all(Corners.sm)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    searchBarTheme: SearchBarThemeData(
      elevation: const WidgetStatePropertyAll(0),
      backgroundColor: WidgetStatePropertyAll(cs.surfaceContainerHigh),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16)),
      constraints: const BoxConstraints(minHeight: 56, maxWidth: 720),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: cs.surface,
      indicatorColor: cs.secondaryContainer,
      indicatorShape: fullShape,
      labelType: NavigationRailLabelType.all,
      selectedLabelTextStyle: text.labelMedium?.copyWith(color: cs.onSurface, fontWeight: FontWeight.w600),
      unselectedLabelTextStyle: text.labelMedium?.copyWith(color: cs.onSurfaceVariant),
      groupAlignment: -1,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: cs.surfaceContainer,
      indicatorColor: cs.secondaryContainer,
      indicatorShape: fullShape,
      height: 72,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => text.labelMedium?.copyWith(
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? cs.onSurface : cs.onSurfaceVariant,
          )),
    ),
    navigationDrawerTheme: NavigationDrawerThemeData(
      indicatorShape: fullShape,
      backgroundColor: cs.surfaceContainerLow,
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: Corners.all(Corners.md)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      iconColor: cs.onSurfaceVariant,
    ),
    dividerTheme: DividerThemeData(color: cs.outlineVariant, space: 1, thickness: 1),
    dialogTheme: DialogThemeData(
      backgroundColor: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: Corners.all(Corners.xl)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: cs.surfaceContainerLow,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Corners.xl))),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: cs.inverseSurface,
      contentTextStyle: text.bodyMedium?.copyWith(color: cs.onInverseSurface),
      actionTextColor: cs.inversePrimary,
      shape: RoundedRectangleBorder(borderRadius: Corners.all(Corners.xs)),
      width: 480,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: cs.inverseSurface, borderRadius: Corners.all(Corners.xs)),
      textStyle: text.bodySmall?.copyWith(color: cs.onInverseSurface),
      waitDuration: const Duration(milliseconds: 500),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(cs.surfaceContainer),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: Corners.all(Corners.md))),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 8)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: cs.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: Corners.all(Corners.md)),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(visualDensity: VisualDensity.standard),
    ),
    sliderTheme: SliderThemeData(
      year2023: false,
      trackHeight: 12,
      inactiveTrackColor: cs.secondaryContainer,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      year2023: false,
      linearTrackColor: cs.secondaryContainer,
      circularTrackColor: cs.secondaryContainer,
    ),
    switchTheme: SwitchThemeData(
      thumbIcon: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? const Icon(Icons.check_rounded) : null,
      ),
    ),
  );
}
