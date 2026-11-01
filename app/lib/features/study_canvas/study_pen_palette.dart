part of 'study_canvas.dart';

const _quickColors = [
  0xff26354a,
  0xff6254d7,
  0xffe65365,
  0xff7d5f4c,
  0xff9a68ce,
  0xff2382ce,
  0xff2d8986,
  0xffffd34f,
  0xffea7b3c,
  0xffffffff,
];

extension _StudyPenPalette on StudyCanvasState {
  int get _penRotation => switch (_penPlacement.edge) {
    StudyDockEdge.left => 1,
    StudyDockEdge.right => 3,
    StudyDockEdge.top => 2,
    StudyDockEdge.bottom => 0,
  };

  Widget _palettePen({
    required Widget child,
    required String label,
    required VoidCallback pick,
    required bool selected,
    required bool vertical,
    Key? key,
    GlobalKey? anchor,
    VoidCallback? settings,
  }) => Tooltip(
    message: label,
    child: SizedBox(
      key: anchor,
      width: vertical ? 36 : 24,
      height: vertical ? 24 : 38,
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkWell(
          key: key,
          onTap: pick,
          onLongPress: settings,
          child: RotatedBox(
            quarterTurns: _penRotation,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 150),
              offset: selected ? Offset.zero : const Offset(0, .1),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: child,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _penDock() => StudyEdgeDock(
    id: 'pens',
    label: '笔盒',
    scale: 1.15,
    surfaceKey: _dockKey,
    placement: _penPlacement,
    thickness: _penPlacement.vertical ? 36 : 42,
    centerHandle: true,
    onChanged: (p) => _moveDock('pens', p),
    trailing: _action(
      _dockSmall ? '展开笔盒' : '收起笔盒',
      _dockSmall ? Icons.draw_outlined : Icons.keyboard_arrow_down,
      () {
        _update(() => _dockSmall = !_dockSmall);
        unawaited(_saveLayout());
      },
      compact: true,
    ),
    children: (vertical) => [
      if (!_dockSmall) ...[
        _action(
          '画笔与橡皮设置',
          Icons.palette_outlined,
          () => _advancedPenSettings(eraser: _tool == StudyTool.eraser),
          compact: true,
        ),
        for (var i = 0; i < _presets.length; i++)
          _palettePen(
            vertical: vertical,
            label: '${_presets[i].name}：点选，再点设置',
            key: i == 0
                ? const ValueKey('study-tool-pen')
                : ValueKey('study-pen-$i'),
            anchor: _penItemKeys.putIfAbsent(i, GlobalKey.new),
            selected: i == _presetIndex && _ink,
            pick: () {
              if (i == _presetIndex && _ink)
                _penSettings();
              else
                _pickPen(i);
            },
            settings: () {
              _pickPen(i);
              _penSettings();
            },
            child: CustomPaint(
              painter: _PalettePenPainter(
                _presets[i].color,
                _presets[i].brush.family,
              ),
            ),
          ),
        _palettePen(
          vertical: vertical,
          label: '橡皮：再点设置',
          key: const ValueKey('study-tool-eraser'),
          anchor: _eraserKey,
          selected: _tool == StudyTool.eraser,
          pick: () => _chooseTool(StudyTool.eraser),
          settings: () => _penSettings(eraser: true),
          child: CustomPaint(painter: _PalettePenPainter(0xffef8c95, 'eraser')),
        ),
        _palettePen(
          vertical: vertical,
          label: '套索',
          selected: _tool == StudyTool.region,
          pick: () => _chooseTool(StudyTool.region),
          child: CustomPaint(painter: _PalettePenPainter(0xff8f949c, 'lasso')),
        ),
        _divider(vertical, compact: true),
        if (_tool == StudyTool.region) ...[
          _action(
            '自由套索',
            Icons.gesture,
            () => _update(() => _lassoRectangle = false),
            selected: !_lassoRectangle,
            compact: true,
          ),
          _action(
            '矩形框选',
            Icons.crop_free,
            () => _update(() => _lassoRectangle = true),
            selected: _lassoRectangle,
            compact: true,
          ),
          _action('所选区域问 AI', Icons.auto_awesome_outlined, _ask, compact: true),
        ] else ...[
          SizedBox(
            width: vertical ? 34 : 92,
            height: vertical ? 92 : 34,
            child: Wrap(
              direction: vertical ? Axis.vertical : Axis.horizontal,
              spacing: 3,
              runSpacing: 2,
              children: [
                for (final color in _quickColors)
                  Tooltip(
                    message: '切换笔色 #${(color & 0xffffff).toRadixString(16)}',
                    child: InkWell(
                      key: ValueKey('study-pen-color-$color'),
                      onTap: () => _quickPen(color: color),
                      onLongPress: () => _advancedPenSettings(tab: 1),
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: Color(color),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: color == 0xffffffff
                                ? const Color(0xffd9dade)
                                : Colors.transparent,
                          ),
                        ),
                        child: _color == color && _ink
                            ? Icon(
                                Icons.check,
                                size: 13,
                                color: Color(color).computeLuminance() > .55
                                    ? Colors.black
                                    : Colors.white,
                              )
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          for (final width
              in (_brush.family == 'highlighter'
                  ? [12.0, 22.0, 32.0]
                  : [1.0, 3.0, 6.0]))
            SizedBox(
              width: 36,
              height: vertical ? 30 : 34,
              child: InkWell(
                onLongPress: _penSettings,
                child: Flex(
                  direction: Axis.horizontal,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      tooltip: '笔宽 ${width.toInt()}',
                      isSelected: _ink && (_penWidth - width).abs() < .05,
                      style: IconButton.styleFrom(
                        minimumSize: const Size(24, 24),
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () => _quickPen(width: width),
                      icon: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _ink && (_penWidth - width).abs() < .05
                                ? const Color(0xff0788ff)
                                : const Color(0xffc5c8cd),
                            width: 1.5,
                          ),
                        ),
                        child: Transform.rotate(
                          angle: -.65,
                          child: Center(
                            child: Container(
                              width: 17,
                              height: math.min(9, width + 1),
                              color: const Color(0xff25282d),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Text(
                      '${width.toInt()}',
                      style: const TextStyle(
                        fontSize: 9,
                        height: 1.1,
                        color: Color(0xff535862),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    ],
  );

  Future<void> _penSettings({bool eraser = false}) async {
    final box =
        (eraser ? _eraserKey : _penItemKeys[_presetIndex])?.currentContext
                ?.findRenderObject()
            as RenderBox?;
    final dock = _dockKey.currentContext?.findRenderObject() as RenderBox?;
    final target = box ?? dock;
    final rect = target == null
        ? Rect.fromCenter(
            center: _viewport.center(Offset.zero),
            width: 40,
            height: 40,
          )
        : MatrixUtils.transformRect(
            target.getTransformTo(null),
            Offset.zero & target.size,
          );
    var advanced = false;
    await showDialog<void>(
      context: context,
      useSafeArea: false,
      barrierColor: Colors.black.withValues(alpha: .015),
      builder: (popup) => StatefulBuilder(
        builder: (popup, refresh) {
          void change(VoidCallback action) {
            _update(action);
            refresh(() {});
            unawaited(_saveBrushSettings());
          }

          final size = MediaQuery.sizeOf(popup),
              width = math.min(300.0, size.width - 24),
              height = math.min(
                eraser
                    ? 360.0
                    : _brush.family == 'pencil'
                    ? 530.0
                    : 490.0,
                size.height - 48,
              );
          final x =
              (_penPlacement.edge == StudyDockEdge.left
                      ? rect.right + 12
                      : _penPlacement.edge == StudyDockEdge.right
                      ? rect.left - width - 12
                      : rect.center.dx - width / 2)
                  .clamp(12.0, math.max(12.0, size.width - width - 12));
          final y =
              (_penPlacement.edge == StudyDockEdge.top
                      ? rect.bottom + 12
                      : rect.top - height - 12)
                  .clamp(
                    MediaQuery.paddingOf(popup).top + 12,
                    math.max(
                      MediaQuery.paddingOf(popup).top + 12,
                      size.height - height - 12,
                    ),
                  );
          Widget slider(
            String label,
            double value,
            double min,
            double max,
            ValueChanged<double> update,
          ) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(label, style: const TextStyle(fontSize: 13)),
                  const Spacer(),
                  Text(
                    value.toStringAsFixed(label == '笔刷粗细' ? 1 : 2),
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
              SliderTheme(
                data: SliderTheme.of(popup).copyWith(
                  trackHeight: 2,
                  trackShape: const RoundedRectSliderTrackShape(),
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 12,
                  ),
                  activeTrackColor: const Color(0xff0788ff),
                  inactiveTrackColor: const Color(0xffebedf2),
                  thumbColor: const Color(0xff0788ff),
                ),
                child: Slider(
                  value: value.clamp(min, max),
                  min: min,
                  max: max,
                  onChanged: (v) => change(() => update(v)),
                ),
              ),
            ],
          );
          return Stack(
            children: [
              Positioned(
                left: x.toDouble(),
                top: y.toDouble(),
                width: width,
                height: height,
                child: Material(
                  key: const ValueKey('study-pen-popover'),
                  color: Colors.white,
                  elevation: 8,
                  shadowColor: Colors.black26,
                  borderRadius: BorderRadius.circular(20),
                  clipBehavior: Clip.antiAlias,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                eraser ? '橡皮' : _presets[_presetIndex].name,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (!eraser)
                              IconButton(
                                tooltip: '收藏为新预设',
                                onPressed: _presets.length >= 20
                                    ? null
                                    : () => change(() {
                                        _presets.add(
                                          StudyPenPreset(
                                            '${_brushNames[_brush.family]} ${_presets.length + 1}',
                                            _color,
                                            _penWidth,
                                            _brush,
                                            shapeAssist: _presets[_presetIndex]
                                                .shapeAssist,
                                          ),
                                        );
                                        _presetIndex = _presets.length - 1;
                                      }),
                                icon: const Icon(Icons.star_border, size: 21),
                              ),
                            IconButton(
                              tooltip: '关闭设置',
                              onPressed: () => Navigator.pop(popup),
                              icon: const Icon(Icons.close, size: 18),
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        if (eraser) ...[
                          Wrap(
                            spacing: 6,
                            children: [
                              for (final mode in const {
                                'partial': '局部',
                                'stroke': '整笔',
                                'lasso': '圈选',
                              }.entries)
                                ChoiceChip(
                                  label: Text(mode.value),
                                  selected: _eraserMode == mode.key,
                                  onSelected: (_) => change(() {
                                    _eraserMode = mode.key;
                                    _tool = StudyTool.eraser;
                                  }),
                                ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          slider(
                            '橡皮半径',
                            _eraserSize,
                            3,
                            100,
                            (v) => _eraserSize = v,
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              '压感橡皮',
                              style: TextStyle(fontSize: 13),
                            ),
                            value: _pressureEraser,
                            onChanged: (v) => change(() => _pressureEraser = v),
                          ),
                        ] else ...[
                          const Text(
                            '实时笔迹预览',
                            style: TextStyle(
                              fontSize: 10,
                              color: Color(0xff737983),
                            ),
                          ),
                          SizedBox(
                            height: 42,
                            width: double.infinity,
                            child: CustomPaint(
                              painter: _BrushPreview(_color, _penWidth, _brush),
                            ),
                          ),
                          const SizedBox(height: 16),
                          SwitchListTile(
                            key: const ValueKey('study-shape-assist'),
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              '一笔成形',
                              style: TextStyle(fontSize: 13),
                            ),
                            subtitle: const Text(
                              '画完停住约 0.7 秒；支持箭头和多边形',
                              style: TextStyle(fontSize: 11),
                            ),
                            value: _presets[_presetIndex].shapeAssist,
                            onChanged: (v) => change(
                              () => _presets[_presetIndex].shapeAssist = v,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () {
                              Navigator.pop(popup);
                              unawaited(_stylusSettings());
                            },
                            icon: const Icon(
                              Icons.settings_input_component,
                              size: 16,
                            ),
                            label: const Text('手写笔与预测'),
                          ),
                          slider(
                            '笔刷粗细',
                            _penWidth,
                            .2,
                            _brush.family == 'highlighter' ? 80 : 20,
                            (v) => _penWidth = v,
                          ),
                          if (_brush.family != 'ballpoint' &&
                              _brush.family != 'highlighter')
                            slider(
                              '压感',
                              _brush.pressure,
                              0,
                              1,
                              (v) => _brush = _brush.copyWith(pressure: v),
                            ),
                          if (_brush.family == 'highlighter' ||
                              _brush.family == 'pencil')
                            slider(
                              '不透明度',
                              _brush.opacity,
                              .05,
                              1,
                              (v) => _brush = _brush.copyWith(opacity: v),
                            ),
                          slider(
                            '平滑程度',
                            _brush.smoothing,
                            0,
                            1,
                            (v) => _brush = _brush.copyWith(smoothing: v),
                          ),
                        ],
                        TextButton(
                          onPressed: () {
                            advanced = true;
                            Navigator.pop(popup);
                          },
                          child: const Text('更多画笔设置'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
    if (advanced && mounted) await _advancedPenSettings(eraser: eraser);
  }
}

/// Original vector artwork drawn for this app; no APK bitmaps or paths are used.
class _PalettePenPainter extends CustomPainter {
  _PalettePenPainter(this.color, this.family);
  final int color;
  final String family;
  @override
  void paint(Canvas c, Size s) {
    final scale = math.min(s.width / 32, s.height / 90);
    c.save();
    c.translate((s.width - 32 * scale) / 2, s.height - 90 * scale);
    c.scale(scale);
    final shade = Paint()
      ..shader = ui.Gradient.linear(
        const Offset(6, 0),
        const Offset(26, 0),
        [
          const Color(0xffb9bcc3),
          Colors.white,
          const Color(0xffd8dbe0),
          const Color(0xffa0a5af),
        ],
        [0, .35, .75, 1],
      );
    final ink = Paint()..color = Color(color);
    final barrel = RRect.fromRectAndRadius(
      const Rect.fromLTWH(7, 39, 18, 58),
      const Radius.circular(5),
    );
    if (family != 'pencil' && family != 'fountain') {
      c.drawRRect(barrel, shade);
    }
    if (family == 'eraser') {
      c.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(7, 18, 18, 31),
          const Radius.circular(7),
        ),
        Paint()
          ..shader = ui.Gradient.linear(
            const Offset(7, 0),
            const Offset(25, 0),
            [const Color(0xfff4b3b7), const Color(0xffdf7e89)],
          ),
      );
      c.drawRect(
        const Rect.fromLTWH(7, 46, 18, 5),
        Paint()..color = const Color(0xffb4b6be),
      );
    } else if (family == 'highlighter') {
      c.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(8, 24, 16, 20),
          const Radius.circular(5),
        ),
        ink..color = Color(color).withValues(alpha: .7),
      );
      c.drawPath(
        Path()
          ..moveTo(10, 24)
          ..lineTo(11, 15)
          ..lineTo(21, 12)
          ..lineTo(22, 24)
          ..close(),
        ink..color = Color(color),
      );
      c.drawRect(const Rect.fromLTWH(7, 65, 18, 10), ink);
    } else if (family == 'pencil') {
      // A faceted wooden pencil stays distinct even at the narrow dock size.
      c.drawRect(
        const Rect.fromLTWH(5, 37, 22, 60),
        Paint()..color = const Color(0xffe5aa31),
      );
      c.drawRect(
        const Rect.fromLTWH(11, 37, 10, 60),
        Paint()..color = const Color(0xffffcf65),
      );
      c.drawPath(
        Path()
          ..moveTo(16, 5)
          ..lineTo(27, 39)
          ..lineTo(20, 35)
          ..lineTo(12, 40)
          ..lineTo(5, 39)
          ..close(),
        Paint()..color = const Color(0xffdcb897),
      );
      c.drawPath(
        Path()
          ..moveTo(16, 5)
          ..lineTo(19, 19)
          ..lineTo(13, 19)
          ..close(),
        Paint()..color = const Color(0xff292d35),
      );
      c.drawRect(const Rect.fromLTWH(5, 72, 22, 9), ink);
    } else if (family == 'fountain') {
      c.drawRRect(barrel, ink);
      c.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(10, 50, 3, 40),
          const Radius.circular(1.5),
        ),
        Paint()..color = Colors.white38,
      );
      final gold = Paint()
        ..shader = ui.Gradient.linear(
          const Offset(3, 0),
          const Offset(29, 0),
          [
            const Color(0xffb68230),
            const Color(0xffffe7a0),
            const Color(0xffc19543),
          ],
          [0, .5, 1],
        );
      c.drawPath(
        Path()
          ..moveTo(16, 3)
          ..lineTo(29, 28)
          ..lineTo(22, 47)
          ..lineTo(10, 47)
          ..lineTo(3, 28)
          ..close(),
        gold,
      );
      c.drawLine(
        const Offset(16, 5),
        const Offset(16, 35),
        Paint()
          ..color = const Color(0xff343942)
          ..strokeWidth = 1.8,
      );
      c.drawCircle(
        const Offset(16, 29),
        2.7,
        Paint()..color = const Color(0xff343942),
      );
      c.drawRect(const Rect.fromLTWH(7, 47, 18, 5), gold);
      c.drawRect(const Rect.fromLTWH(7, 84, 18, 3), gold);
    } else if (family == 'lasso') {
      c.drawPath(
        Path()
          ..moveTo(16, 9)
          ..lineTo(23, 39)
          ..lineTo(9, 39)
          ..close(),
        Paint()..color = const Color(0xff454a53),
      );
      for (var y = 20.0; y < 40; y += 5)
        c.drawLine(
          Offset(10, y + 4),
          Offset(22, y),
          Paint()
            ..color = Colors.white70
            ..strokeWidth = 2,
        );
      c.drawOval(
        const Rect.fromLTWH(12, 54, 10, 15),
        Paint()
          ..color = const Color(0xff666b73)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    } else {
      c.drawPath(
        Path()
          ..moveTo(16, family == 'brush' ? 7 : 13)
          ..quadraticBezierTo(20, 28, 21, 43)
          ..lineTo(11, 43)
          ..quadraticBezierTo(12, 26, 16, family == 'brush' ? 7 : 13)
          ..close(),
        ink,
      );
      c.drawRect(const Rect.fromLTWH(7, 72, 18, 7), ink);
    }
    c.restore();
  }

  @override
  bool shouldRepaint(_PalettePenPainter old) =>
      old.color != color || old.family != family;
}
