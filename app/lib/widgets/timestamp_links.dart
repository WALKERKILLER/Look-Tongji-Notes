import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../theme/tokens.dart';

const _ts = r'(\d{1,2}:\d{2}(?::\d{2})?)';
// A range `[a]–[b]`, or a single `[a]`, not already followed by a link target.
final _tsRef = RegExp('\\[$_ts\\](?:\\s*[–—~-]\\s*\\[$_ts\\])?(?!\\()');
final _fence = RegExp(r'^(```|~~~)', multiLine: true);
final _inlineCode = RegExp(r'`[^`\n]*`');

int? parseClock(String s) {
  final p = s.split(':').map(int.tryParse).toList();
  if (p.any((x) => x == null)) return null;
  return p.fold<int>(0, (a, b) => a * 60 + b!);
}

/// Rewrites bare `[mm:ss]`, `[h:mm:ss]` and `[a]–[b]` references into
/// `look://` links so Markdown renders them as tappable timestamps. With
/// [lectureId] the link names its lecture; otherwise it means "this lecture".
/// Code spans and fenced blocks are left untouched.
String linkifyTimestamps(String md, {String lectureId = ''}) {
  if (!md.contains(':')) return md;
  final out = StringBuffer();
  var inFence = false;
  for (final part in md.split(_fence)) {
    // split() drops the delimiters; fences alternate code/text.
    if (inFence) {
      out.write('```$part');
    } else {
      if (out.isNotEmpty) out.write('```');
      out.write(_linkText(part, lectureId));
    }
    inFence = !inFence;
  }
  return out.toString();
}

String _linkText(String text, String lectureId) {
  final buf = StringBuffer();
  var at = 0;
  for (final m in _inlineCode.allMatches(text)) {
    buf.write(_linkPlain(text.substring(at, m.start), lectureId));
    buf.write(m[0]);
    at = m.end;
  }
  buf.write(_linkPlain(text.substring(at), lectureId));
  return buf.toString();
}

/// [linkifyTimestamps] for text known to hold no code or math.
String linkifyPlain(String s, {String lectureId = ''}) => _linkPlain(s, lectureId);

String _linkPlain(String s, String lectureId) => s.replaceAllMapped(_tsRef, (m) {
      final start = parseClock(m[1]!);
      if (start == null) return m[0]!;
      final end = m[2] == null ? null : parseClock(m[2]!);
      final label = m[2] == null ? m[1]! : '${m[1]}–${m[2]}';
      final base = lectureId.isEmpty ? 'look://seek' : 'look://lecture/$lectureId';
      return '[$label]($base?t=$start${end != null ? '&end=$end' : ''})';
    });

/// A parsed `look://` timestamp link.
class TimeLink {
  const TimeLink(this.lectureId, this.seconds);
  final String lectureId; // empty: the lecture in context
  final int seconds;

  static TimeLink? parse(String url) {
    final u = Uri.tryParse(url);
    if (u == null || (u.scheme != 'look' && u.scheme != 'lookstudio')) return null;
    final t = int.tryParse(u.queryParameters['t'] ?? '');
    if (t == null) return null;
    if (u.host == 'seek') return TimeLink('', t);
    if (u.host == 'lecture' && u.pathSegments.isNotEmpty) return TimeLink(u.pathSegments.first, t);
    return null;
  }
}

/// `inlineLinkBuilder` for GptMarkdown: timestamp links become tonal chips,
/// other links keep the default look.
InlineSpan timestampLinkBuilder(LinkBuildDetails d, {required void Function(TimeLink) onSeek}) {
  final link = TimeLink.parse(d.url);
  if (link == null) return d.defaultSpan();
  return WidgetSpan(
    alignment: PlaceholderAlignment.middle,
    child: TimestampChip(label: d.label, external: link.lectureId.isNotEmpty, onTap: () => onSeek(link)),
  );
}

class TimestampChip extends StatefulWidget {
  const TimestampChip({super.key, required this.label, required this.onTap, this.external = false});
  final String label;
  final VoidCallback onTap;
  final bool external;
  @override
  State<TimestampChip> createState() => _TimestampChipState();
}

class _TimestampChipState extends State<TimestampChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = DefaultTextStyle.of(context).style;
    final fg = _hover ? cs.onPrimary : cs.onSecondaryContainer;
    return Tooltip(
      message: widget.external ? '打开对应课次并跳到这里' : '跳到这里播放',
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: Motion.short4,
            curve: Motion.standard,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            padding: const EdgeInsets.fromLTRB(4, 1, 7, 1),
            decoration: BoxDecoration(
              color: _hover ? cs.primary : cs.secondaryContainer,
              borderRadius: BorderRadius.circular(_hover ? Corners.sm : Corners.full),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(widget.external ? Icons.open_in_new_rounded : Icons.play_arrow_rounded, size: (base.fontSize ?? 14) * (widget.external ? 0.9 : 1.1), color: fg),
              const SizedBox(width: 2),
              Text(
                widget.label,
                style: base.copyWith(
                  color: fg,
                  fontSize: (base.fontSize ?? 14) * 0.88,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
