part of 'study_canvas.dart';

enum StudyDockEdge { top, right, bottom, left }

/// Space between a dock and the window edge it sits on.
const studyDockMargin = Space.sm;

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
    this.dragIcon = Icons.drag_indicator,
    this.showHandle = true,
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
  final IconData dragIcon;
  final bool showHandle;
  @override
  State<StudyEdgeDock> createState() => _StudyEdgeDockState();
}

class _StudyEdgeDockState extends State<StudyEdgeDock>
    with TickerProviderStateMixin {
  _DockGroupState? _group;
  late final _snap = AnimationController(vsync: this, duration: Motion.medium1)
    ..addListener(() => _group?.relayout.value++)
    ..addStatusListener((status) {
      if (status != AnimationStatus.completed || _target == null) return;
      final target = _target!;
      setState(() {
        _center = null;
        _target = null;
      });
      // Settled: a tick, and the dock opens out from the edge.
      unawaited(HapticFeedback.selectionClick());
      _bloom();
      widget.onChanged(target);
    });

  /// Grows the dock in when it changes form: the ball under the finger on
  /// pickup, the full dock from its edge once it has snapped.
  late final _form = AnimationController(
    vsync: this,
    duration: Motion.medium2,
    value: 1,
  );
  void _bloom() => MediaQuery.disableAnimationsOf(context)
      ? _form.value = 1
      : _form.forward(from: 0);
  Offset? _center;
  StudyDockPlacement? _target;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final group = _DockScope.of(context);
    if (_group != group) {
      _group?.docks.remove(widget.id);
      _group = group;
      group.docks[widget.id] = this;
    }
  }

  @override
  void dispose() {
    _group?.docks.remove(widget.id);
    _snap.dispose();
    _form.dispose();
    super.dispose();
  }

  void _start(DragStartDetails e) {
    _snap.reset();
    unawaited(HapticFeedback.lightImpact());
    _moveTo(e.globalPosition);
    _bloom();
  }

  void _moveTo(Offset global) {
    final stage =
        _group?.stage.currentContext?.findRenderObject() as RenderBox?;
    if (stage == null) return;
    final point = stage.globalToLocal(global), size = stage.size;
    final center = Offset(
      point.dx.clamp(26, math.max(26, size.width - 26)),
      point.dy.clamp(26, math.max(26, size.height - 26)),
    );
    final distances = <StudyDockEdge, double>{
      StudyDockEdge.top: center.dy,
      StudyDockEdge.right: size.width - center.dx,
      StudyDockEdge.bottom: size.height - center.dy,
      StudyDockEdge.left: center.dx,
    };
    final edge = distances.entries
        .reduce((a, b) => a.value <= b.value ? a : b)
        .key;
    final vertical = edge == StudyDockEdge.left || edge == StudyDockEdge.right;
    setState(() {
      _center = center;
      _target = StudyDockPlacement(
        edge,
        ((vertical ? center.dy : center.dx) /
                math.max(1, vertical ? size.height : size.width))
            .clamp(0, 1),
      );
    });
    _group!.relayout.value++;
  }

  void _end() {
    if (_center != null) _snap.forward(from: 0);
  }

  void _cancel() {
    final moved = _center != null;
    _snap.stop();
    setState(() {
      _center = null;
      _target = null;
    });
    if (moved) _bloom();
    _group?.relayout.value++;
  }

  Widget _handle(bool vertical, {bool centered = false}) => Tooltip(
    message: '拖动${widget.label}，松手贴边',
    child: MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: SizedBox(
        key: ValueKey('study-dock-handle-${widget.id}'),
        width: centered
            ? 96
            : vertical
            ? widget.thickness
            : 24,
        height: centered
            ? 16
            : vertical
            ? 24
            : widget.thickness,
        child: Center(
          child: centered
              ? Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: StudyChrome.of(context).inkFaint,
                    borderRadius: BorderRadius.circular(3),
                  ),
                )
              : Icon(
                  vertical ? Icons.drag_handle : Icons.more_vert,
                  size: 16,
                  color: StudyChrome.of(context).inkFaint,
                ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final floating = _center != null, vertical = widget.placement.vertical;
    return LayoutId(
      id: widget.id,
      child: LayoutBuilder(
        builder: (context, size) {
          final centered = widget.centerHandle && !vertical;
          final extent = math.min(
            widget.maxLength ?? double.infinity,
            vertical
                ? math.max(
                    1.0,
                    size.maxHeight -
                        math.max(64.0, _group?.widget.topInset ?? 0) -
                        64,
                  )
                : math.max(1.0, size.maxWidth - widget.startInset - 24),
          );
          final strip = Flex(
            direction: vertical ? Axis.vertical : Axis.horizontal,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.showHandle && !centered) _handle(vertical),
              Flexible(
                child: !widget.showHandle
                    ? Flex(
                        direction: vertical ? Axis.vertical : Axis.horizontal,
                        mainAxisSize: MainAxisSize.min,
                        children: widget.children(vertical),
                      )
                    : SingleChildScrollView(
                        scrollDirection: vertical
                            ? Axis.vertical
                            : Axis.horizontal,
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
          // Pickup scales from the finger; the docked form from its edge.
          final grow = floating ? Alignment.center : widget.placement.alignment;
          final form = CurvedAnimation(
            parent: _form,
            curve: Motion.emphasizedDecelerate,
          );
          return Listener(
            onPointerCancel: (_) => _cancel(),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              dragStartBehavior: DragStartBehavior.down,
              onPanStart: _start,
              onPanUpdate: (e) => _moveTo(e.globalPosition),
              onPanEnd: (_) => _end(),
              onPanCancel: _cancel,
              child: FadeTransition(
                opacity: Tween(begin: .4, end: 1.0).animate(form),
                child: ScaleTransition(
                  scale: Tween(
                    begin: floating ? .7 : .86,
                    end: 1.0,
                  ).animate(form),
                  alignment: grow,
                  child: SizedBox(
                    key: ValueKey('study-dock-${widget.id}'),
                    width: floating
                        ? 52
                        : (vertical ? widget.thickness * widget.scale : null),
                    height: floating
                        ? 52
                        : (vertical ? null : widget.thickness * widget.scale),
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: GlassSurface(
                        key: widget.surfaceKey,
                        selected: floating,
                        radius: floating
                            ? 26
                            : (widget.centerHandle
                                  ? Corners.lg
                                  : widget.thickness / 2),
                        child: floating
                            ? SizedBox(
                                width: 52,
                                height: 52,
                                child: Icon(
                                  widget.dragIcon,
                                  key: ValueKey(
                                    'study-dock-floating-${widget.id}',
                                  ),
                                ),
                              )
                            : ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: vertical
                                      ? widget.thickness
                                      : extent / widget.scale,
                                  maxHeight: vertical
                                      ? extent / widget.scale
                                      : widget.thickness,
                                ),
                                child: centered && widget.showHandle
                                    ? Stack(
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 8,
                                            ),
                                            child: strip,
                                          ),
                                          Positioned(
                                            top: 0,
                                            left: 0,
                                            right: 0,
                                            child: Center(
                                              child: _handle(
                                                vertical,
                                                centered: true,
                                              ),
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
            ),
          );
        },
      ),
    );
  }
}

/// All dock sizes are measured together, so collapsing, rotating and resizing
/// cannot make independently positioned controls cover one another.
class _DockGroup extends StatefulWidget {
  const _DockGroup({required this.children, this.topInset = 0});
  final double topInset;
  final List<StudyEdgeDock> children;
  @override
  State<_DockGroup> createState() => _DockGroupState();
}

class _DockGroupState extends State<_DockGroup> {
  final stage = GlobalKey();
  final docks = <String, _StudyEdgeDockState>{};
  final relayout = ValueNotifier(0);
  @override
  void dispose() {
    relayout.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: _DockScope(
      group: this,
      child: CustomMultiChildLayout(
        key: stage,
        delegate: _DockGroupLayout(
          this,
          widget.children.map((c) => c.id).toList(),
        ),
        children: widget.children,
      ),
    ),
  );
}

class _DockScope extends InheritedWidget {
  const _DockScope({required this.group, required super.child});
  final _DockGroupState group;
  static _DockGroupState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_DockScope>()!.group;
  @override
  bool updateShouldNotify(_DockScope old) => old.group != group;
}

class _DockGroupLayout extends MultiChildLayoutDelegate {
  _DockGroupLayout(this.group, this.ids) : super(relayout: group.relayout);
  final _DockGroupState group;
  final List<String> ids;
  @override
  void performLayout(Size size) {
    final occupied = <Rect>[
      if (group.widget.topInset > 0)
        Rect.fromLTWH(0, 0, size.width, group.widget.topInset - 4),
      if (size.width >= 600)
        Rect.fromLTWH(size.width - 196, size.height - 68, 196, 68),
    ];
    for (final id in ids) {
      final state = group.docks[id]!;
      final child = layoutChild(id, BoxConstraints.loose(size));
      final placement = state._target ?? state.widget.placement;
      final docked = studyDockRect(
        size,
        child,
        placement,
        occupied,
        inset: state.widget.startInset,
      );
      Rect rect = docked;
      if (state._center != null) {
        final free = Rect.fromCenter(
          center: state._center!,
          width: child.width,
          height: child.height,
        );
        rect = Rect.lerp(
          free,
          docked,
          Motion.emphasizedDecelerate.transform(state._snap.value),
        )!;
      } else {
        occupied.add(rect);
      }
      positionChild(id, rect.topLeft);
    }
  }

  @override
  bool shouldRelayout(_DockGroupLayout old) => true;
}

/// Prefer the requested position, then slide along the edge; if the edge is
/// full, use another inward lane. Includes corner and zoom-control avoidance.
Rect studyDockRect(
  Size size,
  Size child,
  StudyDockPlacement p,
  List<Rect> occupied, {
  double inset = 0,
}) {
  final freeX = math.max(0.0, size.width - child.width);
  final freeY = math.max(0.0, size.height - child.height);
  final left = math.min(freeX, p.vertical ? studyDockMargin : inset + 12);
  final right = math.max(left, freeX - (p.vertical ? studyDockMargin : 12));
  final top = math.min(freeY, p.vertical ? 64.0 : studyDockMargin);
  final bottom = math.max(top, freeY - (p.vertical ? 64.0 : studyDockMargin));
  final low = p.vertical ? top : left, high = p.vertical ? bottom : right;
  final length = p.vertical ? child.height : child.width;
  final desired = low + (high - low) * p.offset;
  final positions = <double>{desired, low, high};
  for (final r in occupied) {
    positions.add(
      ((p.vertical ? r.top : r.left) - length - 8).clamp(low, high),
    );
    positions.add(((p.vertical ? r.bottom : r.right) + 8).clamp(low, high));
  }
  final sorted = positions.toList()
    ..sort((a, b) => (a - desired).abs().compareTo((b - desired).abs()));
  Rect? fallback;
  for (var lane = 0; lane <= occupied.length; lane++) {
    final shift = lane * ((p.vertical ? child.width : child.height) + 8);
    for (final along in sorted) {
      final offset = switch (p.edge) {
        StudyDockEdge.top => Offset(along, (top + shift).clamp(0, freeY)),
        StudyDockEdge.bottom => Offset(along, (bottom - shift).clamp(0, freeY)),
        StudyDockEdge.left => Offset((left + shift).clamp(0, freeX), along),
        StudyDockEdge.right => Offset((right - shift).clamp(0, freeX), along),
      };
      final rect = offset & child;
      fallback ??= rect;
      if (occupied.every((r) => !r.inflate(4).overlaps(rect))) return rect;
    }
  }
  return fallback!;
}
