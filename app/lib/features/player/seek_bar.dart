import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../theme/tokens.dart';
import '../schedule/schedule_store.dart';
import '../schedule/schedule_widgets.dart';
import 'lecture_player.dart';

/// Progress bar split into outline chapters, with buffered range, slide
/// ticks, bookmark and schedule marks, and a hover preview of the slide and
/// chapter at that moment.
class SeekBar extends StatefulWidget {
  const SeekBar({super.key, required this.ctl, this.onInteract});
  final LecturePlayer ctl;
  final VoidCallback? onInteract;
  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  double? _hoverX;
  double? _dragFrac;
  double _width = 1;

  int get _durMs => widget.ctl.duration.inMilliseconds;

  double _frac(double x) => (x / _width).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final ctl = widget.ctl;
    final cs = Theme.of(context).colorScheme;
    final active = _hoverX != null || _dragFrac != null;
    final marks = context.watch<ScheduleStore>().forLecture(ctl.lectureId).where((it) => it.tMs >= 0).toList();
    return LayoutBuilder(builder: (context, c) {
      _width = c.maxWidth;
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        onHover: (e) => setState(() => _hoverX = e.localPosition.dx),
        onExit: (_) => setState(() => _hoverX = null),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (d) {
            widget.onInteract?.call();
            setState(() => _dragFrac = _frac(d.localPosition.dx));
          },
          onHorizontalDragUpdate: (d) {
            widget.onInteract?.call();
            setState(() => _dragFrac = _frac(d.localPosition.dx));
          },
          onHorizontalDragEnd: (_) {
            if (_dragFrac != null && _durMs > 0) ctl.seekTo((_dragFrac! * _durMs).round());
            setState(() => _dragFrac = null);
          },
          onTapUp: (d) {
            widget.onInteract?.call();
            if (_durMs > 0) ctl.seekTo((_frac(d.localPosition.dx) * _durMs).round());
          },
          child: SizedBox(
            height: 28,
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned.fill(
                child: ValueListenableBuilder(
                  valueListenable: ctl.position,
                  builder: (context, pos, _) => ValueListenableBuilder(
                    valueListenable: ctl.buffer,
                    builder: (context, buf, _) => AnimatedBuilder(
                      animation: ctl,
                      builder: (context, _) => CustomPaint(
                        painter: _BarPainter(
                          played: _dragFrac ?? (_durMs > 0 ? pos.inMilliseconds / _durMs : 0),
                          buffered: _durMs > 0 ? buf.inMilliseconds / _durMs : 0,
                          slides: _durMs > 0 ? [for (final s in ctl.slides) if (s.isKey) s.tSec * 1000 / _durMs] : const [],
                          bookmarks: _durMs > 0 ? [for (final b in ctl.bookmarks) b.tMs / _durMs] : const [],
                          chapters: _durMs > 0 ? [for (final c in ctl.chapters.skip(1)) c.startMs / _durMs] : const [],
                          marks: _durMs > 0 ? [for (final it in marks) (it.tMs / _durMs, KindStyle.of(context, it.kind).accent)] : const [],
                          hover: _hoverX == null ? null : _frac(_hoverX!),
                          thick: active,
                          cs: cs,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if ((_dragFrac != null || _hoverX != null) && _durMs > 0) _preview(context),
            ]),
          ),
        ),
      );
    });
  }

  Widget _preview(BuildContext context) {
    final ctl = widget.ctl;
    final f = _dragFrac ?? _frac(_hoverX!);
    final ms = (f * _durMs).round();
    final si = ctl.slideAt(ms);
    final slide = si >= 0 ? ctl.slides[si] : null;
    final ci = ctl.chapterAt(ms);
    final chapter = ci >= 0 ? ctl.chapters[ci].title : null;
    const w = 176.0;
    final left = (f * _width - w / 2).clamp(0.0, (_width - w).clamp(0.0, double.infinity));
    final tt = Theme.of(context).textTheme;
    return Positioned(
      left: left,
      bottom: 30,
      width: w,
      child: IgnorePointer(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (slide != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(Corners.md),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(ctl.slideUrl(slide), fit: BoxFit.cover, gaplessPlayback: true,
                    headers: ctl.media?.headers, errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black54)),
              ),
            ),
          const SizedBox(height: Space.xs),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.78), borderRadius: BorderRadius.circular(chapter == null ? Corners.full : Corners.md)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (chapter != null)
                Text(chapter, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: tt.labelMedium?.copyWith(color: Colors.white, height: 1.3)),
              Text(fmtClock(ms),
                  style: (chapter == null ? tt.labelMedium : tt.labelSmall)
                      ?.copyWith(color: chapter == null ? Colors.white : Colors.white70, fontFeatures: const [FontFeature.tabularFigures()])),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.played,
    required this.buffered,
    required this.slides,
    required this.bookmarks,
    required this.chapters,
    required this.marks,
    required this.hover,
    required this.thick,
    required this.cs,
  });
  final double played, buffered;
  final List<double> slides, bookmarks;

  /// Chapter boundaries (fractions), first chapter excluded.
  final List<double> chapters;
  final List<(double, Color)> marks;
  final double? hover;
  final bool thick;
  final ColorScheme cs;

  static const _gap = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final h = thick ? 6.0 : 4.0;
    final y = size.height / 2;
    final w = size.width;
    final edges = [0.0, ...chapters.where((c) => c > 0 && c < 1), 1.0];
    final px = w * played.clamp(0, 1);
    final base = Paint()..color = Colors.white.withValues(alpha: 0.22);
    final buf = Paint()..color = Colors.white.withValues(alpha: 0.38);
    final hov = Paint()..color = Colors.white.withValues(alpha: 0.18);
    final fill = Paint()..color = cs.primary;
    for (var i = 0; i < edges.length - 1; i++) {
      final x0 = w * edges[i] + (i > 0 ? _gap / 2 : 0);
      final x1 = w * edges[i + 1] - (i < edges.length - 2 ? _gap / 2 : 0);
      if (x1 <= x0) continue;
      // The chapter under the pointer grows, so its extent reads at a glance.
      final under = hover != null && edges.length > 2 && hover! >= edges[i] && hover! < edges[i + 1];
      final sh = under ? h + 3 : h;
      final seg = RRect.fromLTRBR(x0, y - sh / 2, x1, y + sh / 2, Radius.circular(sh / 2));
      canvas.save();
      canvas.clipRRect(seg);
      canvas.drawRect(seg.outerRect, base);
      canvas.drawRect(Rect.fromLTRB(x0, y - sh / 2, w * buffered.clamp(0, 1), y + sh / 2), buf);
      if (hover != null) canvas.drawRect(Rect.fromLTRB(x0, y - sh / 2, w * hover!, y + sh / 2), hov);
      canvas.drawRect(Rect.fromLTRB(x0, y - sh / 2, px, y + sh / 2), fill);
      canvas.restore();
    }
    final tick = Paint()..color = Colors.black.withValues(alpha: 0.45);
    for (final s in slides) {
      canvas.drawRect(Rect.fromLTWH(w * s - 0.75, y - h / 2, 1.5, h), tick);
    }
    final bm = Paint()..color = cs.tertiary;
    for (final b in bookmarks) {
      canvas.drawCircle(Offset(w * b, y - h / 2 - 5), 3, bm);
    }
    // Schedule mentions: small rounded squares in the kind's color.
    for (final (f, c) in marks) {
      final r = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(w * f, y - h / 2 - 6), width: 7, height: 7), const Radius.circular(2));
      canvas.drawRRect(r, Paint()..color = Colors.black.withValues(alpha: 0.5));
      canvas.drawRRect(r.deflate(1), Paint()..color = c);
    }
    // Thumb: an M3 Expressive vertical handle.
    final tw = thick ? 6.0 : 4.0, th = thick ? 22.0 : 16.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(px, y), width: tw, height: th), Radius.circular(tw / 2)),
      fill,
    );
  }

  @override
  bool shouldRepaint(_BarPainter o) =>
      o.played != played ||
      o.buffered != buffered ||
      o.hover != hover ||
      o.thick != thick ||
      o.slides.length != slides.length ||
      o.bookmarks.length != bookmarks.length ||
      o.chapters.length != chapters.length ||
      o.marks.length != marks.length ||
      o.cs != cs;
}
