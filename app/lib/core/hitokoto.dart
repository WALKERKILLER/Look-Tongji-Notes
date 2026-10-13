import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// One line from hitokoto.cn (一言).
class Quote {
  const Quote(this.text, {this.from = '', this.who = ''});
  final String text, from, who;

  /// "—— 作者《出处》"
  String get source {
    final f = from.isEmpty ? '' : (from.startsWith('《') ? from : '《$from》');
    final w = who.trim();
    if (w.isEmpty && f.isEmpty) return '';
    return '—— $w$f';
  }

  Map<String, String> toJson() => {'text': text, 'from': from, 'who': who};
  static Quote fromJson(Map m) => Quote('${m['text'] ?? ''}', from: '${m['from'] ?? ''}', who: '${m['who'] ?? ''}');
}

/// Used when offline and nothing is cached yet.
const _fallback = [
  Quote('学而不思则罔，思而不学则殆。', from: '论语'),
  Quote('博学之，审问之，慎思之，明辨之，笃行之。', from: '礼记·中庸'),
  Quote('路漫漫其修远兮，吾将上下而求索。', from: '离骚', who: '屈原'),
  Quote('纸上得来终觉浅，绝知此事要躬行。', from: '冬夜读书示子聿', who: '陆游'),
  Quote('不积跬步，无以至千里；不积小流，无以成江海。', from: '荀子·劝学'),
];

/// Fetches a quote once per app session; refresh on demand. The last quote
/// is kept so the greeting renders instantly next launch or offline.
abstract final class Hitokoto {
  static Quote? _current;
  static Quote? get current => _current;

  static Future<Quote> get({List<String> types = const ['d', 'i', 'k'], bool refresh = false}) async {
    if (_current != null && !refresh) return _current!;
    final sp = await SharedPreferences.getInstance();
    try {
      final q = [for (final t in types) 'c=$t', 'encode=json', 'max_length=48'].join('&');
      final r = await http.get(Uri.parse('https://v1.hitokoto.cn/?$q')).timeout(const Duration(seconds: 6));
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      final m = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
      final quote = Quote('${m['hitokoto'] ?? ''}'.trim(), from: '${m['from'] ?? ''}'.trim(), who: '${m['from_who'] ?? ''}'.trim());
      if (quote.text.isEmpty) throw Exception('empty');
      await sp.setString('hitokoto.last', jsonEncode(quote.toJson()));
      return _current = quote;
    } catch (_) {
      if (refresh || _current == null) {
        final raw = sp.getString('hitokoto.last');
        if (raw != null && !refresh) return _current = Quote.fromJson(jsonDecode(raw) as Map);
        return _current = _fallback[math.Random().nextInt(_fallback.length)];
      }
      return _current!;
    }
  }

  /// The cached quote from a previous launch, for an instant first frame.
  static Future<Quote?> cached() async {
    final raw = (await SharedPreferences.getInstance()).getString('hitokoto.last');
    return raw == null ? null : Quote.fromJson(jsonDecode(raw) as Map);
  }
}
