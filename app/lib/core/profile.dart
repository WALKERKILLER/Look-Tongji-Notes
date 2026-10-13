import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the avatar comes from.
enum AvatarKind { initial, emoji, art, file, url }

/// Outline of the avatar.
enum AvatarFrame {
  circle('圆形'),
  squircle('圆角方'),
  cookie('曲奇'),
  flower('花瓣');

  const AvatarFrame(this.label);
  final String label;
}

/// The local user's display profile: nickname, avatar and home greeting
/// options. Kept on this device only; the Tongji account is untouched.
class UserProfile extends ChangeNotifier {
  UserProfile._(this._sp);
  final SharedPreferences _sp;

  static Future<UserProfile> load() async => UserProfile._(await SharedPreferences.getInstance()).._read();

  String nickname = '';
  AvatarKind kind = AvatarKind.initial;

  /// emoji character, art seed, absolute file path or image URL.
  String value = '';

  /// Background tone index for emoji/initial avatars (see [kAvatarTones]).
  int tone = 0;
  AvatarFrame frame = AvatarFrame.circle;
  bool showQuote = true;

  /// Hitokoto categories: d 文学, i 诗词, k 哲学, h 影视, a 动画, j 网易云.
  List<String> quoteTypes = const ['d', 'i', 'k'];

  /// Nickname, else the Tongji real name, else the student id.
  String displayName(String fallback) => nickname.isNotEmpty ? nickname : fallback;

  void _read() {
    final raw = _sp.getString('profile');
    if (raw == null) return;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      nickname = m['nickname'] ?? '';
      kind = AvatarKind.values.byName(m['kind'] ?? 'initial');
      value = m['value'] ?? '';
      tone = m['tone'] ?? 0;
      frame = AvatarFrame.values.byName(m['frame'] ?? 'circle');
      showQuote = m['showQuote'] ?? true;
      quoteTypes = ((m['quoteTypes'] as List?) ?? quoteTypes).cast<String>();
    } catch (_) {
      // Corrupt profile falls back to defaults.
    }
  }

  void _save() {
    _sp.setString(
      'profile',
      jsonEncode({
        'nickname': nickname,
        'kind': kind.name,
        'value': value,
        'tone': tone,
        'frame': frame.name,
        'showQuote': showQuote,
        'quoteTypes': quoteTypes,
      }),
    );
    notifyListeners();
  }

  void setNickname(String v) {
    final t = v.trim();
    if (t == nickname) return;
    nickname = t.length > 24 ? t.substring(0, 24) : t;
    _save();
  }

  void update(void Function(UserProfile p) f) {
    f(this);
    _save();
  }

  Future<void> _setAvatar(AvatarKind k, String v) async {
    final old = kind == AvatarKind.file ? value : '';
    kind = k;
    value = v;
    _save();
    if (old.isNotEmpty && old != v) {
      try {
        await File(old).delete();
      } catch (_) {}
    }
  }

  Future<void> setEmoji(String emoji, {int? tone}) {
    if (tone != null) this.tone = tone;
    return _setAvatar(AvatarKind.emoji, emoji);
  }

  Future<void> setArt(String seed) => _setAvatar(AvatarKind.art, seed);
  Future<void> setUrl(String url) => _setAvatar(AvatarKind.url, url);
  Future<void> setQQ(String qq) => _setAvatar(AvatarKind.url, qqAvatarUrl(qq));
  Future<void> reset() => _setAvatar(AvatarKind.initial, '');

  /// Copies [source] into the app's support directory so the avatar survives
  /// the original being moved or deleted.
  Future<void> setFile(String source) async {
    final dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'avatar'));
    await dir.create(recursive: true);
    final dest = p.join(dir.path, 'avatar-${DateTime.now().millisecondsSinceEpoch}${p.extension(source).toLowerCase()}');
    await File(source).copy(dest);
    await _setAvatar(AvatarKind.file, dest);
  }

  static String qqAvatarUrl(String qq) => 'https://q2.qlogo.cn/headimg_dl?dst_uin=$qq&spec=640';
  static final _qq = RegExp(r'^[1-9]\d{4,11}$');
  static bool validQQ(String s) => _qq.hasMatch(s.trim());

  static String randomSeed() => math.Random().nextInt(1 << 31).toRadixString(36);
}
