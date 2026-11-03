part of 'study_canvas.dart';

const _brushNames = {
  'ballpoint': '圆珠笔',
  'fountain': '钢笔',
  'pencil': '铅笔',
  'brush': '软笔',
  'highlighter': '荧光笔',
};
const _penPalette = [
  0xff26354a,
  0xff000000,
  0xff566473,
  0xff9aa4b0,
  0xffe65365,
  0xffb72c45,
  0xffea7b3c,
  0xffffb449,
  0xffffd34f,
  0xffe4e99a,
  0xffb1d75c,
  0xff3ba97e,
  0xff2d8986,
  0xff43c9d7,
  0xff2382ce,
  0xff3c5bb3,
  0xff6254d7,
  0xff9a68ce,
  0xffc964b3,
  0xfff2a7ca,
  0xffb38e72,
  0xff7d5f4c,
  0xffffffff,
  0xffcbd4e4,
];

extension _StudyBrushUI on StudyCanvasState {
  Future<void> _loadBrushSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('study.brush-presets.v1');
      if (!mounted || raw == null || raw.length > 32000) return;
      final data = jsonDecode(raw) as Map;
      final values = [
        for (final p in (data['presets'] as List).take(20))
          StudyPenPreset.fromJson(p as Map),
      ];
      if (values.isEmpty) return;
      for (final pen in values) {
        if (_brushNames.values.contains(pen.name)) {
          pen.name = _brushNames[pen.brush.family]!;
        }
      }
      _update(() {
        _presets = values;
        _presetIndex = ((data['selected'] as num? ?? 0).toInt()).clamp(
          0,
          values.length - 1,
        );
        _eraserSize = ((data['eraser_size'] as num? ?? 18).toDouble()).clamp(
          3,
          100,
        );
        _pressureEraser = data['pressure_eraser'] != false;
        _predictionEnabled = data['prediction'] != false;
        _penButtons = data['pen_buttons'] != false;
        _pressureThreshold =
            ((data['pressure_threshold'] as num? ?? .8).toDouble()).clamp(
              .55,
              .98,
            );
        _eraserMode =
            const {'partial', 'stroke', 'lasso'}.contains(data['eraser_mode'])
            ? '${data['eraser_mode']}'
            : 'partial';
        final pen = _presets[_presetIndex];
        _brush = pen.brush;
        _color = pen.color;
        _penWidth = pen.width;
      });
      unawaited(_configureStylus());
    } catch (_) {
      /* Invalid optional preferences do not prevent opening the canvas. */
    }
  }

  Future<void> _saveBrushSettings() async {
    final p = _presets[_presetIndex];
    if (_brushNames.values.contains(p.name)) {
      p.name = _brushNames[_brush.family]!;
    }
    p
      ..color = _color
      ..width = _penWidth
      ..brush = _brush;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'study.brush-presets.v1',
        jsonEncode({
          'presets': _presets.map((p) => p.json()).toList(),
          'selected': _presetIndex,
          'eraser_size': _eraserSize,
          'eraser_mode': _eraserMode,
          'pressure_eraser': _pressureEraser,
          'prediction': _predictionEnabled,
          'pen_buttons': _penButtons,
          'pressure_threshold': _pressureThreshold,
        }),
      );
    } catch (_) {
      if (mounted) _toast('画笔偏好暂未保存；画布与笔迹仍可正常保存');
    }
  }

  void _pickPen(int index) {
    _update(() {
      _selectionReady = false;
      _eraserCursor = null;
      _cursor.value++;
      _presetIndex = index;
      final p = _presets[index];
      _color = p.color;
      _penWidth = p.width;
      _brush = p.brush;
      _tool = p.brush.family == 'highlighter'
          ? StudyTool.highlighter
          : StudyTool.pen;
    });
    unawaited(_saveBrushSettings());
  }

  void _chooseTool(StudyTool tool) {
    if (_tool == tool &&
        (tool == StudyTool.pen ||
            tool == StudyTool.highlighter ||
            tool == StudyTool.eraser)) {
      _penSettings(eraser: tool == StudyTool.eraser);
      return;
    }
    _eraserCursor = null;
    _selectionReady = false;
    _cursor.value++;
    if (tool == StudyTool.pen || tool == StudyTool.highlighter) {
      final index = _presets.indexWhere(
        (p) =>
            (p.brush.family == 'highlighter') ==
            (tool == StudyTool.highlighter),
      );
      if (index >= 0) {
        _pickPen(index);
        return;
      }
    }
    _update(() => _tool = tool);
  }

  void _quickPen({int? color, double? width}) {
    // Color and width controls resume the selected pen, including after erasing.
    _pickPen(_presetIndex);
    _update(() {
      if (color != null) _color = color;
      if (width != null) _penWidth = width;
    });
    unawaited(_saveBrushSettings());
  }

  Future<void> _advancedPenSettings({bool eraser = false, int tab = 0}) async {
    final hex = TextEditingController(
      text: (_color & 0xffffff).toRadixString(16).padLeft(6, '0').toUpperCase(),
    );
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .08),
      builder: (context) => Dialog(
        alignment: _penPlacement.alignment,
        insetPadding: EdgeInsets.only(
          left: _penPlacement.edge == StudyDockEdge.left ? 76 : 12,
          right: _penPlacement.edge == StudyDockEdge.right ? 76 : 12,
          top: _penPlacement.edge == StudyDockEdge.top ? 76 : 24,
          bottom: _penPlacement.edge == StudyDockEdge.bottom ? 76 : 24,
        ),
        child: SizedBox(
          width: math.min(400, MediaQuery.sizeOf(context).width - 100),
          child: StatefulBuilder(
            builder: (context, refresh) {
              void change(VoidCallback f) {
                _update(f);
                refresh(() {});
                unawaited(_saveBrushSettings());
              }

              Widget slider(
                String title,
                double value,
                double min,
                double max,
                ValueChanged<double> set,
              ) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$title · ${value.toStringAsFixed(title == '笔刷粗细' ? 1 : 2)}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Slider(
                    value: value.clamp(min, max),
                    min: min,
                    max: max,
                    onChanged: (v) => change(() => set(v)),
                  ),
                ],
              );
              return SizedBox(
                height: math.min(620, MediaQuery.sizeOf(context).height - 48),
                child: DefaultTabController(
                  length: 4,
                  initialIndex: eraser ? 3 : tab,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Row(
                          children: [
                            const Text(
                              '笔盒',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Spacer(),
                            TextButton.icon(
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
                              icon: const Icon(Icons.add, size: 16),
                              label: Text('收藏 ${_presets.length}/20'),
                            ),
                            IconButton(
                              tooltip: '删除当前收藏',
                              onPressed: _presets.length <= 1
                                  ? null
                                  : () => change(() {
                                      _presets.removeAt(_presetIndex);
                                      _presetIndex = 0;
                                      final p = _presets.first;
                                      _color = p.color;
                                      _penWidth = p.width;
                                      _brush = p.brush;
                                    }),
                              icon: const Icon(Icons.delete_outline, size: 19),
                            ),
                          ],
                        ),
                      ),
                      const TabBar(
                        tabs: [
                          Tab(text: '笔刷'),
                          Tab(text: '颜色'),
                          Tab(text: '粗细'),
                          Tab(text: '橡皮'),
                        ],
                      ),
                      SizedBox(
                        height: 100,
                        child: CustomPaint(
                          painter: _BrushPreview(
                            _color,
                            _penWidth,
                            _brush,
                            chrome,
                          ),
                          child: Center(
                            child: Align(
                              alignment: Alignment.bottomRight,
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Text(
                                  '实时笔迹预览',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            SingleChildScrollView(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      for (final entry in _brushNames.entries)
                                        ChoiceChip(
                                          selected: _brush.family == entry.key,
                                          label: Text(entry.value),
                                          onSelected: (_) => change(() {
                                            _brush = _brush.copyWith(
                                              family: entry.key,
                                              opacity:
                                                  entry.key == 'highlighter'
                                                  ? 0.35
                                                  : 1,
                                            );
                                            _tool = entry.key == 'highlighter'
                                                ? StudyTool.highlighter
                                                : StudyTool.pen;
                                          }),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 20),
                                  SwitchListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text('一笔成形'),
                                    subtitle: const Text('画完停住约 0.7 秒；继续按住可调整'),
                                    value: _presets[_presetIndex].shapeAssist,
                                    onChanged: (v) => change(
                                      () => _presets[_presetIndex].shapeAssist =
                                          v,
                                    ),
                                  ),
                                  slider(
                                    '不透明度',
                                    _brush.opacity,
                                    .05,
                                    1,
                                    (v) => _brush = _brush.copyWith(opacity: v),
                                  ),
                                  slider(
                                    '压感响应',
                                    _brush.pressure,
                                    0,
                                    1,
                                    (v) =>
                                        _brush = _brush.copyWith(pressure: v),
                                  ),
                                  slider(
                                    '平滑程度',
                                    _brush.smoothing,
                                    0,
                                    1,
                                    (v) =>
                                        _brush = _brush.copyWith(smoothing: v),
                                  ),
                                  if (_brush.family == 'highlighter')
                                    SegmentedButton<bool>(
                                      segments: const [
                                        ButtonSegment(
                                          value: false,
                                          label: Text('圆头'),
                                        ),
                                        ButtonSegment(
                                          value: true,
                                          label: Text('平头'),
                                        ),
                                      ],
                                      selected: {_brush.squareTip},
                                      onSelectionChanged: (s) => change(
                                        () => _brush = _brush.copyWith(
                                          squareTip: s.first,
                                        ),
                                      ),
                                    ),
                                  const SizedBox(height: 12),
                                  Text(
                                    '圆珠笔与荧光笔保持均匀宽度；钢笔、铅笔与软笔响应压力。鼠标使用固定压力。',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SingleChildScrollView(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                children: [
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 12,
                                    children: [
                                      for (final color in _penPalette)
                                        InkWell(
                                          onTap: () => change(() {
                                            _color = color;
                                            hex.text = (color & 0xffffff)
                                                .toRadixString(16)
                                                .padLeft(6, '0')
                                                .toUpperCase();
                                          }),
                                          child: Container(
                                            width: 38,
                                            height: 38,
                                            decoration: BoxDecoration(
                                              color: Color(color),
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                width: _color == color ? 3 : 1,
                                                color: _color == color
                                                    ? chrome.accent
                                                    : chrome.line,
                                              ),
                                            ),
                                            child: _color == color
                                                ? Icon(
                                                    Icons.check,
                                                    size: 18,
                                                    color:
                                                        Color(
                                                              color,
                                                            ).computeLuminance() >
                                                            .5
                                                        ? Colors.black
                                                        : Colors.white,
                                                  )
                                                : null,
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 24),
                                  TextField(
                                    controller: hex,
                                    maxLength: 6,
                                    decoration: const InputDecoration(
                                      prefixText: '#',
                                      labelText: '自定义 HEX 颜色',
                                    ),
                                    onChanged: (v) {
                                      if (RegExp(r'^[0-9a-fA-F]{6}$')
                                          .hasMatch(v))
                                        change(
                                          () => _color =
                                              0xff000000 |
                                              int.parse(v, radix: 16),
                                        );
                                    },
                                  ),
                                ],
                              ),
                            ),
                            SingleChildScrollView(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      for (final width in [
                                        1.0,
                                        2.0,
                                        3.0,
                                        5.0,
                                        8.0,
                                        12.0,
                                        20.0,
                                        32.0,
                                      ])
                                        ChoiceChip(
                                          selected:
                                              (_penWidth - width).abs() < .05,
                                          label: Text('${width.toInt()}'),
                                          onSelected: (_) =>
                                              change(() => _penWidth = width),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 24),
                                  slider(
                                    '笔刷粗细',
                                    _penWidth,
                                    .2,
                                    80,
                                    (v) => _penWidth = v,
                                  ),
                                  Text(
                                    '宽度使用画布坐标；缩放画布时已有笔迹保持比例。',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SingleChildScrollView(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SegmentedButton<String>(
                                    segments: const [
                                      ButtonSegment(
                                        value: 'partial',
                                        label: Text('局部擦除'),
                                      ),
                                      ButtonSegment(
                                        value: 'stroke',
                                        label: Text('整笔擦除'),
                                      ),
                                      ButtonSegment(
                                        value: 'lasso',
                                        label: Text('圈选整笔'),
                                      ),
                                    ],
                                    selected: {_eraserMode},
                                    onSelectionChanged: (s) => change(() {
                                      _eraserMode = s.first;
                                      _tool = StudyTool.eraser;
                                    }),
                                  ),
                                  const SizedBox(height: 16),
                                  SwitchListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text('压感橡皮'),
                                    subtitle: const Text(
                                      '落笔时原地重压停留，临时擦除；画出笔迹后停留用于成形',
                                    ),
                                    value: _pressureEraser,
                                    onChanged: (v) =>
                                        change(() => _pressureEraser = v),
                                  ),
                                  if (_pressureEraser)
                                    slider(
                                      '触发压力（越小越灵敏）',
                                      _pressureThreshold,
                                      .55,
                                      .98,
                                      (v) => _pressureThreshold = v,
                                    ),
                                  const SizedBox(height: 16),
                                  slider(
                                    '橡皮半径',
                                    _eraserSize,
                                    3,
                                    100,
                                    (v) => _eraserSize = v,
                                  ),
                                  Text(
                                    '整笔模式会移除同一次落笔的全部分段；圈选模式在抬笔后擦除圈内笔画。锁定或隐藏图层保持不变。',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    Future.delayed(const Duration(milliseconds: 400), hex.dispose);
  }
}

class _BrushPreview extends CustomPainter {
  _BrushPreview(this.color, this.width, this.brush, this.chrome);
  final int color;
  final double width;
  final StudyBrush brush;
  final StudyChrome chrome;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, Paint()..color = chrome.surfaceSoft);
    final points = [
      for (var i = 0; i < 100; i++)
        InkPoint(
          Offset(
            24 + (size.width - 48) * i / 99,
            size.height / 2 + math.sin(i / 99 * math.pi * 3) * 22,
          ),
          .1 + .9 * math.sin(i / 99 * math.pi),
        ),
    ];
    paintInk(
      canvas,
      points,
      color,
      width,
      brush.family == 'highlighter' ? 'highlighter' : 'pen',
      brush: brush,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BrushPreview old) => true;
}
