import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/api.dart';
import '../../widgets/look_markdown.dart';
import '../../l10n/l10n.dart';
import '../player/lecture_player.dart';
import 'study_document.dart';
import 'study_pdf_column.dart';
import 'study_edge_dock.dart';
import 'study_shape.dart';

import 'package:val_latex_flutter/val_latex_flutter.dart';

part 'study_agent_ui.dart';
part 'study_brush_ui.dart';
part 'study_interaction.dart';
part 'study_conversation_ui.dart';
part 'study_pdf_ui.dart';
part 'study_toolbar_ui.dart';
part 'study_pen_palette.dart';
part 'study_shape_interaction.dart';
part 'study_stylus.dart';

enum StudyTool { select, hand, pen, highlighter, eraser, region }

class StudyCanvas extends StatefulWidget {
  const StudyCanvas({
    super.key,
    required this.api,
    required this.ctl,
    required this.video,
    required this.panel,
    required this.onClassic,
    required this.onAsk,
    required this.onBack,
    this.fullscreen = false,
  });
  final Api api;
  final LecturePlayer ctl;
  final Widget video, panel;
  final VoidCallback onClassic, onBack;
  final ValueChanged<String> onAsk;
  final bool fullscreen;
  @override
  State<StudyCanvas> createState() => StudyCanvasState();
}

class StudyCanvasState extends State<StudyCanvas> with WidgetsBindingObserver {
  StudyDocument? document;
  Object? _loadError, _saveError;
  StudyTool _tool = StudyTool.select;
  int _color = 0xff25344a;
  double _penWidth = 3;
  StudyBrush _brush = const StudyBrush(), _gestureBrush = const StudyBrush();
  double _gestureWidth = 3, _eraserSize = 18;
  int _gestureColor = 0xff25344a, _presetIndex = 0;
  List<StudyPenPreset> _presets = StudyPenPreset.defaults();
  String _eraserMode = 'partial', _paperStyle = 'ruled';
  int _paperColor = 0xffffffff;
  StudyDockPlacement _penPlacement = const StudyDockPlacement(
    StudyDockEdge.bottom,
  );
  StudyDockPlacement _toolPlacement = const StudyDockPlacement(
    StudyDockEdge.top,
  );
  StudyDockPlacement _modulePlacement = const StudyDockPlacement(
    StudyDockEdge.top,
    0,
  );
  bool _dockSmall = false;
  final _penItemKeys = <int, GlobalKey>{};
  final _eraserKey = GlobalKey();
  final _eraserLasso = <Offset>[], _lasso = <Offset>[];
  final _camera = ValueNotifier(0), _cursor = ValueNotifier(0);
  final _selectionMenuKey = GlobalKey();
  Rect? _stageRect, _selectionBounds;
  Offset? _eraserCursor, _pressureOrigin, _pressureStart;
  double _cursorRadius = 18, _pressureThreshold = .8;
  bool _pressureEraser = true, _temporaryEraser = false;
  bool _selectionReady = false,
      _selectionDragging = false,
      _selectionResize = false;
  bool _lassoRectangle = false;
  Timer? _pressureTimer;
  Timer? _shapeTimer;
  final _inputSurface = GlobalKey();
  StreamSubscription? _stylusEvents;
  Timer? _predictionExpiry;
  bool _predictionEnabled = true, _penButtons = true;
  List<InkPoint> _predicted = [];
  int _acceptedPredictions = 0;
  int? _lastRealStylusTime;
  Offset _lastRealStylusPosition = Offset.zero;
  Offset? _shapeHoldOrigin, _shapeHandle;
  StudyShape? _shape;
  List<InkPoint>? _shapePreview;
  int _pressureKeep = 0;
  List<StudyStroke> _copiedInk = [];
  List<StudyCard> _copiedCards = [];
  Rect? _copiedBounds;

  final _moduleKey = GlobalKey(), _toolbarKey = GlobalKey();
  final _conversationKeys = <String, GlobalKey<_ConversationBodyState>>{};
  final _initialConversations = <String, Map>{};
  String? _activeConversation;
  bool _moduleSmall = false, _toolbarSmall = false;
  String _status = l10n.studyOpening;
  bool _importing = false, _disposed = false;
  Timer? _saveTimer;
  Timer? _syncCheck;
  StreamSubscription? _syncSubscription;
  bool _remotePending = false, _refreshing = false;
  Map? _remoteDocument;
  Future<bool>? _saving;
  int _savedEdit = 0;
  final _scene = ValueNotifier(0), _live = ValueNotifier(0);
  final _selection = <String>{};
  final _detail = StudySelection();
  final _capture = GlobalKey();
  final _dockKey = GlobalKey(), _zoomKey = GlobalKey();
  final _localVideoKeys = <String, GlobalKey<_LocalVideoState>>{};
  final _localVideoTimes = <String, int>{};
  Rect? _regionSelection, _sourceHighlight;
  void _update(VoidCallback action) => setState(action);
  final _pointers = <int, Offset>{};
  List<InkPoint> _points = [];
  final List<StudyStroke> _prefix = [];
  int _prefixEnd = 0;
  String _anchor = '';
  Offset? _start, _last;
  Offset? _panCamera;
  Rect? _marquee;
  String? _dragCard;
  bool _resize = false, _erasing = false;
  double? _pinchDistance, _pinchZoom;
  Offset? _pinchWorld;
  int? _drawingPointer;
  int _pointBudget = 20000;
  DateTime? _lastStylus;
  Size _viewport = const Size(1000, 700);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _syncCheck = Timer.periodic(const Duration(seconds: 5), (_) {
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (lifecycle == AppLifecycleState.paused ||
          lifecycle == AppLifecycleState.hidden ||
          lifecycle == AppLifecycleState.detached ||
          !mounted ||
          ModalRoute.of(context)?.isCurrent == false)
        return;
      unawaited(_refreshFromSync());
    });
    _syncSubscription = widget.api.sse('/api/events').listen((e) {
      if (e['type'] == 'sync_done' &&
          ((e['data'] as Map?)?['downloaded'] as num? ?? 0) > 0) {
        unawaited(_refreshFromSync());
      }
    }, onError: (_) {});
    unawaited(_titlebar(true));
    unawaited(_startStylus());
    _loadBrushSettings();
    _loadLayout();
  }

  Future<void> _titlebar(bool canvas) async {
    if (!Platform.isMacOS) return;
    try {
      await windowManager.setTitleBarStyle(
        canvas ? TitleBarStyle.hidden : TitleBarStyle.normal,
      );
      if (canvas && !mounted)
        await windowManager.setTitleBarStyle(TitleBarStyle.normal);
    } on PlatformException catch (_) {
      // Window chrome is optional; canvas navigation remains in the toolbar.
    } on MissingPluginException catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refreshFromSync());
    if (state != AppLifecycleState.resumed) {
      _cancelShapeHold();
      _clearPrediction();
    } else {
      unawaited(_configureStylus());
    }
  }

  bool get _editingCanvas =>
      _importing ||
      (document != null && document!.edit != _savedEdit) ||
      _saving != null ||
      _drawingPointer != null ||
      _erasing ||
      _dragCard != null;

  Future<void> _load({Map? synced}) async {
    try {
      final data = synced ?? await widget.api.studyCanvas(widget.ctl.lectureId);
      if (!mounted) return;
      final prefs = await SharedPreferences.getInstance();
      final draft = prefs.getString('study-draft-${widget.ctl.lectureId}');
      if (!mounted) return;
      if (synced != null && _editingCanvas) return;
      final d = StudyDocument.fromJson(data as Map);
      if (draft != null) {
        document?.dispose();
        d.dispose();
        _remoteDocument = data;
        _remotePending = true;
        document = StudyDocument.fromJson(jsonDecode(draft) as Map);
        document!.edit = 1;
        _savedEdit = 0;
        document!.addListener(_changed);
        if (mounted) setState(() => _status = '已恢复本机草稿，请选择保留版本');
        return;
      }
      document?.dispose();
      document = d;
      d.addListener(_changed);
      _savedEdit = d.edit;
      setState(() {
        _loadError = null;
        _status = l10n.studySaved;
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  Future<void> _refreshFromSync() async {
    if (_refreshing || !mounted) return;
    _refreshing = true;
    try {
      final remote = await widget.api.studyCanvas(widget.ctl.lectureId) as Map;
      final d = document;
      if (d == null || !mounted) return;
      if (remote['base_hash'] == d.baseHash) return;
      // Finish an edit already in progress. Its save rebases against the latest
      // revision, so the last saved whole canvas wins (ADR 0022).
      if (_editingCanvas) return;
      await _load(synced: remote);
    } catch (_) {
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _resolveRemote(bool keepLocal) async {
    final remote = _remoteDocument;
    if (remote == null) return;
    if (keepLocal) {
      document!.revision = (remote['revision'] as num).toInt();
      document!.baseHash = remote['base_hash'] as String? ?? '';
      _remotePending = false;
      if (!await flush()) {
        _remotePending = true;
        return;
      }
    } else {
      _remotePending = false;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('study-draft-${widget.ctl.lectureId}');
      await _load();
    }
    if (!_remotePending) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('study-draft-${widget.ctl.lectureId}');
      if (mounted) setState(() {});
    }
  }

  void _changed() {
    if (_disposed) return;
    if (_selectionReady) {
      final strokes = document!.strokes.map((s) => s.id).toSet();
      final cards = document!.cards.map((c) => c.id).toSet();
      _detail.strokeIds.removeWhere((id) => !strokes.contains(id));
      _selection.removeWhere((id) => !cards.contains(id));
      _selectionBounds = _boundsOfSelection();
      if (_selectionBounds == null && _detail.objectId == null)
        _selectionReady = false;
    }
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 1000), _saveWhenIdle);
    _scene.value++;
    setState(() => _status = l10n.studyPendingSave);
  }

  void _saveWhenIdle() {
    if (_drawingPointer != null || _erasing || _dragCard != null) {
      _saveTimer = Timer(const Duration(seconds: 1), _saveWhenIdle);
    } else {
      unawaited(flush());
    }
  }

  Future<bool> flush() async {
    _saveTimer?.cancel();
    final current = _saving;
    if (current != null) {
      if (!await current) return false;
    }
    final d = document;
    if (_remotePending) return false;
    if (d == null || d.edit == _savedEdit) return true;
    final future = _saveLoop(d);
    _saving = future;
    try {
      return await future;
    } finally {
      if (identical(_saving, future)) _saving = null;
    }
  }

  Future<bool> _saveLoop(StudyDocument d) async {
    try {
      var retries = 0;
      while (d.edit != _savedEdit) {
        final edit = d.edit;
        if (mounted) setState(() => _status = l10n.studySaving);
        Map out;
        try {
          out = await widget.api.saveStudyCanvas(
            widget.ctl.lectureId,
            d.json(),
          ) as Map;
        } on ApiError catch (e) {
          if (e.status != 409 || retries++ >= 2) rethrow;
          final remote =
              await widget.api.studyCanvas(widget.ctl.lectureId) as Map;
          // Retain the superseded saved document before replacing it.
          await widget.api.post(
            '/api/lectures/${widget.ctl.lectureId}/study-canvas/draft',
            remote,
          );
          d.revision = (remote['revision'] as num).toInt();
          d.baseHash = remote['base_hash'] as String? ?? '';
          continue;
        }
        d.revision = (out['revision'] as num).toInt();
        d.baseHash = out['base_hash'] as String? ?? '';
        _savedEdit = edit;
      }
      if (mounted)
        setState(() {
          _saveError = null;
          _status = l10n.studySaved;
        });
      return true;
    } catch (e) {
      if (mounted)
        setState(() {
          _saveError = e;
          _status = l10n.studySaveFailed;
        });
      return false;
    }
  }

  bool handleKey(KeyEvent e) {
    if (e is! KeyDownEvent || document == null) return false;
    final k = e.logicalKey;
    if ((HardwareKeyboard.instance.isMetaPressed ||
            HardwareKeyboard.instance.isControlPressed) &&
        k == LogicalKeyboardKey.keyZ) {
      HardwareKeyboard.instance.isShiftPressed
          ? document!.redo()
          : document!.undo();
      return true;
    }
    final tool = {
      LogicalKeyboardKey.keyV: StudyTool.select,
      LogicalKeyboardKey.keyH: StudyTool.hand,
      LogicalKeyboardKey.keyD: StudyTool.pen,
      LogicalKeyboardKey.keyE: StudyTool.eraser,
    }[k];
    if (tool != null) {
      _chooseTool(tool);
      return true;
    }
    return false;
  }

  @override
  void dispose() {
    unawaited(_titlebar(false));
    WidgetsBinding.instance.removeObserver(this);
    _syncCheck?.cancel();
    _disposed = true;
    _saveTimer?.cancel();
    _syncSubscription?.cancel();
    _pressureTimer?.cancel();
    _shapeTimer?.cancel();
    _predictionExpiry?.cancel();
    unawaited(_stylusEvents?.cancel());
    _camera.dispose();
    _cursor.dispose();
    document?.removeListener(_changed);
    document?.dispose();
    _scene.dispose();
    _live.dispose();
    super.dispose();
  }

  Offset _world(Offset p) => (p - document!.camera) / document!.zoom;
  bool get _ink => _tool == StudyTool.pen || _tool == StudyTool.highlighter;
  bool get _writing =>
      _ink || _tool == StudyTool.eraser || _tool == StudyTool.region;
  void _cameraChanged() {
    _camera.value++;
    final stage = _stageRect, view = _visibleWorld;
    if (stage == null ||
        !stage.contains(view.topLeft) ||
        !stage.contains(view.bottomRight)) {
      setState(() {});
    }
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      document!.edit++;
      setState(() {}); // Re-cull only after the gesture settles.
      unawaited(flush());
    });
  }

  bool _overControls(Offset global) {
    for (final key in [
      _dockKey,
      _zoomKey,
      _selectionMenuKey,
      _moduleKey,
      _toolbarKey,
    ]) {
      final box = key.currentContext?.findRenderObject() as RenderBox?;
      if (box != null &&
          box.hasSize &&
          box.size.contains(box.globalToLocal(global)))
        return true;
    }
    return false;
  }

  void _down(PointerDownEvent e) {
    _realStylus(e);
    if (_overControls(e.position)) return;
    final d = document!;
    final hitPoint = _world(e.localPosition);
    final hitCard = d.cards
        .where((c) => d.visible(c.layer) && c.rect.contains(hitPoint))
        .lastOrNull;
    if (hitCard != null && _tool != StudyTool.hand) {
      final headerAction =
          hitPoint.dy < hitCard.rect.top + 36 &&
          hitPoint.dx > hitCard.rect.right - 150;
      final content =
          hitPoint.dy >= hitCard.rect.top + 36 &&
          hitPoint.dy < hitCard.rect.bottom - 20;
      if (headerAction ||
          (content && (hitCard.type == 'conversation' || !_writing)))
        return;
    }
    final stylus =
        e.kind == PointerDeviceKind.stylus ||
        e.kind == PointerDeviceKind.invertedStylus;
    if (_erasing || _selectionDragging || _lasso.isNotEmpty) return;
    if (_drawingPointer != null && e.pointer != _drawingPointer) return;
    if (e.kind == PointerDeviceKind.touch &&
        _lastStylus != null &&
        DateTime.now().difference(_lastStylus!).inMilliseconds < 1000)
      return;
    if (stylus) {
      _lastStylus = DateTime.now();
      _pointers.clear();
      _panCamera = null;
    }
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length == 2 && _drawingPointer == null) {
      final p = _pointers.values.toList();
      _marquee = null;
      _lasso.clear();
      _selectionDragging = false;
      _pinchDistance = (p[0] - p[1]).distance;
      _pinchZoom = d.zoom;
      _pinchWorld = _world((p[0] + p[1]) / 2);
      return;
    }
    if (_pointers.length > 1 || _drawingPointer != null) return;
    final p = _world(e.localPosition);
    _start = _last = p;
    if (_penButtons && stylus && (e.buttons & kPrimaryStylusButton) != 0) {
      _temporaryEraser = true;
      _beginErase(e, p);
      return;
    }
    if (_tool == StudyTool.region && e.kind != PointerDeviceKind.touch) {
      if (_selectionReady &&
          _selectionBounds != null &&
          _selectionBounds!.inflate(16 / d.zoom).contains(p) &&
          (_selection.isNotEmpty || _detail.strokeIds.isNotEmpty)) {
        d.checkpoint();
        _selectionDragging = true;
        _selectionResize =
            (p - _selectionBounds!.bottomRight).distance < 22 / d.zoom;
        return;
      }
      _selectionReady = false;
      _selectionBounds = null;
      _lasso
        ..clear()
        ..add(p);
      _detail.clear();
      _regionSelection = null;
      _marquee = Rect.fromPoints(p, p);
      _selection.clear();
      _scene.value++;
      return;
    }
    if ((e.kind == PointerDeviceKind.touch &&
            !(hitCard != null &&
                !_writing &&
                hitPoint.dy < hitCard.rect.top + 36)) ||
        _tool == StudyTool.hand ||
        e.buttons == kMiddleMouseButton) {
      _panCamera = d.camera;
      _start = e.localPosition;
      return;
    }
    if (_tool == StudyTool.eraser ||
        e.kind == PointerDeviceKind.invertedStylus) {
      _temporaryEraser = e.kind == PointerDeviceKind.invertedStylus;
      _beginErase(e, p);
      return;
    }
    if (_ink) {
      if (!d.editable(d.activeLayer)) {
        _toast(l10n.studyLayerUnavailable);
        return;
      }
      if (d.strokes.length >= 29000 ||
          d.strokes.fold<int>(0, (n, s) => n + s.points.length) >= 490000) {
        _toast(l10n.studyInkLimit);
        return;
      }
      _pointBudget = math.min(
        20000,
        499900 - d.strokes.fold<int>(0, (n, s) => n + s.points.length),
      );
      _drawingPointer = e.pointer;
      _pressureStart = e.localPosition;
      _resetShape();
      _gestureBrush = _brush;
      _gestureWidth = _penWidth;
      _gestureColor = _color;
      _points = [InkPoint(p, _pressure(e))];
      _prefix.clear();
      _prefixEnd = 0;
      _anchor = '';
      for (final c in d.cards.reversed) {
        if (d.visible(c.layer) && c.rect.contains(p)) {
          _anchor = c.id;
          break;
        }
      }
      _watchPressure(e);
      _watchShape(e);
      _live.value++;
      return;
    }
    final hits = d.cards.where((a) => d.visible(a.layer) && a.rect.contains(p));
    if (hits.isNotEmpty) {
      final c = hits.last;
      if (!_selection.contains(c.id)) {
        _detail.clear();
        _regionSelection = null;
        _selection.clear();
        _selection.add(c.id);
      }
      if (d.canTransformCard(c) &&
          (p.dy < c.rect.top + 38 ||
              (!c.collapsed &&
                  (p - c.rect.bottomRight).distance < 28 / d.zoom))) {
        d.checkpoint();
        _dragCard = c.id;
        _resize =
            !c.collapsed && (p - c.rect.bottomRight).distance < 28 / d.zoom;
      }
    } else {
      _selection.clear();
      _detail.clear();
      _regionSelection = null;
      _selectionReady = false;
      _selectionBounds = null;
      _panCamera = d.camera;
      _start = e.localPosition;
    }
    setState(() {});
    _scene.value++;
  }

  double _pressure(PointerEvent e) =>
      e.kind == PointerDeviceKind.stylus ||
          e.kind == PointerDeviceKind.invertedStylus
      ? ((e.pressure - e.pressureMin) /
                math.max(.001, e.pressureMax - e.pressureMin))
            .clamp(.05, 1)
      : .7;
  void _move(PointerMoveEvent e) {
    if (_drawingPointer == e.pointer) _realStylus(e);
    final d = document!;
    if (!_pointers.containsKey(e.pointer)) return;
    if (e.kind == PointerDeviceKind.stylus ||
        e.kind == PointerDeviceKind.invertedStylus) {
      _lastStylus = DateTime.now();
    }
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length == 2 &&
        _pinchDistance != null &&
        _drawingPointer == null) {
      final p = _pointers.values.toList();
      d.zoom =
          (_pinchZoom! * (p[0] - p[1]).distance / math.max(1, _pinchDistance!))
              .clamp(.05, 8);
      d.camera = (p[0] + p[1]) / 2 - _pinchWorld! * d.zoom;
      _cameraChanged();
      return;
    }
    if (_pointers.length > 1) return;
    final p = _world(e.localPosition);
    if (_panCamera != null) {
      d.camera = _panCamera! + e.localPosition - _start!;
      _cameraChanged();
      return;
    }
    if (_drawingPointer == e.pointer) {
      if (_shape != null) {
        _adjustShape(p);
        return;
      }
      _watchPressure(e);
      _watchShape(e);
      final previous = _points.last,
          delta = (p - previous.p) * (1 - _gestureBrush.smoothing * .7);
      if (delta.distance < .4 / d.zoom || _points.length >= _pointBudget)
        return;
      final steps = (delta.distance / 4).ceil().clamp(
        1,
        math.min(100, _pointBudget - _points.length),
      );
      for (var i = 1; i <= steps; i++) {
        final t = i / steps;
        _points.add(
          InkPoint(
            previous.p + delta * t,
            previous.pressure + (_pressure(e) - previous.pressure) * t,
          ),
        );
      }
      while (_points.length - _prefixEnd > 65) {
        _prefix.add(
          StudyStroke(
            id: studyId(),
            layer: d.activeLayer,
            points: _points.sublist(_prefixEnd, _prefixEnd + 65),
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
        );
        _prefixEnd += 64;
        _scene.value++;
      }
      _live.value++;
      return;
    }
    if (_erasing) {
      _updateEraserCursor(e.localPosition);
      if (!_temporaryEraser && _eraserMode == 'lasso') {
        if (_eraserLasso.length < 1024 &&
            (_eraserLasso.last - p).distance > 3 / d.zoom)
          _eraserLasso.add(p);
        _cursor.value++;
      } else {
        _eraseAt(_last!, p);
      }
      _last = p;
      return;
    }
    if (_selectionDragging && _selectionBounds != null) {
      final from = _selectionBounds!;
      final delta = p - _last!;
      final to = _selectionResize
          ? Rect.fromLTWH(
              from.left,
              from.top,
              math.max(12 / d.zoom, from.width + delta.dx),
              math.max(12 / d.zoom, from.height + delta.dy),
            )
          : from.shift(delta);
      _transformSelection(from, to);
      _last = p;
      return;
    }
    if (_dragCard != null) {
      final c = d.cards.firstWhere((a) => a.id == _dragCard), old = c.rect;
      final delta = p - _last!;
      final next = _resize
          ? Rect.fromLTWH(
              old.left,
              old.top,
              math.max(
                c.type == 'conversation' ? 420 : 280,
                old.width + delta.dx,
              ),
              math.max(
                c.type == 'conversation' ? 480 : 180,
                old.height + delta.dy,
              ),
            )
          : old.shift(delta);
      d.transformCards(_resize ? {c.id} : _selection, old, next);
      _last = p;
      return;
    }
    if (_marquee != null) {
      _marquee = _lassoRectangle
          ? Rect.fromPoints(_start!, p)
          : _marquee!.expandToInclude(Rect.fromPoints(p, p));
      if (_lasso.length < 2048 && (_lasso.last - p).distance > 2 / d.zoom)
        _lasso.add(p);
      _cursor.value++;
    }
  }

  void _up(PointerEvent e) {
    final d = document!;
    if (!_pointers.containsKey(e.pointer)) return;
    if (_drawingPointer == e.pointer) {
      _clearPrediction();
      _lastRealStylusTime = null;
      _cancelShapeHold();
    }
    _pressureTimer?.cancel();
    _pressureTimer = null;
    _pressureOrigin = null;
    _pressureStart = null;
    _pointers.remove(e.pointer);
    if (e is PointerCancelEvent && _drawingPointer == e.pointer) {
      _resetShape();
      _points = [];
      _prefix.clear();
      _prefixEnd = 0;
      _drawingPointer = null;
      _scene.value++;
      _live.value++;
    }
    if (_drawingPointer == e.pointer) {
      final d = document!;
      d.addStroke(
        StudyStroke(
          id: studyId(),
          layer: d.activeLayer,
          points: List.of(_points),
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
      );
      _commitShape();
      final added = d.strokes.last;
      _detail.clear();
      _detail.strokeIds.addAll(
        d.strokes.where((s) => s.gesture == added.gesture).map((s) => s.id),
      );
      var region = d.strokes
          .where((s) => _detail.strokeIds.contains(s.id))
          .map((s) => s.bounds)
          .reduce((a, b) => a.expandToInclude(b))
          .inflate(16);
      _regionSelection = region;
      _selection.clear();
      final anchored = d.cards.where((c) => c.id == _anchor).firstOrNull;
      if (anchored != null) {
        _selection.add(anchored.id);
        _detail.objectId = anchored.id;
        region = region.intersect(_sourceBounds(anchored));
        _detail.region = _normalizeRegion(region, _sourceBounds(anchored));
      } else {
        _detail.region = region;
      }
      _points = [];
      _prefix.clear();
      _prefixEnd = 0;
      _drawingPointer = null;
      _resetShape();
      _scene.value++;
      _live.value++;
    }
    if (_pointers.length == 1 && _pinchDistance != null) {
      _pinchDistance = null;
      _panCamera = d.camera;
      _start = _pointers.values.single;
    }
    if (_pointers.isEmpty) {
      if (_erasing &&
          !_temporaryEraser &&
          _eraserMode == 'lasso' &&
          e is! PointerCancelEvent) {
        d.eraseLasso(_eraserLasso);
        _eraserLasso.clear();
      }
      if (_tool == StudyTool.region &&
          _marquee != null &&
          e is! PointerCancelEvent) {
        _finishSelection();
      }
      _selectionDragging = false;
      _temporaryEraser = false;
      _eraserCursor = null;
      _cursor.value++;
      _lasso.clear();
      _eraserLasso.clear();
      _panCamera = null;
      _start = _last = null;
      _marquee = null;
      _dragCard = null;
      _erasing = false;
      _pinchDistance = null;
      _scene.value++;
      setState(() {});
    }
  }

  void _scroll(PointerSignalEvent e) {
    if (e is! PointerScrollEvent ||
        _drawingPointer != null ||
        _overControls(e.position))
      return;
    GestureBinding.instance.pointerSignalResolver.register(e, (_) {
      final d = document!;
      if (HardwareKeyboard.instance.isMetaPressed ||
          HardwareKeyboard.instance.isControlPressed) {
        final p = _world(e.localPosition);
        d.zoom = (d.zoom * math.exp(-e.scrollDelta.dy * .002)).clamp(.05, 8);
        d.camera = e.localPosition - p * d.zoom;
      } else {
        d.camera -= e.scrollDelta;
      }
      _cameraChanged();
    });
  }

  void _zoomBy(double factor) {
    final d = document!,
        center = _viewport.center(Offset.zero),
        p = _world(_viewport.center(Offset.zero));
    d.zoom = (d.zoom * factor).clamp(.05, 8);
    d.camera = center - p * d.zoom;
    _cameraChanged();
  }

  void _fit() {
    final d = document!;
    final cards = d.cards.where((a) => d.visible(a.layer));
    var r = cards.isEmpty
        ? const Rect.fromLTWH(0, 0, 880, 550)
        : cards.first.rect;
    for (final c in cards) {
      r = r.expandToInclude(c.rect);
    }
    d.zoom = math
        .min(
          (_viewport.width - 100) / r.width,
          (_viewport.height - 100) / r.height,
        )
        .clamp(.05, 1.5);
    d.camera = _viewport.center(Offset.zero) - r.center * d.zoom;
    _cameraChanged();
  }

  void _toast(String s) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  Future<void> _expandPDFColumn(StudyCard root) async {
    if (_importing) return;
    final d = document!;
    setState(() => _importing = true);
    try {
      d.beginPDFColumn(root);
      if (!await flush()) return;
      for (var page = 1; page <= root.pageCount; page++) {
        if (!mounted || !d.cards.contains(root) || root.pdfColumn != root.id)
          return;
        if (d.pdfPages(root.id).any((c) => c.page == page)) continue;
        setState(() => _status = '正在展开课件 $page / ${root.pageCount} 页');
        final data = await widget.api.studyPDFPage(
          widget.ctl.lectureId,
          root.source,
          page,
        ) as Map;
        if (!mounted || !d.cards.contains(root) || root.pdfColumn != root.id)
          return;
        d.appendPDFPage(root, page, data);
        if (!await flush()) return;
      }
    } catch (e) {
      if (mounted) _toast('展开未完成：$e。已展开的页面和笔迹已保留，可点击“继续展开整列”重试');
    } finally {
      if (mounted)
        setState(() {
          _importing = false;
        });
    }
  }

  Future<void> _collapsePDFColumn(String id) async {
    try {
      document!.collapsePDFColumn(id);
      await flush();
    } catch (e) {
      if (mounted) _toast('$e');
    }
  }

  Future<void> _import({String? courseware, bool wholeCourse = false}) async {
    if (_importing) return;
    XFile? file;
    if (courseware == null) {
      file = await openFile(
        acceptedTypeGroups: [
          XTypeGroup(
            label: l10n.studyMaterials,
            extensions: [
              'pdf',
              'png',
              'jpg',
              'jpeg',
              'gif',
              'webp',
              'txt',
              'md',
              'markdown',
              'mp4',
              'mov',
              'm4v',
              'webm',
              'mkv',
            ],
          ),
        ],
      );
      if (!mounted || file == null) return;
    }
    final d = document!;
    if (!d.editable(d.activeLayer)) {
      _toast(l10n.studyPickLayer);
      return;
    }
    setState(() {
      _importing = true;
      _status = l10n.studyImporting;
    });
    try {
      dynamic out;
      if (courseware != null) {
        out = wholeCourse
            ? await widget.api.importStudyMaterial(
                widget.ctl.lectureId,
                courseware,
              )
            : await widget.api.importStudyCourseware(
                widget.ctl.lectureId,
                courseware,
              );
      } else {
        final length = await file!.length();
        if (length > 300 << 20) throw FormatException(l10n.studyFileTooLarge);
        out = await widget.api.importStudyAsset(
          widget.ctl.lectureId,
          file.name,
          file.openRead(),
          length,
        );
      }
      if (!mounted) return;
      final cards = [
        for (final a in out['objects'] as List) StudyCard.fromJson(a as Map),
      ];
      if (cards.length + d.cards.length > 2000)
        throw FormatException(l10n.studyCardLimit);
      final center = _world(_viewport.center(Offset.zero));
      d.checkpoint();
      var y = center.dy - 120;
      for (final c in cards) {
        c.layer = d.activeLayer;
        c.rect = Rect.fromLTWH(center.dx - 160, y, c.rect.width, c.rect.height);
        y += c.rect.height + 36;
      }
      d.cards.addAll(cards);
      _selection
        ..clear()
        ..add(cards.first.id);
      d.changed();
      _tool = StudyTool.select;
      await flush();
    } catch (e) {
      _toast(l10n.studyImportError('$e'));
    } finally {
      if (mounted)
        setState(() {
          _importing = false;
          if (_saveError == null) _status = l10n.studySaved;
        });
    }
  }

  Future<void> _text([StudyCard? card]) async {
    final input = TextEditingController(text: card?.text ?? '');
    final text = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(card == null ? l10n.studyAddText : l10n.studyEditText),
        content: SizedBox(
          width: 500,
          child: TextField(
            controller: input,
            autofocus: true,
            minLines: 5,
            maxLines: 15,
            maxLength: 200000,
            decoration: InputDecoration(hintText: l10n.studyTextHint),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, input.text),
            child: Text(l10n.commonSave),
          ),
        ],
      ),
    );
    // Dialog animations can retain the input after the route result completes.
    Future.delayed(const Duration(milliseconds: 400), input.dispose);
    if (!mounted || text == null) return;
    final d = document!;
    if (!d.editable(card?.layer ?? d.activeLayer)) {
      _toast(l10n.studyLocked);
      return;
    }
    d.checkpoint();
    if (card != null) {
      card.text = text;
    } else {
      final p = _world(_viewport.center(Offset.zero));
      final c = StudyCard(
        id: studyId(),
        type: 'text',
        layer: d.activeLayer,
        rect: Rect.fromLTWH(p.dx - 100, p.dy - 100, 480, 360),
        title: l10n.studyTextCard,
        text: text,
      );
      d.cards.add(c);
      _selection
        ..clear()
        ..add(c.id);
    }
    d.changed();
  }

  Future<void> _ask() async {
    await _openConversation();
  }

  void _layers() {
    showModalBottomSheet(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => SafeArea(
          child: SizedBox(
            height: 330,
            child: Column(
              children: [
                ListTile(
                  title: Text(l10n.studyLayers),
                  trailing: IconButton(
                    tooltip: l10n.studyAddLayer,
                    icon: const Icon(Icons.add),
                    onPressed: () {
                      final d = document!;
                      if (d.layers.length >= 32) return;
                      d.checkpoint();
                      final l = StudyLayer(
                        studyId(),
                        l10n.studyLayerName(d.layers.length + 1),
                      );
                      d.layers.add(l);
                      d.activeLayer = l.id;
                      d.changed();
                      update(() {});
                    },
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      for (final l in document!.layers)
                        ListTile(
                          selected: document!.activeLayer == l.id,
                          title: Text(l.name),
                          onTap: () {
                            setState(() => document!.activeLayer = l.id);
                            update(() {});
                          },
                          leading: IconButton(
                            tooltip: l10n.studyToggleVisible,
                            icon: Icon(
                              l.visible
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () {
                              document!.checkpoint();
                              l.visible = !l.visible;
                              document!.changed();
                              update(() {});
                            },
                          ),
                          trailing: IconButton(
                            tooltip: l10n.studyToggleLocked,
                            icon: Icon(
                              l.locked
                                  ? Icons.lock_outline
                                  : Icons.lock_open_outlined,
                            ),
                            onPressed: () {
                              document!.checkpoint();
                              l.locked = !l.locked;
                              document!.changed();
                              update(() {});
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> exportRecovery() async {
    if (document == null) return;
    final dest = await getSaveLocation(
      suggestedName: '学习画布-${widget.ctl.lectureId}.json',
    );
    if (dest == null || !mounted) return;
    try {
      await File(dest.path).writeAsString(jsonEncode(document!.json()));
      _toast(l10n.studyRecoverySaved);
    } catch (e) {
      _toast(l10n.studyExportError('$e'));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.fullscreen) return widget.video;
    if (_loadError != null)
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('画布打开失败：$_loadError'),
            TextButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    final d = document;
    if (d == null) return const Center(child: CircularProgressIndicator());
    return LayoutBuilder(
      builder: (_, size) {
        _viewport = Size(size.maxWidth, size.maxHeight);
        return _canvas(d);
      },
    );
  }

  void _moveDock(String id, StudyDockPlacement next) {
    setState(() {
      final old = switch (id) {
        'tools' => _toolPlacement,
        'modules' => _modulePlacement,
        _ => _penPlacement,
      };
      bool occupied(StudyDockPlacement p) =>
          p.edge == next.edge && (p.offset - next.offset).abs() < .25;
      if (id != 'tools' && occupied(_toolPlacement)) _toolPlacement = old;
      if (id != 'modules' && occupied(_modulePlacement)) _modulePlacement = old;
      if (id != 'pens' && occupied(_penPlacement)) _penPlacement = old;
      switch (id) {
        case 'tools':
          _toolPlacement = next;
        case 'modules':
          _modulePlacement = next;
        default:
          _penPlacement = next;
      }
    });
    unawaited(_saveLayout());
  }

  Rect get _visibleWorld => Rect.fromLTWH(
    -document!.camera.dx / document!.zoom,
    -document!.camera.dy / document!.zoom,
    _viewport.width / document!.zoom,
    _viewport.height / document!.zoom,
  );

  Widget _canvas(StudyDocument d) {
    final stage = _visibleWorld.inflate(
      math.max(_viewport.width, _viewport.height) / d.zoom,
    );
    _stageRect = stage;
    return RepaintBoundary(
      key: _inputSurface,
      child: ClipRect(
        child: Listener(
          key: const ValueKey('study-input'),
          behavior: HitTestBehavior.translucent,
          onPointerHover: (e) {
            if (e.kind == PointerDeviceKind.stylus ||
                e.kind == PointerDeviceKind.invertedStylus)
              _lastStylus = DateTime.now();
            if (_tool == StudyTool.eraser ||
                e.kind == PointerDeviceKind.invertedStylus)
              _updateEraserCursor(e.localPosition);
          },
          onPointerDown: _down,
          onPointerMove: _move,
          onPointerUp: _up,
          onPointerCancel: _up,
          onPointerSignal: _scroll,
          onPointerPanZoomStart: (e) {
            if (_drawingPointer != null ||
                _erasing ||
                _overControls(e.position))
              return;
            _pinchZoom = d.zoom;
            _pinchWorld = _world(e.localPosition);
            _panCamera = d.camera;
          },
          onPointerPanZoomUpdate: (e) {
            if (_pinchWorld == null || _pinchZoom == null || _panCamera == null)
              return;
            d.zoom = (_pinchZoom! * e.scale).clamp(.05, 8);
            d.camera = e.localPosition + e.pan - _pinchWorld! * d.zoom;
            _cameraChanged();
          },
          onPointerPanZoomEnd: (_) {
            _pinchWorld = null;
            _panCamera = null;
          },
          child: MouseRegion(
            onExit: (_) {
              _eraserCursor = null;
              _cursor.value++;
            },
            child: Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned.fill(
                  child: RepaintBoundary(
                    key: _capture,
                    child: Stack(
                      fit: StackFit.expand,
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: RepaintBoundary(
                            child: CustomPaint(
                              painter: _Paper(
                                document: d,
                                repaint: _camera,
                                style: _paperStyle,
                                color: _paperColor,
                              ),
                            ),
                          ),
                        ),
                        // Camera changes transform an already laid-out world. Media widgets and
                        // recorded ink are retained until the visible area leaves this bounded stage.
                        Positioned(
                          left: 0,
                          top: 0,
                          width: stage.width,
                          height: stage.height,
                          child: AnimatedBuilder(
                            animation: _camera,
                            builder: (_, child) => Transform(
                              alignment: Alignment.topLeft,
                              transform: Matrix4.identity()
                                ..translate(
                                  d.camera.dx + stage.left * d.zoom,
                                  d.camera.dy + stage.top * d.zoom,
                                )
                                ..scale(d.zoom),
                              child: child,
                            ),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Positioned.fill(
                                  child: IgnorePointer(
                                    child: RepaintBoundary(
                                      child: CustomPaint(
                                        painter: _ConnectionPainter(
                                          d,
                                          stage,
                                          _scene,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                for (final c in d.cards.where(
                                  (a) =>
                                      d.visible(a.layer) &&
                                      (a.type == 'lecture' ||
                                          a.type == 'video' ||
                                          a.type == 'conversation' ||
                                          a.rect.overlaps(stage)),
                                ))
                                  Positioned(
                                    key: ValueKey('study-card/${c.id}'),
                                    left: c.rect.left - stage.left,
                                    top: c.rect.top - stage.top,
                                    width: c.rect.width,
                                    height: c.rect.height,
                                    child: RepaintBoundary(child: _card(c)),
                                  ),
                                Positioned.fill(
                                  child: IgnorePointer(
                                    child: RepaintBoundary(
                                      child: CustomPaint(
                                        painter: _InkScene(
                                          document: d,
                                          live: _prefix,
                                          stage: stage,
                                          repaint: _scene,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: IgnorePointer(
                            child: RepaintBoundary(
                              child: CustomPaint(
                                painter: _InkTail(
                                  document: d,
                                  points: () =>
                                      _shapePreview ??
                                      (_predicted.isEmpty
                                          ? _points
                                          : [
                                              ..._points.skip(_prefixEnd),
                                              ..._predicted,
                                            ]),
                                  start: () =>
                                      _predicted.isEmpty ? _prefixEnd : 0,
                                  color: () => _gestureColor,
                                  width: () => _gestureWidth,
                                  brush: () => _gestureBrush,
                                  tool: () => _tool,
                                  repaint: Listenable.merge([
                                    _live,
                                    _scene,
                                    _camera,
                                  ]),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        key: const ValueKey('study-feedback'),
                        painter: _InteractionFeedback(
                          this,
                          Listenable.merge([_cursor, _scene, _camera]),
                        ),
                      ),
                    ),
                  ),
                ),
                if (Platform.isMacOS)
                  const Positioned(
                    top: 0,
                    left: 80,
                    right: 0,
                    height: 22,
                    child: DragToMoveArea(child: SizedBox.expand()),
                  ),
                _topToolbar(),
                _moduleRail(),
                _penDock(),
                _selectionToolbar(),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: Material(
                    key: _zoomKey,
                    elevation: 2,
                    borderRadius: BorderRadius.circular(20),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: l10n.studyZoomOut,
                          onPressed: () => _zoomBy(1 / 1.2),
                          icon: const Icon(Icons.remove, size: 18),
                        ),
                        ValueListenableBuilder<int>(
                          valueListenable: _camera,
                          builder: (_, value, child) => Text(
                            '${(d.zoom * 100).round()}%',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        IconButton(
                          tooltip: l10n.studyZoomIn,
                          onPressed: () => _zoomBy(1.2),
                          icon: const Icon(Icons.add, size: 18),
                        ),
                        IconButton(
                          tooltip: l10n.studyFit,
                          onPressed: _fit,
                          icon: const Icon(Icons.fit_screen, size: 19),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(StudyCard c) {
    final d = document!,
        selected = _selection.contains(c.id),
        cs = Theme.of(context).colorScheme;
    return IgnorePointer(
      ignoring: _writing || _tool == StudyTool.hand || !d.editable(c.layer),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? cs.primary : const Color(0xffdce1ec),
            width: selected ? 2 : 1,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x140c1832),
              blurRadius: 20,
              offset: Offset(0, 5),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            SizedBox(
              height: 36,
              child: ColoredBox(
                color: c.type == 'lecture'
                    ? const Color(0xffeae8ff)
                    : const Color(0xfff5f6fb),
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    Icon(
                      c.type == 'lecture' || c.type == 'video'
                          ? Icons.play_circle_outline
                          : c.type == 'text'
                          ? Icons.notes
                          : Icons.description_outlined,
                      size: 16,
                      color: const Color(0xff615b86),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        c.type == 'pdf' && c.pdfColumn.isNotEmpty
                            ? '${c.title} · 第 ${c.page}/${c.pageCount} 页'
                            : c.title,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xff34415c),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (c.type != 'conversation')
                      Draggable<String>(
                        data: c.id,
                        feedback: Material(
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(c.title),
                          ),
                        ),
                        child: IconButton(
                          tooltip: '加入 AI 对话（或拖到引用条）',
                          onPressed: () => _chooseConversation(c),
                          icon: const Icon(
                            Icons.add_comment_outlined,
                            size: 15,
                          ),
                        ),
                      ),
                    IconButton(
                      tooltip: c.collapsed ? '展开模块' : '折叠模块',
                      onPressed: c.type == 'pdfdoc' && c.pdfColumn.isNotEmpty
                          ? null
                          : () {
                              d.checkpoint();
                              c.collapsed = !c.collapsed;
                              if (c.collapsed) {
                                c.expandedH = c.rect.height;
                                c.rect = Rect.fromLTWH(
                                  c.rect.left,
                                  c.rect.top,
                                  c.rect.width,
                                  60,
                                );
                              } else {
                                c.rect = Rect.fromLTWH(
                                  c.rect.left,
                                  c.rect.top,
                                  c.rect.width,
                                  math.max(240, c.expandedH),
                                );
                              }
                              d.changed();
                            },
                      icon: Icon(
                        c.collapsed ? Icons.expand_more : Icons.expand_less,
                        size: 16,
                      ),
                    ),
                    if (c.type != 'lecture' &&
                        !(c.type == 'pdfdoc' && c.pdfColumn.isNotEmpty))
                      IconButton(
                        tooltip: '删除模块',
                        onPressed: () {
                          d.checkpoint();
                          d.cards.removeWhere((v) => v.id == c.id);
                          d.connections.removeWhere(
                            (v) => v.from == c.id || v.to == c.id,
                          );
                          d.strokes.removeWhere((v) => v.anchor == c.id);
                          d.changed();
                        },
                        icon: const Icon(Icons.close, size: 15),
                      ),
                    if (c.type == 'pdfdoc' &&
                        (c.pdfColumn.isEmpty ||
                            d.pdfPages(c.id).length < c.pageCount))
                      IconButton(
                        tooltip: c.pdfColumn.isEmpty ? '在画布展开为一列' : '继续展开整列',
                        onPressed: _importing
                            ? null
                            : () => _expandPDFColumn(c),
                        icon: const Icon(Icons.unfold_more, size: 16),
                      ),
                    if (c.pdfColumn.isNotEmpty)
                      IconButton(
                        tooltip: '收起整列',
                        onPressed: _importing
                            ? null
                            : () => _collapsePDFColumn(c.pdfColumn),
                        icon: const Icon(Icons.unfold_less, size: 16),
                      ),
                    if (c.type == 'pdf' || c.type == 'pdfdoc')
                      IconButton(
                        tooltip: '选择文档文字',
                        onPressed: () => _documentSelection(c),
                        icon: const Icon(Icons.text_snippet_outlined, size: 16),
                      ),
                    if (c.generated)
                      IconButton(
                        tooltip: '编辑知识卡片',
                        onPressed: () => _editKnowledge(c),
                        icon: const Icon(Icons.edit_outlined, size: 15),
                      ),
                    if (c.type == 'text')
                      IconButton(
                        tooltip: l10n.studyEditText,
                        onPressed: () => _text(c),
                        icon: const Icon(Icons.edit_outlined, size: 15),
                      ),
                    const Icon(
                      Icons.drag_indicator,
                      size: 16,
                      color: Color(0xff949cb0),
                    ),
                    const SizedBox(width: 10),
                  ],
                ),
              ),
            ),
            Expanded(
              child: OverflowBox(
                minHeight: c.collapsed ? math.max(480, c.expandedH) - 56 : null,
                maxHeight: c.collapsed ? math.max(480, c.expandedH) - 56 : null,
                child: Offstage(
                  offstage: c.collapsed,
                  child: switch (c.type) {
                    'pdfdoc' => _PDFBody(owner: this, card: c),
                    'conversation' => _ConversationBody(
                      key: _conversationKeys.putIfAbsent(
                        c.id,
                        () => GlobalKey<_ConversationBodyState>(),
                      ),
                      owner: this,
                      card: c,
                      initial: _initialConversations[c.id],
                    ),
                    'lecture' => Column(
                      children: [
                        Expanded(child: widget.video),
                        SizedBox(
                          height: 30,
                          child: TextButton(
                            onPressed: () => showDialog<void>(
                              context: context,
                              builder: (_) => Dialog(
                                child: SizedBox(
                                  width: 480,
                                  height: 600,
                                  child: widget.panel,
                                ),
                              ),
                            ),
                            child: const Text('大纲 · 字幕 · 课程资料'),
                          ),
                        ),
                      ],
                    ),
                    'image' || 'pdf' => Image(
                      image: ResizeImage(
                        NetworkImage(widget.api.fileUrl(c.path)),
                        width: 1500,
                        height: 1500,
                        policy: ResizeImagePolicy.fit,
                      ),
                      fit: BoxFit.contain,
                      errorBuilder: (_, error, stack) =>
                          Center(child: Text(l10n.studyImageFailed)),
                    ),
                    'video' => _LocalVideo(
                      key: _localVideoKeys.putIfAbsent(
                        c.id,
                        () => GlobalKey<_LocalVideoState>(),
                      ),
                      url: c.path.isEmpty
                          ? widget.api.studyMediaUrl(widget.ctl.lectureId, c.id)
                          : widget.api.fileUrl(c.path),
                      initialMs: _localVideoTimes[c.id] ?? 0,
                      onPosition: (ms) => _localVideoTimes[c.id] = ms,
                    ),
                    'note' ||
                    'explanation' ||
                    'knowledge' ||
                    'practice' => _KnowledgeBody(
                      card: c,
                      onSource: _focusSource,
                      editable: d.editable(c.layer),
                      onBeginAnswer: d.checkpoint,
                      onAnswer: (i, value) {
                        if (d.editable(c.layer)) {
                          c.responses['$i'] = value;
                          d.changed();
                        }
                      },
                    ),
                    _ => SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: SelectableText(
                          c.text,
                          onSelectionChanged: (selection, cause) {
                            if (!selection.isCollapsed) {
                              _selection
                                ..clear()
                                ..add(c.id);
                              _detail.clear();
                              _detail
                                ..objectId = c.id
                                ..start = selection.start
                                ..end = selection.end;
                            }
                          },
                          style: const TextStyle(
                            fontSize: 16,
                            height: 1.65,
                            color: Color(0xff25344a),
                          ),
                        ),
                      ),
                    ),
                  },
                ),
              ),
            ),
            SizedBox(
              height: 16,
              child: Align(
                alignment: Alignment.bottomRight,
                child: Icon(
                  Icons.south_east,
                  size: 12,
                  color: selected ? cs.primary : const Color(0xffa2aabd),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocalVideo extends StatefulWidget {
  const _LocalVideo({
    super.key,
    required this.url,
    required this.initialMs,
    required this.onPosition,
  });
  final String url;
  final int initialMs;
  final ValueChanged<int> onPosition;
  @override
  State<_LocalVideo> createState() => _LocalVideoState();
}

class _LocalVideoState extends State<_LocalVideo> {
  late final player = Player();
  late final controller = VideoController(player);
  StreamSubscription? _errors;
  StreamSubscription? _positions;
  String? _error;
  @override
  void initState() {
    super.initState();
    _errors = player.stream.error.listen((error) {
      if (mounted) setState(() => _error = error);
    });
    _positions = player.stream.position.listen(
      (p) => widget.onPosition(p.inMilliseconds),
    );
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      await controller.platform.future;
      if (!mounted) return;
      await player.open(Media(widget.url), play: false);
      if (mounted && widget.initialMs > 0)
        await player.seek(Duration(milliseconds: widget.initialMs));
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  void dispose() {
    _errors?.cancel();
    _positions?.cancel();
    unawaited(player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _error == null
      ? Video(controller: controller)
      : Center(child: Text(l10n.studyLocalVideoError(_error!)));
}

class _Paper extends CustomPainter {
  _Paper({
    this.document,
    Listenable? repaint,
    this.style = 'ruled',
    this.color = 0xffffffff,
  }) : super(repaint: repaint);
  final String style;
  final int color;
  final StudyDocument? document;
  @override
  void paint(Canvas c, Size s) {
    c.drawRect(Offset.zero & s, Paint()..color = Color(color));
    if (style == 'blank') return;
    var spacing = document == null ? 14.0 : 36 * document!.zoom;
    while (document != null && spacing < 22) {
      spacing *= 2;
    }
    final camera = document?.camera ?? Offset.zero;
    final line = Paint()
      ..color = const Color(0x1826354a)
      ..strokeWidth = .7;
    for (var y = camera.dy % spacing; y < s.height; y += spacing) {
      if (style == 'ruled' || style == 'grid') {
        c.drawLine(Offset(0, y), Offset(s.width, y), line);
      } else {
        for (var x = camera.dx % spacing; x < s.width; x += spacing) {
          c.drawCircle(Offset(x, y), .8, line);
        }
      }
    }
    if (style == 'grid') {
      for (var x = camera.dx % spacing; x < s.width; x += spacing) {
        c.drawLine(Offset(x, 0), Offset(x, s.height), line);
      }
    }
  }

  @override
  bool shouldRepaint(_Paper old) => true;
}

class _InkScene extends CustomPainter {
  _InkScene({
    required this.document,
    required this.live,
    required this.stage,
    required Listenable repaint,
  }) : super(repaint: repaint);
  final StudyDocument document;
  final List<StudyStroke> live;
  final Rect stage;
  @override
  void paint(Canvas c, Size s) {
    final d = document;
    c.save();
    c.translate(-stage.left, -stage.top);
    final viewport = stage;
    for (final stroke in [...d.strokes, ...live]) {
      if (d.strokeVisible(stroke) && stroke.bounds.overlaps(viewport))
        stroke.paint(c);
    }
    c.restore();
  }

  @override
  bool shouldRepaint(_InkScene old) =>
      old.stage != stage || old.document != document;
  @override
  bool shouldRebuildSemantics(_InkScene old) => false;
}

class _InkTail extends CustomPainter {
  _InkTail({
    required this.document,
    required this.points,
    required this.start,
    required this.color,
    required this.width,
    required this.tool,
    required this.brush,
    required Listenable repaint,
  }) : super(repaint: repaint);
  final StudyDocument document;
  final List<InkPoint> Function() points;
  final int Function() start, color;
  final double Function() width;
  final StudyTool Function() tool;
  final StudyBrush Function() brush;
  @override
  void paint(Canvas c, Size s) {
    final p = points();
    if (p.isEmpty) return;
    c.save();
    c.translate(document.camera.dx, document.camera.dy);
    c.scale(document.zoom);
    paintInk(
      c,
      p.sublist(start()),
      color(),
      width(),
      tool() == StudyTool.highlighter ? 'highlighter' : 'pen',
      brush: brush(),
    );
    c.restore();
  }

  @override
  bool shouldRepaint(_InkTail old) => true;
  @override
  bool shouldRebuildSemantics(_InkTail old) => false;
}
