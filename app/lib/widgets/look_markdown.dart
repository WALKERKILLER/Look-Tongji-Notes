import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:val_latex_flutter/val_latex_flutter.dart';

import '../core/app_state.dart';
import '../core/lookd_service.dart';
import '../core/open_path.dart';
import '../theme/tokens.dart';
import 'states.dart';
import 'timestamp_links.dart';

/// A `look://` reference inside Markdown: a moment of a lecture, one of its
/// slides, a passage of uploaded courseware, a whole lecture or a file in
/// the course library.
sealed class LookRef {
  const LookRef();

  static LookRef? parse(String url) {
    final u = Uri.tryParse(url);
    // lookstudio:// is the same link as exported for other programs.
    if (u == null || (u.scheme != 'look' && u.scheme != 'lookstudio')) return null;
    final t = TimeLink.parse(url);
    if (t != null) return TimeRef(t.lectureId, t.seconds);
    final seg = u.pathSegments;
    if (u.host == 'slide' && seg.length >= 2) {
      final idx = int.tryParse(seg[1]);
      return idx == null ? null : SlideRef(seg[0], idx);
    }
    if (u.host == 'courseware' && seg.isNotEmpty) {
      return CoursewareRef(seg[0], u.queryParameters['file'] ?? '', u.queryParameters['q'] ?? '');
    }
    if (u.host == 'lecture' && seg.isNotEmpty) return LectureRef(seg[0]);
    if (u.host == 'file' && seg.isNotEmpty) return FileRef(seg.join('/'));
    return null;
  }
}

class TimeRef extends LookRef {
  const TimeRef(this.lectureId, this.seconds);
  final String lectureId; // empty: the lecture in context
  final int seconds;
}

class SlideRef extends LookRef {
  const SlideRef(this.lectureId, this.idx);
  final String lectureId;
  final int idx;
}

class CoursewareRef extends LookRef {
  const CoursewareRef(this.lectureId, this.file, this.query);
  final String lectureId, file, query;
}

/// A lecture without a time: opens the player where the user left off.
class LectureRef extends LookRef {
  const LectureRef(this.lectureId);
  final String lectureId;
}

/// A file in the course library, by its library-relative path.
class FileRef extends LookRef {
  const FileRef(this.path);
  final String path;
}

const _imageExts = {'.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp'};

/// Opens a library file: images in the viewer, anything else with the
/// system's default app.
Future<void> openLibraryFile(BuildContext context, String path) async {
  final rel = p.posix.normalize(path);
  if (rel.startsWith('..') || p.posix.isAbsolute(rel)) {
    showSnack(context, '这个文件不在课程库里');
    return;
  }
  if (_imageExts.contains(p.posix.extension(rel).toLowerCase())) {
    await showImageViewer(context, context.read<AppState>().api.fileUrl(rel));
    return;
  }
  final root = context.read<LookdService>().libraryRoot;
  final ok = root.isNotEmpty && await openPath(p.join(root, rel));
  if (!ok && context.mounted) showSnack(context, '没能打开 ${p.posix.basename(rel)}');
}

/// Opens a link that is not a `look://` reference: web and mail links in
/// the system's handler; anything else says why nothing happens.
Future<void> openPlainLink(BuildContext context, String url) async {
  final u = Uri.tryParse(url.trim());
  final ok = u != null && const {'http', 'https', 'mailto'}.contains(u.scheme) && await launchUrl(u, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) showSnack(context, '这个链接无法打开');
}

// Regions that must reach the renderer untouched, in priority order, plus the
// two repairs: bare math environments and `$ x $` with padding spaces.
final _regions = RegExp(
  [
    r'(\$\$[\s\S]*?\$\$)', // 1 display $$
    r'(\\\[[\s\S]*?\\\])', // 2 display \[ \]
    r'(\\\([\s\S]*?\\\))', // 3 inline \( \)
    r'(`[^`\n]*`)', // 4 inline code
    r'(\\begin\{((?:equation|align|gather|multline|aligned|gathered|alignat|cases|array|split|[pbvBV]?matrix)\*?)\}[\s\S]*?\\end\{\6\})', // 5 bare environment (6 = name)
    r'(?<![\\$])\$ +([^$\n]+?) +\$(?!\$)', // 7 spaced inline
    r'((?<![\\$])\$[^$\n]+?\$(?!\$))', // 8 inline $
  ].join('|'),
);
final _fenceLine = RegExp(r'^\s*(```|~~~)');
final _mathy = RegExp(r'[\\^_=]');
final _cjk = RegExp(r'[㐀-鿿]');

/// Prepares model-written Markdown for rendering. Fenced and inline code and
/// all math stay as written; bare `\begin{aligned}…` blocks get `$$`
/// delimiters, `$ x $` loses its padding when it is clearly math, and
/// `[mm:ss]` timestamps elsewhere become `look://` links.
String prepareMarkdown(String md, {String lectureId = ''}) {
  final out = StringBuffer();
  final text = StringBuffer();
  var fence = false;
  void flushText() {
    if (text.isEmpty) return;
    out.write(_prepareText(text.toString(), lectureId));
    text.clear();
  }

  for (final line in md.split('\n')) {
    final isFence = _fenceLine.hasMatch(line);
    if (fence || isFence) {
      flushText();
      out.write('$line\n');
      if (isFence) fence = !fence;
    } else {
      text.write('$line\n');
    }
  }
  flushText();
  final s = out.toString();
  return md.endsWith('\n') ? s : s.substring(0, s.length - 1);
}

String _prepareText(String s, String lectureId) {
  final buf = StringBuffer();
  var at = 0;
  for (final m in _regions.allMatches(s)) {
    buf.write(linkifyPlain(s.substring(at, m.start), lectureId: lectureId));
    if (m[5] != null) {
      buf.write('\n\$\$\n${m[5]}\n\$\$\n');
    } else if (m[7] != null) {
      final body = m[7]!;
      buf.write(_mathy.hasMatch(body) && !_cjk.hasMatch(body) ? '\$$body\$' : m[0]);
    } else {
      buf.write(m[0]);
    }
    at = m.end;
  }
  buf.write(linkifyPlain(s.substring(at), lectureId: lectureId));
  return buf.toString();
}

/// The app's Markdown renderer for chat, notes and parsed courseware: LaTeX
/// (inline at text size, display formulas scrolling sideways when wide),
/// tappable timestamps and references, and images from the course library.
class LookMarkdown extends StatelessWidget {
  const LookMarkdown(
    this.data, {
    super.key,
    this.style,
    this.lectureId = '',
    this.baseDir = '',
    this.onRef,
    this.onImage,
    this.isStreaming = false,
    this.animation = GptMarkdownAnimation.none,
    this.codeBuilder,
  });

  final String data;
  final TextStyle? style;

  /// Lecture that bare `[mm:ss]` timestamps refer to (empty: the one in context).
  final String lectureId;

  /// Library-relative folder that relative image paths resolve against
  /// (a note's folder, or a parsed courseware folder).
  final String baseDir;
  final ValueChanged<LookRef>? onRef;

  /// Tap on an image; defaults to a zoomable viewer.
  final void Function(String url)? onImage;
  final bool isStreaming;
  final GptMarkdownAnimation animation;
  final CodeBlockBuilder? codeBuilder;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GptMarkdown(
      prepareMarkdown(data, lectureId: lectureId),
      style: style,
      useDollarSignsForLatex: true,
      isStreaming: isStreaming,
      animation: animation,
      codeBuilder: codeBuilder,
      styleSheet: GptMarkdownStyleSheet(
        latex: LatexStyle(scrollBlockHorizontally: true, padding: const EdgeInsets.symmetric(vertical: Space.xs)),
      ),
      inlineLatexBuilder: (d) => d.asWidgetSpan(
        Math.tex(
          d.tex,
          textStyle: d.style.copyWith(fontSize: (d.style.fontSize ?? 14) * 1.1, color: d.style.color ?? cs.onSurface),
          parseOptions: const ParseOptions(strict: Strict.ignore, streaming: true),
          onError: (_, _) => Text(d.source, style: d.style.copyWith(fontFamily: 'monospace', color: cs.error)),
        ),
      ),
      onLinkTap: (url, _) {
        final ref = LookRef.parse(url);
        ref != null && onRef != null ? onRef!(ref) : openPlainLink(context, url);
      },
      inlineLinkBuilder: (d) {
        final ref = LookRef.parse(d.url);
        if (ref == null || onRef == null) return d.defaultSpan();
        return WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: switch (ref) {
            TimeRef(:final lectureId) => TimestampChip(label: d.label, external: lectureId.isNotEmpty && lectureId != this.lectureId, onTap: () => onRef!(ref)),
            SlideRef() => RefChip(icon: Icons.slideshow_outlined, label: d.label, onTap: () => onRef!(ref)),
            CoursewareRef() => RefChip(icon: Icons.description_outlined, label: d.label, onTap: () => onRef!(ref)),
            LectureRef() => RefChip(icon: Icons.ondemand_video_rounded, label: d.label, onTap: () => onRef!(ref)),
            FileRef() => RefChip(icon: Icons.attach_file_rounded, label: d.label, onTap: () => onRef!(ref)),
          },
        );
      },
      imageBuilder: (context, url, w, h) => _MdImage(url: resolveImageUrl(context, url, baseDir), width: w, height: h, onTap: onImage),
    );
  }
}

/// Turns an image reference from Markdown into a fetchable URL.
String resolveImageUrl(BuildContext context, String url, String baseDir) {
  final api = context.read<AppState>().api;
  final ref = LookRef.parse(url);
  if (ref is SlideRef) return slideImageUrl(api.baseUrl, api.token, ref.lectureId, ref.idx);
  if (url.startsWith('look://file/')) return api.fileUrl(Uri.decodeFull(url.substring('look://file/'.length)));
  if (url.startsWith('http://') || url.startsWith('https://') || url.startsWith('data:')) return url;
  final rel = p.posix.normalize(p.posix.join(baseDir, Uri.decodeFull(url)));
  return api.fileUrl(rel);
}

String slideImageUrl(String base, String token, String lectureId, int idx) => '$base/api/lectures/$lectureId/slides/$idx/image?token=$token';

class _MdImage extends StatelessWidget {
  const _MdImage({required this.url, this.width, this.height, this.onTap});
  final String url;
  final double? width, height;
  final void Function(String url)? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: height ?? 420, maxWidth: width ?? double.infinity),
        child: MouseRegion(
          cursor: SystemMouseCursors.zoomIn,
          child: GestureDetector(
            onTap: () => onTap != null ? onTap!(url) : showImageViewer(context, url),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Corners.md),
              child: Image.network(
                url,
                fit: BoxFit.contain,
                frameBuilder: (_, child, frame, sync) => AnimatedOpacity(opacity: frame == null && !sync ? 0 : 1, duration: Motion.medium1, child: child),
                errorBuilder: (_, _, _) => Container(
                  padding: const EdgeInsets.all(Space.md),
                  color: cs.surfaceContainerHighest,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.broken_image_outlined, size: 18, color: cs.onSurfaceVariant),
                    const SizedBox(width: Space.sm),
                    Text('图片不可用', style: TextStyle(color: cs.onSurfaceVariant)),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-window, zoomable image.
Future<void> showImageViewer(BuildContext context, String url) => showDialog(
      context: context,
      useRootNavigator: true,
      barrierColor: Colors.black87,
      builder: (context) => Dialog.fullscreen(
        backgroundColor: Colors.transparent,
        child: Stack(children: [
          Positioned.fill(child: InteractiveViewer(maxScale: 6, child: Center(child: Image.network(url, fit: BoxFit.contain)))),
          Positioned(
            top: Space.lg,
            right: Space.lg,
            child: IconButton.filledTonal(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
          ),
        ]),
      ),
    );

/// Compact tonal chip for a slide or courseware reference.
class RefChip extends StatelessWidget {
  const RefChip({super.key, required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = DefaultTextStyle.of(context).style;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Material(
        color: cs.tertiaryContainer,
        borderRadius: BorderRadius.circular(Corners.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(Corners.sm),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 1, 7, 1),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: (base.fontSize ?? 14) * 0.95, color: cs.onTertiaryContainer),
              const SizedBox(width: 3),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: base.copyWith(color: cs.onTertiaryContainer, fontSize: (base.fontSize ?? 14) * 0.88, fontWeight: FontWeight.w600, height: 1.3)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
