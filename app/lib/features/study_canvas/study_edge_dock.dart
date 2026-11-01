import 'dart:math' as math;

import 'package:flutter/material.dart';

enum StudyDockEdge { top, right, bottom, left }

class StudyDockPlacement {
  const StudyDockPlacement(this.edge, [this.offset = .5]);
  final StudyDockEdge edge;
  final double offset;
  bool get vertical =>
      edge == StudyDockEdge.left || edge == StudyDockEdge.right;
  Alignment get alignment => switch (edge) {
    StudyDockEdge.top => Alignment(offset * 2 - 1, -1),
    StudyDockEdge.bottom => Alignment(offset * 2 - 1, 1),
    StudyDockEdge.left => Alignment(-1, offset * 2 - 1),
    StudyDockEdge.right => Alignment(1, offset * 2 - 1),
  };
  Map<String, dynamic> json() => {'edge': edge.name, 'offset': offset};
  static StudyDockPlacement parse(dynamic data, StudyDockPlacement fallback) {
    if (data is! Map) return fallback;
    final edge = StudyDockEdge.values
        .where((e) => e.name == data['edge'])
        .firstOrNull;
    final offset = data['offset'];
    if (edge == null || offset is! num || !offset.isFinite) return fallback;
    return StudyDockPlacement(edge, offset.toDouble().clamp(0, 1));
  }
}

/// A handle moves only its toolbar. The stage receives blank-area gestures.
/// Interaction reference: Notein APK 1.2.607.0; see docs/drawing-controls.md.
class StudyEdgeDock extends StatefulWidget {
  const StudyEdgeDock({
    super.key,
    required this.id,
    required this.label,
    required this.placement,
    required this.onChanged,
    required this.children,
    this.surfaceKey,
    this.trailing,
    this.thickness = 52,
    this.scale = 1,
    this.maxLength,
    this.centerHandle = false,
    this.startInset = 0,
  });
  final String id, label;
  final StudyDockPlacement placement;
  final ValueChanged<StudyDockPlacement> onChanged;
  final List<Widget> Function(bool vertical) children;
  final GlobalKey? surfaceKey;
  final double thickness, scale;
  final Widget? trailing;
  final double? maxLength;
  final bool centerHandle;
  final double startInset;
  @override
  State<StudyEdgeDock> createState() => _StudyEdgeDockState();
}

class _StudyEdgeDockState extends State<StudyEdgeDock> {
  final _stage = GlobalKey();
  StudyDockPlacement? _drag;

  void _move(Offset global) {
    final box = _stage.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final p = box.globalToLocal(global), s = box.size;
    final distances = <StudyDockEdge, double>{
      StudyDockEdge.top: p.dy.abs(),
      StudyDockEdge.right: (s.width - p.dx).abs(),
      StudyDockEdge.bottom: (s.height - p.dy).abs(),
      StudyDockEdge.left: p.dx.abs(),
    };
    final edge = distances.entries
        .reduce((a, b) => a.value <= b.value ? a : b)
        .key;
    final vertical = edge == StudyDockEdge.left || edge == StudyDockEdge.right;
    final axis = vertical ? s.height : s.width;
    final position = vertical ? p.dy : p.dx;
    setState(
      () => _drag = StudyDockPlacement(
        edge,
        (position / math.max(1, axis)).clamp(0, 1),
      ),
    );
  }

  Widget _handle(bool vertical, {bool centered = false}) => Tooltip(
    message: '拖动${widget.label}，松手贴边',
    child: MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: GestureDetector(
        key: ValueKey('study-dock-handle-${widget.id}'),
        behavior: HitTestBehavior.opaque,
        onPanStart: (e) => _move(e.globalPosition),
        onPanUpdate: (e) => _move(e.globalPosition),
        onPanEnd: (_) {
          final next = _drag;
          setState(() => _drag = null);
          if (next != null) widget.onChanged(next);
        },
        onPanCancel: () => setState(() => _drag = null),
        child: SizedBox(
          width: centered
              ? 64
              : vertical
              ? widget.thickness
              : 18,
          height: centered
              ? 8
              : vertical
              ? (widget.centerHandle ? 10 : 18)
              : widget.thickness,
          child: Center(
            child: centered
                ? Container(
                    width: 30,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xffd9dadd),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  )
                : Icon(
                    vertical ? Icons.drag_handle : Icons.more_vert,
                    size: 15,
                    color: const Color(0xffa0a2a6),
                  ),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final placement = _drag ?? widget.placement;
    // Reparenting the handle before pointer-up disposes its drag recognizer.
    // Apply the new orientation only after the placement has been committed.
    final vertical = widget.placement.vertical;
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, size) {
          final centered = widget.centerHandle && !vertical;
          final extent = math.min(
            widget.maxLength ?? double.infinity,
            vertical
                ? math.max(1.0, size.maxHeight - 128)
                : math.max(1.0, size.maxWidth - widget.startInset - 24),
          );
          final logicalExtent = extent / widget.scale;
          final strip = Flex(
            direction: vertical ? Axis.vertical : Axis.horizontal,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!centered) _handle(vertical),
              Flexible(
                child: SingleChildScrollView(
                  scrollDirection: vertical ? Axis.vertical : Axis.horizontal,
                  child: Flex(
                    direction: vertical ? Axis.vertical : Axis.horizontal,
                    mainAxisSize: MainAxisSize.min,
                    children: widget.children(vertical),
                  ),
                ),
              ),
              if (widget.trailing != null) widget.trailing!,
            ],
          );
          return SizedBox.expand(
            key: _stage,
            child: AnimatedAlign(
              duration: _drag == null
                  ? const Duration(milliseconds: 200)
                  : Duration.zero,
              curve: Curves.easeOut,
              alignment: placement.alignment,
              child: Padding(
                padding: vertical
                    ? const EdgeInsets.symmetric(vertical: 64)
                    : EdgeInsets.only(left: widget.startInset + 12, right: 12),
                child: SizedBox(
                  key: ValueKey('study-dock-${widget.id}'),
                  width: vertical ? widget.thickness * widget.scale : null,
                  height: vertical ? null : widget.thickness * widget.scale,
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: Material(
                      key: widget.surfaceKey,
                      color: Colors.white,
                      elevation: _drag == null ? 2 : 6,
                      shadowColor: Colors.black.withValues(alpha: .18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          widget.centerHandle ? 14 : 26,
                        ),
                        side: const BorderSide(color: Color(0xffeeeeef)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: vertical ? widget.thickness : logicalExtent,
                          maxHeight: vertical
                              ? logicalExtent
                              : widget.thickness,
                        ),
                        child: centered
                            ? Stack(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: strip,
                                  ),
                                  Positioned(
                                    top: 0,
                                    left: 0,
                                    right: 0,
                                    child: Center(
                                      child: _handle(vertical, centered: true),
                                    ),
                                  ),
                                ],
                              )
                            : strip,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
