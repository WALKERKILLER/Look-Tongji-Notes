part of 'study_canvas.dart';

extension _StudyShapeInteraction on StudyCanvasState {
  void _cancelShapeHold() {
    _shapeTimer?.cancel();
    _shapeTimer = null;
    _shapeHoldOrigin = null;
  }

  void _resetShape() {
    _cancelShapeHold();
    _shape = null;
    _shapeHandle = null;
    _shapePreview = null;
  }

  void _watchShape(PointerEvent event) {
    if (!_presets[_presetIndex].shapeAssist ||
        _pressureTimer != null ||
        _shape != null ||
        !_ink) {
      _cancelShapeHold();
      return;
    }
    if (_shapeHoldOrigin != null &&
        (event.localPosition - _shapeHoldOrigin!).distance <= 6)
      return;
    _cancelShapeHold();
    _shapeHoldOrigin = event.localPosition;
    final pointer = event.pointer;
    _shapeTimer = Timer(const Duration(milliseconds: 700), () {
      _shapeTimer = null;
      if (!mounted ||
          _drawingPointer != pointer ||
          _pressureTimer != null ||
          ModalRoute.of(context)?.isCurrent == false ||
          _points.length < 3)
        return;
      final shape = recognizeStudyShape([
        for (final p in _points) p.p,
      ], zoom: document!.zoom);
      final local = _pointers[pointer];
      if (shape == null || local == null) return;
      _clearPrediction();
      _shape = shape;
      _shapeHandle = _world(local);
      final pressure =
          _points.fold<double>(0, (a, b) => a + b.pressure) / _points.length;
      _shapePreview = [for (final p in shape.points) InkPoint(p, pressure)];
      _prefix.clear();
      _prefixEnd = 0;
      _scene.value++;
      _live.value++;
    });
  }

  void _adjustShape(Offset point) {
    // Ignore sensor jitter before the user deliberately adjusts the fitted shape.
    final points = (point - _shapeHandle!).distance * document!.zoom <= 6
        ? _shape!.points
        : _shape!.adjust(_shapeHandle!, point);
    final pressure = _shapePreview!.first.pressure;
    _shapePreview = [for (final p in points) InkPoint(p, pressure)];
    _live.value++;
  }

  void _commitShape() {
    if (_shapePreview == null) return;
    final d = document!, original = document!.strokes.last;
    // The first checkpoint restores the actual freehand input; a second undo
    // removes that physical stroke. No shape-only fields enter the sync format.
    d.checkpoint();
    d.strokes.removeWhere((s) => s.gesture == original.gesture);
    d.strokes.addAll(
      StudyDocument.chunks(
        StudyStroke(
          id: original.gesture,
          gesture: original.gesture,
          layer: original.layer,
          points: _shapePreview!,
          color: original.color,
          width: original.width,
          brush: original.brush,
          tool: original.tool,
          anchor: original.anchor,
          page: original.page,
        ),
      ),
    );
    d.changed();
  }
}
