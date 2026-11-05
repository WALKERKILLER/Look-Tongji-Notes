part of 'study_canvas.dart';

extension _StudyInteraction on StudyCanvasState {
  void _updateEraserCursor(Offset local) {
    _eraserCursor = local;
    _cursorRadius = _eraserSize;
    _cursor.value++;
  }

  void _eraseAt(Offset a, Offset b) {
    final d = document!;
    if (_eraserMode == 'stroke') {
      d.eraseWhole(a, b, _eraserSize / d.zoom);
    } else {
      d.erase(a, b, _eraserSize / d.zoom);
    }
  }

  void _beginErase(PointerEvent e, Offset p) {
    document!.checkpoint();
    _startErase(e.localPosition, p);
  }

  void _startErase(Offset local, Offset p) {
    _erasing = true;
    _selectionReady = false;
    _regionSelection = null;
    _detail.clear();
    _selection.clear();
    _last = p;
    _eraserLasso.clear();
    if (_eraserMode == 'lasso') {
      _eraserLasso.add(p);
    } else {
      _eraseAt(p, p);
    }
    _updateEraserCursor(local);
  }

  // Erase is a press-and-hold at touchdown. Once the pen has travelled,
  // endpoint holds belong to shape recognition, even with heavy pressure.
  void _watchPressure(PointerEvent e) {
    if (_pressureStart != null &&
        (e.localPosition - _pressureStart!).distance > 6) {
      _pressureStart = null;
    }
    if (_pressureStart == null ||
        !_pressureEraser ||
        _shape != null ||
        e.kind != PointerDeviceKind.stylus ||
        e.pressureMax <= e.pressureMin ||
        _pressure(e) < _pressureThreshold) {
      _pressureTimer?.cancel();
      _pressureTimer = null;
      _pressureOrigin = null;
      return;
    }
    if (_pressureOrigin != null &&
        (e.localPosition - _pressureOrigin!).distance <= 6)
      return;
    _pressureTimer?.cancel();
    _pressureOrigin = e.localPosition;
    _pressureKeep = math.max(0, _points.length - 1);
    final pointer = e.pointer;
    _pressureTimer = Timer(const Duration(milliseconds: 380), () {
      _pressureTimer = null;
      if (!mounted || _drawingPointer != pointer || _pressureOrigin == null)
        return;
      final local = _pointers[pointer];
      if (local == null) return;
      final d = document!;
      _resetShape();
      d.checkpoint();
      // Keep writing before the hold; remove only the stationary trigger tail.
      if (_pressureKeep > 1) {
        d.strokes.addAll(
          StudyDocument.chunks(
            StudyStroke(
              id: studyId(),
              layer: d.activeLayer,
              points: _points.take(_pressureKeep).toList(),
              color: _gestureColor,
              width: _gestureWidth,
              brush: _gestureBrush,
              tool: _tool == StudyTool.highlighter ? 'highlighter' : 'pen',
              anchor: _anchor,
              page:
                  d.cards
                      .where((c) => c.id == _anchor && c.type == 'pdfdoc')
                      .firstOrNull
                      ?.page ??
                  0,
            ),
          ),
        );
        d.changed();
      }
      _points = [];
      _prefix.clear();
      _prefixEnd = 0;
      _drawingPointer = null;
      _temporaryEraser = true;
      _startErase(local, _world(local));
      _scene.value++;
      _live.value++;
      unawaited(HapticFeedback.selectionClick());
    });
  }

  void _finishSelection() {
    final d = document!, r = _marquee!;
    if (r.width * d.zoom < 5 || r.height * d.zoom < 5) return;
    final polygon = _lassoRectangle
        ? [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft]
        : List<Offset>.of(_lasso);
    _detail.clear();
    _detail.strokeIds.addAll(d.strokesInPolygon(polygon));
    _selection.clear();
    // A loop on a document selects ink/visual context. It only moves the entire
    // document if the loop encloses the card, avoiding accidental PDF movement.
    for (final c in d.cards.where(
      (c) => c.type != 'conversation' && d.visible(c.layer),
    )) {
      if (r.contains(c.rect.topLeft) && r.contains(c.rect.bottomRight))
        _selection.add(c.id);
    }
    _regionSelection = r;
    _selectionBounds = _boundsOfSelection() ?? r;
    final anchored = d.cards
        .where(
          (c) =>
              c.type != 'conversation' &&
              d.visible(c.layer) &&
              c.rect.contains(r.center) &&
              c.rect.overlaps(r),
        )
        .lastOrNull;
    if (anchored != null && _selection.isEmpty) {
      _detail.objectId = anchored.id;
      _detail.region = _normalizeRegion(
        r.intersect(_sourceBounds(anchored)),
        _sourceBounds(anchored),
      );
    } else {
      _detail.region = r;
    }
    _quickAsk = false;
    _quickImages = false;
    _selectionReady = true;
    _cursor.value++;
  }

  Rect? _boundsOfSelection() {
    final d = document!;
    final bounds = [
      for (final s in d.strokes)
        if (_detail.strokeIds.contains(s.id)) s.bounds,
      for (final c in d.cards)
        if (_selection.contains(c.id)) c.rect,
    ];
    return bounds.isEmpty
        ? null
        : bounds.reduce((a, b) => a.expandToInclude(b));
  }

  void _transformSelection(Rect from, Rect to, {int? color, double? width}) {
    final d = document!;
    // Anchored ink is transformed by its selected parent exactly once.
    final ink = d.strokes
        .where(
          (s) =>
              _detail.strokeIds.contains(s.id) &&
              !_selection.contains(s.anchor),
        )
        .map((s) => s.id)
        .toSet();
    if (_selection.isNotEmpty && color == null && width == null)
      d.transformCards(_selection, from, to);
    d.transformInk(
      color != null || width != null ? _detail.strokeIds : ink,
      from,
      to,
      color: color,
      width: width,
    );
    _selectionBounds = _boundsOfSelection() ?? to;
    _regionSelection = _selectionBounds;
    _detail.region = _selectionBounds;
    _detail.objectId = '';
    _cursor.value++;
    _update(() {});
  }

  void _copySelection() {
    final d = document!;
    _copiedCards = d.cards
        .where((c) => _selection.contains(c.id) && c.type != 'lecture')
        .map((c) => c.copy())
        .toList();
    final parents = _copiedCards.map((c) => c.id).toSet();
    _copiedInk = d.strokes
        .where(
          (s) => _detail.strokeIds.contains(s.id) || parents.contains(s.anchor),
        )
        .toList();
    _copiedBounds = _selectionBounds;
    _update(() {});
  }

  void _pasteSelection() {
    final d = document!;
    if (_copiedBounds == null || (_copiedInk.isEmpty && _copiedCards.isEmpty))
      return;
    if (d.cards.length + _copiedCards.length > 2000 ||
        d.strokes.length + _copiedInk.length > 29000 ||
        d.strokes.fold<int>(0, (n, s) => n + s.points.length) +
                _copiedInk.fold<int>(0, (n, s) => n + s.points.length) >
            490000) {
      _toast('画布内容已接近容量上限，请先整理后再粘贴');
      return;
    }
    if (!d.editable(d.activeLayer)) {
      _toast(l10n.studyLayerUnavailable);
      return;
    }
    d.checkpoint();
    final oldBounds = _copiedBounds!;
    final delta = _visibleWorld.contains(oldBounds.center)
        ? Offset(28 / d.zoom, 28 / d.zoom)
        : _visibleWorld.center - oldBounds.center;
    final cardIds = {for (final c in _copiedCards) c.id: studyId()};
    final gestureIds = {for (final s in _copiedInk) s.gesture: studyId()};
    _detail.clear();
    _selection.clear();
    for (final c in _copiedCards) {
      final copy = StudyCard.fromJson({
        ...c.json(),
        'id': cardIds[c.id],
        'pdf_column': cardIds[c.pdfColumn] ?? '',
        'layer': d.activeLayer,
      });
      copy.rect = copy.rect.shift(delta);
      d.cards.add(copy);
      _selection.add(copy.id);
    }
    for (final s in _copiedInk) {
      final copy = StudyStroke(
        id: studyId(),
        layer: d.activeLayer,
        gesture: gestureIds[s.gesture],
        anchor: cardIds[s.anchor] ?? s.anchor,
        points: [for (final p in s.points) InkPoint(p.p + delta, p.pressure)],
        color: s.color,
        width: s.width,
        tool: s.tool,
        brush: s.brush,
      );
      d.strokes.add(copy);
      _detail.strokeIds.add(copy.id);
    }
    _tool = StudyTool.region;
    _selectionBounds = _boundsOfSelection();
    _regionSelection = _selectionBounds;
    _detail.region = _selectionBounds;
    _quickAsk = false;
    _selectionReady = true;
    d.changed();
  }

  void _deleteSelection() {
    final d = document!;
    final cards = d.cards
        .where(
          (c) =>
              _selection.contains(c.id) &&
              c.type != 'lecture' &&
              d.canTransformCard(c),
        )
        .map((c) => c.id)
        .toSet();
    final ink = d.strokes
        .where(
          (s) =>
              d.editable(s.layer) &&
              (_detail.strokeIds.contains(s.id) || cards.contains(s.anchor)),
        )
        .map((s) => s.id)
        .toSet();
    if (cards.isEmpty && ink.isEmpty) return;
    d.checkpoint();
    d.cards.removeWhere((c) => cards.contains(c.id));
    d.strokes.removeWhere((s) => ink.contains(s.id));
    d.connections.removeWhere(
      (c) => cards.contains(c.from) || cards.contains(c.to),
    );
    _selection.clear();
    _detail.clear();
    _selectionReady = false;
    _selectionBounds = null;
    _regionSelection = null;
    d.changed();
  }

  Widget _selectionToolbar() {
    if (_tool != StudyTool.region ||
        !_selectionReady ||
        _selectionBounds == null ||
        _selectionDragging)
      return const SizedBox.shrink();
    final hasContent = _selection.isNotEmpty || _detail.strokeIds.isNotEmpty;
    return AnimatedBuilder(
      animation: _camera,
      builder: (_, child) {
        final d = document!, r = _selectionBounds!;
        final width = math.min(600.0, math.max(160.0, _viewport.width - 24));
        final left = (r.center.dx * d.zoom + d.camera.dx - width / 2).clamp(
          12.0,
          math.max(12.0, _viewport.width - width - 12),
        );
        final top = (r.top * d.zoom + d.camera.dy - 58).clamp(
          8.0,
          math.max(8.0, _viewport.height - 64),
        );
        Widget action(String label, IconData icon, VoidCallback? onPressed) =>
            TextButton.icon(
              onPressed: onPressed,
              icon: Icon(icon, size: 17),
              label: Text(label),
            );
        return Positioned(
          left: left.toDouble(),
          top: top.toDouble(),
          width: width,
          child: Material(
            key: _selectionMenuKey,
            elevation: 5,
            borderRadius: BorderRadius.circular(14),
            child: _quickAsk
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.auto_awesome_outlined, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            key: const ValueKey('study-quick-question'),
                            controller: _quickInput,
                            autofocus: true,
                            maxLength: 4000,
                            decoration: const InputDecoration(
                              hintText: '问问选中的内容…',
                              counterText: '',
                              border: InputBorder.none,
                            ),
                            onSubmitted: (_) => _sendQuickQuestion(),
                          ),
                        ),
                        FilterChip(
                          label: const Text('附选区图'),
                          selected: _quickImages,
                          onSelected: _quickSending
                              ? null
                              : (value) => _update(() => _quickImages = value),
                          tooltip: '允许把此选区图片发送给视觉模型',
                        ),
                        IconButton(
                          tooltip: '发送问题',
                          icon: const Icon(Icons.arrow_upward),
                          onPressed: _quickSending ? null : _sendQuickQuestion,
                        ),
                        IconButton(
                          tooltip: '收起提问',
                          icon: const Icon(Icons.close),
                          onPressed: () => _update(() => _quickAsk = false),
                        ),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        action('问 AI', Icons.auto_awesome_outlined, _ask),
                        action(
                          '复制',
                          Icons.copy_outlined,
                          hasContent ? _copySelection : null,
                        ),
                        action(
                          '粘贴',
                          Icons.content_paste,
                          _copiedBounds == null ? null : _pasteSelection,
                        ),
                        action(
                          '副本',
                          Icons.control_point_duplicate,
                          hasContent
                              ? () {
                                  _copySelection();
                                  _pasteSelection();
                                }
                              : null,
                        ),
                        PopupMenuButton<int>(
                          tooltip: '选区改色',
                          enabled: _detail.strokeIds.isNotEmpty,
                          icon: const Icon(Icons.palette_outlined, size: 20),
                          itemBuilder: (_) => [
                            for (final c in _penPalette.take(20))
                              PopupMenuItem(
                                value: c,
                                child: Row(
                                  children: [
                                    Icon(Icons.circle, color: Color(c)),
                                    const SizedBox(width: 12),
                                    Text(
                                      '#${(c & 0xffffff).toRadixString(16).padLeft(6, '0')}',
                                    ),
                                  ],
                                ),
                              ),
                          ],
                          onSelected: (c) {
                            d.checkpoint();
                            _transformSelection(r, r, color: c);
                          },
                        ),
                        PopupMenuButton<double>(
                          tooltip: '选区粗细',
                          enabled: _detail.strokeIds.isNotEmpty,
                          icon: const Icon(Icons.line_weight, size: 20),
                          itemBuilder: (_) => [
                            for (final w in [1.0, 2.0, 3.0, 5.0, 8.0, 12.0])
                              PopupMenuItem(
                                value: w,
                                child: Text('${w.toInt()}'),
                              ),
                          ],
                          onSelected: (w) {
                            d.checkpoint();
                            _transformSelection(r, r, width: w);
                          },
                        ),
                        action(
                          '删除',
                          Icons.delete_outline,
                          hasContent ? _deleteSelection : null,
                        ),
                        IconButton(
                          tooltip: '取消选择',
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => _update(() {
                            _selectionReady = false;
                            _selectionBounds = null;
                            _regionSelection = null;
                            _selection.clear();
                            _detail.clear();
                            _cursor.value++;
                          }),
                        ),
                      ],
                    ),
                  ),
          ),
        );
      },
    );
  }
}

class _InteractionFeedback extends CustomPainter {
  _InteractionFeedback(this.state, Listenable repaint)
    : super(repaint: repaint);
  final StudyCanvasState state;
  @override
  void paint(Canvas canvas, Size size) {
    final s = state, d = s.document!;
    Offset screen(Offset p) => p * d.zoom + d.camera;
    final accent = state.chrome.accent;
    final line = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    void dash(Path path) {
      for (final metric in path.computeMetrics()) {
        for (var start = 0.0; start < metric.length; start += 10) {
          canvas.drawPath(
            metric.extractPath(start, math.min(start + 6, metric.length)),
            line,
          );
        }
      }
    }

    final loop = s._erasing ? s._eraserLasso : s._lasso;
    if (loop.length > 1 && !(s._lassoRectangle && !s._erasing)) {
      final path = Path()..addPolygon(loop.map(screen).toList(), true);
      canvas.drawPath(path, Paint()..color = state.chrome.accentWash);
      dash(path);
    } else {
      final r =
          s._marquee ??
          (s._selectionReady ? s._selectionBounds : null) ??
          s._sourceHighlight;
      if (r != null) {
        final box = Rect.fromPoints(screen(r.topLeft), screen(r.bottomRight));
        dash(Path()..addRect(box));
        if (s._selectionReady) {
          canvas.drawCircle(
            box.bottomRight,
            7,
            Paint()..color = state.chrome.paper,
          );
          canvas.drawCircle(box.bottomRight, 7, line);
        }
      }
    }
    final cursor = s._eraserCursor;
    if (cursor != null &&
        (s._tool == StudyTool.eraser || s._temporaryEraser) &&
        s._eraserMode != 'lasso') {
      canvas.drawCircle(
        cursor,
        s._cursorRadius,
        Paint()..color = state.chrome.paper.withValues(alpha: .24),
      );
      canvas.drawCircle(
        cursor,
        s._cursorRadius,
        Paint()
          ..color = state.chrome.paper
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
      canvas.drawCircle(
        cursor,
        s._cursorRadius,
        Paint()
          ..color = state.chrome.inkSoft
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3,
      );
      if (s._temporaryEraser)
        canvas.drawCircle(cursor, 2, Paint()..color = accent);
    }
  }

  @override
  bool shouldRepaint(_InteractionFeedback old) => old.state != state;
}

/// A ring that fills under a finger resting on a card, so the hold that
/// lifts the card reads as deliberate rather than as a stall. It stays
/// hidden through the first moments, when most contacts become pans.
class _HoldCue extends StatelessWidget {
  const _HoldCue({required this.at});
  final ValueListenable<Offset?> at;

  static const double _size = 44;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Offset?>(
    valueListenable: at,
    builder: (context, p, _) => p == null
        ? const SizedBox.shrink()
        : Positioned(
            left: p.dx - _size / 2,
            top: p.dy - _size / 2,
            width: _size,
            height: _size,
            child: IgnorePointer(
              // A new hold starts a new fill.
              child: _HoldRing(key: ValueKey(p)),
            ),
          ),
  );
}

class _HoldRing extends StatefulWidget {
  const _HoldRing({super.key});
  @override
  State<_HoldRing> createState() => _HoldRingState();
}

class _HoldRingState extends State<_HoldRing>
    with SingleTickerProviderStateMixin {
  // Silent for the first quarter of the hold.
  static const _quiet = .25;
  late final _fill = AnimationController(
    vsync: this,
    duration: canvasCardHoldDelay,
  )..forward();

  @override
  void dispose() {
    _fill.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return const SizedBox();
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _fill,
      builder: (context, _) {
        final t = ((_fill.value - _quiet) / (1 - _quiet)).clamp(0.0, 1.0);
        return Opacity(
          opacity: Motion.emphasizedDecelerate.transform(
            (t * 4).clamp(0.0, 1.0),
          ),
          child: CustomPaint(
            painter: _RingPainter(
              Motion.emphasized.transform(t),
              cs.primary,
              cs.surface,
            ),
          ),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.t, this.ink, this.halo);
  final double t;
  final Color ink, halo;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2 - 3;
    final c = size.center(Offset.zero);
    // A soft disc keeps the ring legible over any material.
    canvas.drawCircle(c, r + 2, Paint()..color = halo.withValues(alpha: .55));
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = ink.withValues(alpha: .18),
    );
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2,
      2 * math.pi * t,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = ink,
    );
  }

  @override
  bool shouldRepaint(_RingPainter o) =>
      o.t != t || o.ink != ink || o.halo != halo;
}
