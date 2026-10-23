import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/l10n.dart';

enum ContrastLevel {
  standard(0),
  medium(0.5),
  high(1);

  const ContrastLevel(this.value);
  final double value;

  String get label => switch (this) {
        standard => l10n.levelStandard,
        medium => l10n.levelMedium,
        high => l10n.levelHigh,
      };
}

/// User-tunable presentation preferences (kept on device, not in the library).
class UiPrefs extends ChangeNotifier {
  UiPrefs._(this._sp);
  final SharedPreferences _sp;

  static Future<UiPrefs> load() async => UiPrefs._(await SharedPreferences.getInstance()).._read();

  ThemeMode themeMode = ThemeMode.system;
  bool dynamicColor = true;
  Color seed = const Color(0xFF3F6CB4); // 同济蓝
  DynamicSchemeVariant variant = DynamicSchemeVariant.tonalSpot;
  ContrastLevel contrast = ContrastLevel.standard;
  double textScale = 1.0;
  String? fontFamily;
  bool compactDensity = false;
  bool reduceMotion = false;

  // Assistant rendering
  bool chatBubbles = true;
  bool showThinking = true;
  GptMarkdownAnimation streamAnimation = GptMarkdownAnimation.fade;
  double chatTextScale = 1.0;
  bool assistantDocked = true;

  // Course page: lectures run from the first to the last unless flipped.
  bool lecturesNewestFirst = false;

  // Player
  double defaultSpeed = 1.0;
  double boostSpeed = 2.0;
  int seekStepSec = 10;
  bool autoResume = true;
  bool slideFollow = true;
  double subtitleScale = 1.0;
  bool showSubtitles = true;

  void _read() {
    final raw = _sp.getString('ui');
    if (raw == null) return;
    try {
      _fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Corrupt prefs fall back to defaults.
    }
  }

  void _fromJson(Map<String, dynamic> m) {
    themeMode = ThemeMode.values.byName(m['themeMode'] ?? 'system');
    dynamicColor = m['dynamicColor'] ?? dynamicColor;
    seed = Color(m['seed'] ?? seed.toARGB32());
    variant = DynamicSchemeVariant.values.byName(m['variant'] ?? variant.name);
    contrast = ContrastLevel.values.byName(m['contrast'] ?? contrast.name);
    textScale = (m['textScale'] ?? 1.0).toDouble();
    fontFamily = m['fontFamily'];
    compactDensity = m['compactDensity'] ?? false;
    reduceMotion = m['reduceMotion'] ?? false;
    chatBubbles = m['chatBubbles'] ?? true;
    showThinking = m['showThinking'] ?? true;
    streamAnimation = GptMarkdownAnimation.values.byName(m['streamAnimation'] ?? streamAnimation.name);
    chatTextScale = (m['chatTextScale'] ?? 1.0).toDouble();
    assistantDocked = m['assistantDocked'] ?? true;
    lecturesNewestFirst = m['lecturesNewestFirst'] ?? false;
    defaultSpeed = (m['defaultSpeed'] ?? 1.0).toDouble();
    boostSpeed = (m['boostSpeed'] ?? 2.0).toDouble();
    seekStepSec = m['seekStepSec'] ?? 10;
    autoResume = m['autoResume'] ?? true;
    slideFollow = m['slideFollow'] ?? true;
    subtitleScale = (m['subtitleScale'] ?? 1.0).toDouble();
    showSubtitles = m['showSubtitles'] ?? true;
  }

  Map<String, dynamic> _toJson() => {
        'themeMode': themeMode.name,
        'dynamicColor': dynamicColor,
        'seed': seed.toARGB32(),
        'variant': variant.name,
        'contrast': contrast.name,
        'textScale': textScale,
        'fontFamily': fontFamily,
        'compactDensity': compactDensity,
        'reduceMotion': reduceMotion,
        'chatBubbles': chatBubbles,
        'showThinking': showThinking,
        'streamAnimation': streamAnimation.name,
        'chatTextScale': chatTextScale,
        'assistantDocked': assistantDocked,
        'lecturesNewestFirst': lecturesNewestFirst,
        'defaultSpeed': defaultSpeed,
        'boostSpeed': boostSpeed,
        'seekStepSec': seekStepSec,
        'autoResume': autoResume,
        'slideFollow': slideFollow,
        'subtitleScale': subtitleScale,
        'showSubtitles': showSubtitles,
      };

  /// The preferences as stored (the assistant reads its registry keys).
  Map<String, dynamic> toJson() => _toJson();

  /// Applies stored-form values (the bot's setting changes and their undo);
  /// an invalid value leaves every preference as it was.
  void applyJson(Map<String, dynamic> patch) {
    final before = _toJson();
    try {
      _fromJson({...before, ...patch});
    } catch (_) {
      _fromJson(before);
      return;
    }
    update((_) {});
  }

  /// Apply a mutation, notify listeners and persist.
  void update(void Function(UiPrefs p) change) {
    change(this);
    notifyListeners();
    _sp.setString('ui', jsonEncode(_toJson()));
  }
}

/// Curated seed colors shown in the appearance picker.
final kSeedPalette = <(String, Color)>[
  (l10n.colorTongjiBlue, Color(0xFF3F6CB4)),
  (l10n.colorIndigo, Color(0xFF2E6E6A)),
  (l10n.colorPine, Color(0xFF4F7A3A)),
  (l10n.colorAmber, Color(0xFFB0782A)),
  (l10n.colorCinnabar, Color(0xFFB4443A)),
  (l10n.colorBegonia, Color(0xFFB0507A)),
  (l10n.colorWisteria, Color(0xFF6E5AA8)),
  (l10n.colorGraphite, Color(0xFF5D6670)),
];

final kVariantLabels = <DynamicSchemeVariant, String>{
  DynamicSchemeVariant.tonalSpot: l10n.schemeTonalSpot,
  DynamicSchemeVariant.neutral: l10n.schemeNeutral,
  DynamicSchemeVariant.vibrant: l10n.schemeVibrant,
  DynamicSchemeVariant.expressive: l10n.schemeExpressive,
  DynamicSchemeVariant.fidelity: l10n.schemeFidelity,
  DynamicSchemeVariant.content: l10n.schemeContent,
  DynamicSchemeVariant.monochrome: l10n.schemeMonochrome,
};

/// Font families offered in settings (null = system default).
final kFontChoices = <(String, String?)>[
  (l10n.fontSystem, null),
  (l10n.fontHarmonySans, 'HarmonyOS Sans SC'),
  (l10n.fontSourceHanSans, 'Noto Sans CJK SC'),
  (l10n.fontLxgwWenKai, 'LXGW WenKai'),
  (l10n.fontInterWithSystem, 'Inter'),
];
