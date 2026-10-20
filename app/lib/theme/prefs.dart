import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ContrastLevel {
  standard(0, '标准'),
  medium(0.5, '中'),
  high(1, '高');

  const ContrastLevel(this.value, this.label);
  final double value;
  final String label;
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
const kSeedPalette = <(String, Color)>[
  ('同济蓝', Color(0xFF3F6CB4)),
  ('黛青', Color(0xFF2E6E6A)),
  ('松绿', Color(0xFF4F7A3A)),
  ('琥珀', Color(0xFFB0782A)),
  ('朱砂', Color(0xFFB4443A)),
  ('海棠', Color(0xFFB0507A)),
  ('藤紫', Color(0xFF6E5AA8)),
  ('石墨', Color(0xFF5D6670)),
];

const kVariantLabels = <DynamicSchemeVariant, String>{
  DynamicSchemeVariant.tonalSpot: '柔和',
  DynamicSchemeVariant.neutral: '中性',
  DynamicSchemeVariant.vibrant: '鲜明',
  DynamicSchemeVariant.expressive: '表现',
  DynamicSchemeVariant.fidelity: '忠实',
  DynamicSchemeVariant.content: '内容',
  DynamicSchemeVariant.monochrome: '单色',
};

/// Font families offered in settings (null = system default).
const kFontChoices = <(String, String?)>[
  ('系统默认', null),
  ('鸿蒙黑体', 'HarmonyOS Sans SC'),
  ('思源黑体', 'Noto Sans CJK SC'),
  ('霞鹜文楷', 'LXGW WenKai'),
  ('Inter + 系统中文', 'Inter'),
];
