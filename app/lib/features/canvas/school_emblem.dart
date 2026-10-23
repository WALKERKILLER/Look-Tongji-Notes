import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Emblems bundled with the app (public domain, see assets/schools/NOTICE).
/// Others are fetched once from the school's `emblem_url` and cached in the
/// app support folder, because they may not be redistributed.
const _bundled = {'fudan': 'assets/schools/fudan.svg'};

final _cache = <String, Future<String?>>{};

Future<String?> _emblem(String id, String url) => _cache[id] ??= () async {
  try {
    final dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'emblems'));
    final f = File(p.join(dir.path, '$id.svg'));
    if (await f.exists()) return await f.readAsString();
    if (url.isEmpty) return null;
    final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
    final body = r.body.trimLeft();
    if (r.statusCode != 200 || r.bodyBytes.length > 1 << 20 || !(body.startsWith('<svg') || body.startsWith('<?xml'))) return null;
    await dir.create(recursive: true);
    await f.writeAsString(r.body);
    return r.body;
  } catch (_) {
    _cache.remove(id); // try again next time
    return null;
  }
}();

/// A school's emblem on a white disc, so its brand colours read the same in
/// light and dark themes. Falls back to the school's first character.
class SchoolEmblem extends StatelessWidget {
  const SchoolEmblem({super.key, required this.id, this.name = '', this.url = '', this.size = 40});
  final String id;
  final String name;
  final String url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fallback = Center(
      child: id == 'other'
          ? Icon(Icons.school_outlined, size: size * 0.5, color: cs.onSecondaryContainer)
          : Text(name.isEmpty ? '?' : name.characters.first, style: TextStyle(fontSize: size * 0.42, fontWeight: FontWeight.w600, color: cs.onSecondaryContainer)),
    );
    Widget mark(Widget child) => Padding(padding: EdgeInsets.all(size * 0.08), child: child);
    final asset = _bundled[id];
    final Widget child;
    if (asset != null) {
      child = mark(SvgPicture.asset(asset, semanticsLabel: '$name校徽'));
    } else if (id == 'other') {
      child = fallback;
    } else {
      child = FutureBuilder<String?>(
        future: _emblem(id, url),
        builder: (_, s) => AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: s.data == null ? KeyedSubtree(key: const ValueKey(0), child: fallback) : mark(SvgPicture.string(s.data!, key: const ValueKey(1), semanticsLabel: '$name校徽')),
        ),
      );
    }
    final hasMark = asset != null || id != 'other';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: hasMark ? Colors.white : cs.secondaryContainer,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}
