import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'look_markdown.dart';

/// A heading of a reader document; [section] is the section it opens.
class MdHeading {
  const MdHeading(this.level, this.title, this.section);
  final int level;
  final String title;
  final int section;
}

/// Markdown split at headings (outside code fences), so long documents build
/// lazily and the reader can jump to and track sections.
class MdDoc {
  MdDoc(String md) {
    final heading = RegExp(r'^(#{1,4})\s+(.+?)\s*#*\s*$');
    final fence = RegExp(r'^\s*(```|~~~)');
    var buf = StringBuffer();
    var inFence = false;
    for (final line in md.split('\n')) {
      if (fence.hasMatch(line)) inFence = !inFence;
      final m = inFence ? null : heading.firstMatch(line);
      if (m != null) {
        if (buf.toString().trim().isNotEmpty || sections.isNotEmpty) sections.add(buf.toString());
        buf = StringBuffer();
        headings.add(MdHeading(m[1]!.length, _plain(m[2]!), sections.length));
      }
      buf.writeln(line);
    }
    if (buf.toString().trim().isNotEmpty) sections.add(buf.toString());
    lower = [for (final s in sections) s.toLowerCase()];
  }

  final sections = <String>[];
  final headings = <MdHeading>[];
  late final List<String> lower;

  static String _plain(String s) => s.replaceAll(RegExp(r'[*_`]|\$'), '').replaceAll(RegExp(r'\[([^\]]*)\]\([^)]*\)'), r'$1').trim();

  /// Sections containing [q] (case-insensitive), in order.
  List<int> find(String q) {
    final k = q.trim().toLowerCase();
    if (k.isEmpty) return const [];
    return [for (var i = 0; i < lower.length; i++) if (lower[i].contains(k)) i];
  }
}

/// Lets a parent drive a [MarkdownReader]: jump, search, and follow position.
class MdReaderController extends ChangeNotifier {
  _MarkdownReaderState? _state;

  /// Index of the section at the top of the viewport.
  int current = 0;

  /// 0…1 reading progress.
  double progress = 0;

  void jumpToSection(int i) => _state?._jump(i);
  void jumpToHeading(MdHeading h) => _state?._jump(h.section);

  /// Jumps to the first section containing [q]; returns false when absent.
  bool reveal(String q) {
    final s = _state;
    if (s == null) return false;
    final hits = s.doc.find(q);
    if (hits.isEmpty) return false;
    s._jump(hits.first, flash: true);
    return true;
  }

  void _update(int c, double p) {
    if (c == current && (p - progress).abs() < 0.005) return;
    current = c;
    progress = p;
    notifyListeners();
  }
}

/// Reading surface: a centred column of Markdown sections with a header.
class MarkdownReader extends StatefulWidget {
  const MarkdownReader({
    super.key,
    required this.doc,
    required this.controller,
    this.header,
    this.lectureId = '',
    this.baseDir = '',
    this.onRef,
    this.maxWidth = 760,
    this.padding = const EdgeInsets.fromLTRB(Space.xl, Space.lg, Space.xl, Space.huge),
    this.initialQuery,
  });

  final MdDoc doc;
  final MdReaderController controller;
  final Widget? header;
  final String lectureId, baseDir;
  final ValueChanged<LookRef>? onRef;
  final double maxWidth;
  final EdgeInsets padding;

  /// Jump to the first passage containing this text once laid out.
  final String? initialQuery;

  @override
  State<MarkdownReader> createState() => _MarkdownReaderState();
}

class _MarkdownReaderState extends State<MarkdownReader> {
  final _scroll = ScrollController();
  final _keys = <int, GlobalKey>{};
  int? _flash;

  MdDoc get doc => widget.doc;

  @override
  void initState() {
    super.initState();
    widget.controller._state = this;
    _scroll.addListener(_track);
    final q = widget.initialQuery;
    if (q != null && q.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.controller.reveal(q);
      });
    }
  }

  @override
  void didUpdateWidget(MarkdownReader old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) widget.controller._state = this;
  }

  @override
  void dispose() {
    if (widget.controller._state == this) widget.controller._state = null;
    _scroll.dispose();
    super.dispose();
  }

  void _track() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final viewport = context.findRenderObject() as RenderBox?;
    if (viewport == null) return;
    var cur = 0;
    for (final e in _keys.entries) {
      final box = e.value.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
      if (top <= 96 && e.key > cur) cur = e.key;
    }
    widget.controller._update(cur, pos.maxScrollExtent <= 0 ? 1 : (pos.pixels / pos.maxScrollExtent).clamp(0.0, 1.0));
  }

  Future<void> _jump(int i, {bool flash = false}) async {
    if (flash) setState(() => _flash = i);
    for (var attempt = 0; attempt < 4; attempt++) {
      if (!mounted) return;
      final ctx = _keys[i]?.currentContext;
      if (ctx != null && ctx.mounted) {
        await Scrollable.ensureVisible(ctx, alignment: 0.02, duration: Motion.long2, curve: Motion.emphasized);
        break;
      }
      if (!_scroll.hasClients) return;
      // Not built yet: move near it by proportion, then retry next frame.
      final f = doc.sections.length <= 1 ? 0.0 : i / doc.sections.length;
      _scroll.jumpTo((_scroll.position.maxScrollExtent * f).clamp(0.0, _scroll.position.maxScrollExtent));
      await WidgetsBinding.instance.endOfFrame;
    }
    if (flash) {
      await Future.delayed(const Duration(milliseconds: 1600));
      if (mounted && _flash == i) setState(() => _flash = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final n = doc.sections.length + (widget.header == null ? 0 : 1);
    return SelectionArea(
      child: ListView.builder(
        controller: _scroll,
        padding: widget.padding,
        itemCount: n,
        itemBuilder: (context, k) {
          Widget child;
          if (widget.header != null && k == 0) {
            child = widget.header!;
          } else {
            final i = k - (widget.header == null ? 0 : 1);
            child = KeyedSubtree(
              key: _keys.putIfAbsent(i, GlobalKey.new),
              child: AnimatedContainer(
                duration: Motion.long2,
                curve: Motion.standard,
                padding: const EdgeInsets.symmetric(horizontal: Space.sm),
                decoration: BoxDecoration(
                  color: _flash == i ? cs.tertiaryContainer.withValues(alpha: 0.45) : Colors.transparent,
                  borderRadius: BorderRadius.circular(Corners.md),
                ),
                child: LookMarkdown(
                  doc.sections[i],
                  style: tt.bodyLarge?.copyWith(height: 1.75),
                  lectureId: widget.lectureId,
                  baseDir: widget.baseDir,
                  onRef: widget.onRef,
                ),
              ),
            );
          }
          return Center(child: ConstrainedBox(constraints: BoxConstraints(maxWidth: widget.maxWidth), child: child));
        },
      ),
    );
  }
}

/// Contents list in the style of an M3 navigation drawer: indented by level,
/// the section being read marked with a pill.
class ReaderToc extends StatelessWidget {
  const ReaderToc({super.key, required this.doc, required this.controller, this.onPicked});
  final MdDoc doc;
  final MdReaderController controller;
  final VoidCallback? onPicked;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    if (doc.headings.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Text('这篇没有小标题', style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
      );
    }
    final top = doc.headings.map((h) => h.level).reduce((a, b) => a < b ? a : b);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        // The heading whose section is being read: the last one at or above it.
        var active = 0;
        for (var i = 0; i < doc.headings.length; i++) {
          if (doc.headings[i].section <= controller.current) active = i;
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
          itemCount: doc.headings.length,
          itemBuilder: (context, i) {
            final h = doc.headings[i];
            final on = i == active;
            final depth = (h.level - top).clamp(0, 3);
            return Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Material(
                color: on ? cs.secondaryContainer : Colors.transparent,
                shape: const StadiumBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {
                    controller.jumpToHeading(h);
                    onPicked?.call();
                  },
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(Space.lg + depth * Space.md, 10, Space.lg, 10),
                    child: Text(
                      h.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: (depth == 0 ? tt.labelLarge : tt.bodyMedium)?.copyWith(
                        color: on ? cs.onSecondaryContainer : (depth == 0 ? cs.onSurface : cs.onSurfaceVariant),
                        fontWeight: on ? FontWeight.w600 : null,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// In-document search bar: query field, match counter, previous/next.
class ReaderSearchBar extends StatefulWidget {
  const ReaderSearchBar({super.key, required this.doc, required this.controller, required this.onClose});
  final MdDoc doc;
  final MdReaderController controller;
  final VoidCallback onClose;
  @override
  State<ReaderSearchBar> createState() => _ReaderSearchBarState();
}

class _ReaderSearchBarState extends State<ReaderSearchBar> {
  final _q = TextEditingController();
  List<int> _hits = const [];
  int _at = 0;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  void _go(int d) {
    if (_hits.isEmpty) return;
    setState(() => _at = (_at + d) % _hits.length);
    widget.controller._state?._jump(_hits[_at], flash: true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.sm),
      child: Material(
        color: cs.surfaceContainerHigh,
        shape: const StadiumBorder(),
        child: Row(children: [
          const SizedBox(width: Space.lg),
          Icon(Icons.search_rounded, color: cs.onSurfaceVariant),
          const SizedBox(width: Space.sm),
          Expanded(
            child: TextField(
              controller: _q,
              autofocus: true,
              decoration: const InputDecoration(hintText: '在本文中查找', border: InputBorder.none, filled: false, isDense: true),
              onChanged: (v) => setState(() {
                _hits = widget.doc.find(v);
                _at = 0;
                if (_hits.isNotEmpty) widget.controller._state?._jump(_hits.first, flash: true);
              }),
              onSubmitted: (_) => _go(1),
            ),
          ),
          if (_q.text.isNotEmpty)
            Text(_hits.isEmpty ? '无结果' : '${_at + 1}/${_hits.length}', style: TextStyle(color: cs.onSurfaceVariant)),
          IconButton(tooltip: '上一处', onPressed: _hits.isEmpty ? null : () => _go(-1), icon: const Icon(Icons.keyboard_arrow_up_rounded)),
          IconButton(tooltip: '下一处', onPressed: _hits.isEmpty ? null : () => _go(1), icon: const Icon(Icons.keyboard_arrow_down_rounded)),
          IconButton(tooltip: '关闭', onPressed: widget.onClose, icon: const Icon(Icons.close_rounded)),
          const SizedBox(width: Space.xs),
        ]),
      ),
    );
  }
}
