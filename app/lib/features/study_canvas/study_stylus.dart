part of 'study_canvas.dart';

extension _StudyStylus on StudyCanvasState {
  bool get _touchBlocked =>
      _stylusPointers.isNotEmpty || (_palmCooldown?.isActive ?? false);

  void _trackStylusPresence(PointerEvent e) {
    if (e.kind != PointerDeviceKind.stylus &&
        e.kind != PointerDeviceKind.invertedStylus)
      return;
    if (e is PointerDownEvent) _stylusPointers.add(e.pointer);
    if (e is PointerUpEvent || e is PointerCancelEvent) {
      _stylusPointers.remove(e.pointer);
    }
    // Active contact is authoritative even when the pen stops reporting moves.
    // Lift/cancel restarts the grace period for a palm still resting nearby.
    _palmCooldown?.cancel();
    _palmCooldown = Timer(const Duration(seconds: 1), () {});
    if (_touchPointers.isEmpty) return;
    // A palm that touched first cannot resume navigation when the pen lifts.
    // Only a fresh down after the grace period may start another gesture.
    for (final pointer in _touchPointers) {
      _pointers.remove(pointer);
    }
    _touchPointers.clear();
    _cancelCardHold();
    _panCamera = null;
    _pinchDistance = _pinchZoom = null;
    _pinchWorld = null;
    _dragCard = null;
    _heldCardNeedsCheckpoint = false;
    _resize = false;
    _start = _last = null;
    if (_pointers.isEmpty) _gesturing.value = false;
  }

  Future<void> _startStylus() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    // Probe first: EventChannel reports a missing native plugin globally.
    try {
      await const MethodChannel('look/stylus').invokeMethod('status');
    } on MissingPluginException catch (_) {
      return;
    } on PlatformException catch (_) {
      return;
    }
    if (!mounted) return;
    _stylusEvents = const EventChannel('look/stylus/events')
        .receiveBroadcastStream()
        .listen(_stylusEvent, onError: (_) {});
    unawaited(_configureStylus());
  }

  Future<void> _configureStylus() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await const MethodChannel('look/stylus').invokeMethod('configure', {
        'prediction': _predictionEnabled,
        'buttons': _penButtons,
      });
    } on MissingPluginException catch (_) {
      // Older desktop/test shells still support ordinary pressure input.
    } on PlatformException catch (_) {}
  }

  void _clearPrediction() {
    _predictionExpiry?.cancel();
    _predictionExpiry = null;
    if (_predicted.isEmpty) return;
    _predicted = [];
    _live.value++;
  }

  void _stylusEvent(dynamic value) {
    if (!mounted || value is! Map) return;
    if (value['type'] == 'clear') {
      _clearPrediction();
      return;
    }
    if (ModalRoute.of(context)?.isCurrent == false ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.paused)
      return;
    if (value['type'] == 'toggleEraser') {
      // A button pressed while drawing must not change a stroke's tool halfway.
      if (!_penButtons || _pointers.isNotEmpty || document == null) return;
      if (_tool == StudyTool.eraser) {
        _pickPen(_presetIndex);
      } else {
        _chooseTool(StudyTool.eraser);
      }
      unawaited(HapticFeedback.selectionClick());
      return;
    }
    if (value['type'] != 'prediction' ||
        !_predictionEnabled ||
        _drawingPointer == null ||
        _shape != null ||
        _points.isEmpty ||
        _lastRealStylusTime != value['time'] ||
        !_ink)
      return;
    final box = _inputSurface.currentContext?.findRenderObject() as RenderBox?;
    final x = value['x'], y = value['y'], samples = value['points'];
    if (box == null || x is! num || y is! num || samples is! List) return;
    final actual = Offset(x.toDouble(), y.toDouble());
    if ((actual - _lastRealStylusPosition).distance > 3) return;
    final preview = <InkPoint>[];
    for (final sample in samples.take(8)) {
      if (sample is! List ||
          sample.length != 3 ||
          sample.any((v) => v is! num || !v.isFinite))
        continue;
      final p = Offset(
        (sample[0] as num).toDouble(),
        (sample[1] as num).toDouble(),
      );
      if ((p - actual).distance > 48) continue;
      preview.add(
        InkPoint(
          _world(box.globalToLocal(p)),
          (sample[2] as num).toDouble().clamp(.05, 1),
        ),
      );
    }
    _clearPrediction();
    _predicted = preview;
    if (preview.isNotEmpty) _acceptedPredictions++;
    _live.value++;
    // A stopped pen cannot leave a predicted hook on screen indefinitely.
    _predictionExpiry = Timer(const Duration(milliseconds: 48), () {
      if (mounted) _clearPrediction();
    });
  }

  void _realStylus(PointerEvent e) {
    _clearPrediction();
    _lastRealStylusTime = e.kind == PointerDeviceKind.stylus
        ? e.timeStamp.inMilliseconds
        : null;
    _lastRealStylusPosition = e.position;
  }

  Future<void> _stylusSettings() async {
    Map status = {};
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        status =
            await const MethodChannel('look/stylus')
                .invokeMapMethod('status') ??
            {};
      } on MissingPluginException catch (_) {
      } on PlatformException catch (_) {}
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, change) => AlertDialog(
          title: const Text('手写笔'),
          content: SizedBox(
            width: 330,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (defaultTargetPlatform == TargetPlatform.android) ...[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('笔迹预测'),
                    subtitle: const Text('只改善笔尖预览，保存真实笔迹'),
                    value: _predictionEnabled,
                    onChanged: (v) {
                      change(() => _predictionEnabled = v);
                      _clearPrediction();
                      unawaited(_configureStylus());
                      unawaited(_saveBrushSettings());
                    },
                  ),
                  Text(
                    '预测引擎：${switch (status['backend']) {
                      'huawei' => '华为 Pencil Engine（无结果时回退 AndroidX）',
                      'androidx' => 'AndroidX',
                      _ => '未启用',
                    }}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  Text(
                    '本页接收 $_acceptedPredictions 帧；引擎输出 ${status['previewFrames'] ?? 0} 帧（华为 ${status['vendorFrames'] ?? 0} / AndroidX ${status['fallbackFrames'] ?? 0}）；按钮 ${status['buttonEvents'] ?? 0} 次',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('笔按钮切换橡皮'),
                  subtitle: const Text('悬空按键切换；按住侧键落笔临时擦除。需要设备上报标准笔按钮事件。'),
                  value: _penButtons,
                  onChanged: (v) {
                    change(() => _penButtons = v);
                    unawaited(_configureStylus());
                    unawaited(_saveBrushSettings());
                  },
                ),
                const Text(
                  'M-Pencil 双击和轻捏尚未验证；本设置不代表设备支持这些手势。',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('完成'),
            ),
          ],
        ),
      ),
    );
  }
}
