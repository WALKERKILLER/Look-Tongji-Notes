part of 'study_canvas.dart';

Rect _normalizeRegion(Rect r, Rect parent) => Rect.fromLTWH(
  ((r.left - parent.left) / parent.width).clamp(0, 1),
  ((r.top - parent.top) / parent.height).clamp(0, 1),
  (r.width / parent.width).clamp(.000001, 1),
  (r.height / parent.height).clamp(.000001, 1),
);

Rect _sourceBounds(StudyCard card) {
  if (card.type != 'pdfdoc') return card.rect;
  final area = Rect.fromLTWH(
    card.rect.left,
    card.rect.top + 36,
    card.rect.width,
    math.max(1, card.rect.height - 88),
  );
  var width = area.width, height = width / card.pageAspect;
  if (height > area.height) {
    height = area.height;
    width = height * card.pageAspect;
  }
  return Rect.fromCenter(center: area.center, width: width, height: height);
}

extension _StudyAgentUI on StudyCanvasState {
  Future<List<Map<String, dynamic>>> _captureSelection() async {
    final d = document!;
    if (_regionSelection == null) return [];
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return [];
    final boundary =
        _capture.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) throw const FormatException('所选区域尚未显示，请移动到视口内重试');
    final world = _regionSelection!,
        r = Rect.fromLTWH(
          world.left * d.zoom + d.camera.dx,
          world.top * d.zoom + d.camera.dy,
          world.width * d.zoom,
          world.height * d.zoom,
        ).intersect(Offset.zero & boundary.size);
    if (r.isEmpty || r.width < 2 || r.height < 2)
      throw const FormatException('所选区域不在当前视口内，请先定位到该区域');
    // Cropping is performed locally; only the reviewed region leaves the renderer.
    final full = await boundary.toImage(pixelRatio: 1);
    Uint8List? bytes;
    try {
      for (final edge in [720.0, 480.0, 320.0]) {
        final scale = math.min(1.0, edge / math.max(r.width, r.height));
        final w = math.max(1, (r.width * scale).round()),
            h = math.max(1, (r.height * scale).round());
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawColor(Colors.white, BlendMode.src);
        canvas.drawImageRect(
          full,
          r,
          Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
          Paint()..filterQuality = FilterQuality.medium,
        );
        final picture = recorder.endRecording();
        final cropped = await picture.toImage(w, h);
        try {
          final data = await cropped.toByteData(format: ui.ImageByteFormat.png);
          bytes = data?.buffer.asUint8List();
        } finally {
          cropped.dispose();
          picture.dispose();
        }
        if (bytes != null && bytes.length <= 450000) break;
      }
    } finally {
      full.dispose();
    }
    if (bytes == null || bytes.length > 450000)
      throw const FormatException('选区图像过大，请缩小后重试');
    final ids = <String>[];
    if (_detail.strokeIds.isNotEmpty) ids.add('selected-ink');
    if (_detail.objectId?.isNotEmpty == true)
      ids.add('object-${_detail.objectId}');
    if (ids.isEmpty) throw const FormatException('请选中笔迹或单个 PDF/图片区域后再使用视觉理解');
    return [
      for (final id in ids.take(2))
        {
          'source_id': id,
          'mime_type': 'image/png',
          'data': base64Encode(bytes),
        },
    ];
  }

  Future<void> _documentSelection(StudyCard card) async {
    TextSelection selection = const TextSelection.collapsed(offset: 0);
    final chosen = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('${card.title} · 原文选区'),
        content: SizedBox(
          width: 650,
          height: 360,
          child: SingleChildScrollView(
            child: card.text.isEmpty
                ? const Text('此页没有可提取文字。请使用区域选择，再通过支持图像的模型理解扫描件或公式。')
                : SelectableText(
                    card.text,
                    onSelectionChanged: (s, cause) => selection = s,
                  ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('取消'),
          ),
          if (card.text.isEmpty)
            FilledButton(
              onPressed: () {
                _update(() => _tool = StudyTool.region);
                Navigator.pop(c, false);
              },
              child: const Text('选择视觉区域'),
            )
          else
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('围绕所选文字问 AI'),
            ),
        ],
      ),
    );
    if (!mounted || chosen != true) return;
    if (selection.isCollapsed || selection.start < 0) {
      _toast('请先在原文中拖选要提问的文字');
      return;
    }
    _detail.clear();
    _detail
      ..objectId = card.id
      ..start = selection.start
      ..end = selection.end;
    _selection
      ..clear()
      ..add(card.id);
    _regionSelection = null;
    await _openConversation();
  }

  Future<void> _focusSource(StudyAnchor a) async {
    if (a.workspaceId.isNotEmpty && a.workspaceId != widget.ctl.lectureId) {
      _toast('此来源属于其他课次，请先打开对应课程');
      return;
    }
    final d = document!;
    final card = d.cards.where((c) => c.id == a.objectId).firstOrNull;
    if (card != null &&
        card.type == 'pdfdoc' &&
        a.page > 0 &&
        card.page != a.page) {
      try {
        final page = await widget.api.studyPDFPage(
          widget.ctl.lectureId,
          card.source,
          a.page,
        );
        if (!mounted) return;
        d.checkpoint();
        card
          ..pageAspect = (page['width'] as num) / (page['height'] as num)
          ..page = a.page
          ..path = '${page['file']}'
          ..text = '${page['text']}'
          ..textBoxes = (page['boxes'] as List? ?? []).cast<Map>();
        d.changed();
      } catch (e) {
        _toast('无法定位文档页：$e');
        return;
      }
    }
    if (card?.collapsed == true) {
      d.checkpoint();
      card!.collapsed = false;
      card.rect = Rect.fromLTWH(
        card.rect.left,
        card.rect.top,
        card.rect.width,
        math.max(240, card.expandedH),
      );
      d.changed();
    }
    Rect? target = card?.rect;
    if (a.kind == 'video' && a.objectId == 'lecture')
      widget.ctl.seekTo(a.timeStartMs);
    else if (a.kind == 'video' && card != null) {
      _localVideoTimes[card.id] = a.timeStartMs;
      final local = _localVideoKeys[card.id]?.currentState;
      if (local != null)
        unawaited(local.player.seek(Duration(milliseconds: a.timeStartMs)));
    } else if (a.kind == 'ink') {
      final ink = d.strokes.where((s) => a.strokeIds.contains(s.id)).toList();
      if (ink.length != a.strokeIds.length) {
        _toast('原笔迹已被修改或擦除，此来源已过期');
        return;
      }
      if (ink.isNotEmpty)
        target = ink
            .map((s) => s.bounds)
            .reduce((r, s) => r.expandToInclude(s));
    } else if (card != null &&
        a.quote.isNotEmpty &&
        (a.start + a.quote.length > card.contentText.length ||
            card.contentText.substring(a.start, a.start + a.quote.length) !=
                a.quote)) {
      _toast('原文选区已被编辑，此引用已过期');
      return;
    }
    if (target == null || card != null && !d.visible(card.layer)) {
      _toast('来源对象已移除或图层已隐藏');
      return;
    }
    if (card != null && a.region != null) {
      final r = a.region!;
      target = Rect.fromLTWH(
        _sourceBounds(card).left + r.left * _sourceBounds(card).width,
        _sourceBounds(card).top + r.top * _sourceBounds(card).height,
        r.width * _sourceBounds(card).width,
        r.height * _sourceBounds(card).height,
      );
    }
    d.zoom = math
        .min(
          (_viewport.width - 100) / math.max(100, target.width),
          (_viewport.height - 100) / math.max(100, target.height),
        )
        .clamp(.05, 2);
    d.camera = _viewport.center(Offset.zero) - target.center * d.zoom;
    _selection
      ..clear()
      ..addAll(card == null ? <String>[] : [card.id]);
    _sourceHighlight = target;
    _regionSelection = null;
    _cameraChanged();
    if (a.end > a.start && card != null && a.kind != 'ink') {
      final raw = card.contentText;
      if (a.end <= raw.length)
        _toast(
          '来源原文：${raw.substring(a.start, a.end).substring(0, math.min(160, a.end - a.start))}',
        );
    }
  }

  Future<void> _editKnowledge(StudyCard original) async {
    final card = original.copy();
    final title = TextEditingController(text: card.title);
    final controls = <TextEditingController>[];
    final saved = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('编辑知识卡片'),
        content: SizedBox(
          width: 650,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  maxLength: 240,
                  decoration: const InputDecoration(labelText: '标题'),
                ),
                for (final b in card.blocks)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Builder(
                      builder: (_) {
                        final value = b.type == 'table'
                            ? [
                                b.columns,
                                ...b.rows,
                              ].map((r) => r.join('\t')).join('\n')
                            : b.type == 'list' || b.type == 'steps'
                            ? b.items.join('\n')
                            : b.text;
                        final ctl = TextEditingController(text: value);
                        controls.add(ctl);
                        return Column(
                          children: [
                            TextField(
                              controller: ctl,
                              minLines: 2,
                              maxLines: 9,
                              maxLength: 12000,
                              decoration: InputDecoration(
                                labelText: b.type == 'table'
                                    ? '表格：首行为列名，列用 Tab 分隔'
                                    : b.type == 'list' || b.type == 'steps'
                                    ? '每行一项'
                                    : b.type,
                              ),
                              onChanged: (v) {
                                if (b.type == 'table') {
                                  final rows = v
                                      .split('\n')
                                      .map((s) => s.split('\t'))
                                      .toList();
                                  b.columns = rows.first;
                                  b.rows = rows.skip(1).toList();
                                } else if (b.type == 'list' ||
                                    b.type == 'steps') {
                                  b.items = v.split('\n');
                                } else {
                                  b.text = v;
                                }
                              },
                            ),
                            if (b.type == 'exercise') ...[
                              TextFormField(
                                initialValue: b.hint,
                                decoration: const InputDecoration(
                                  labelText: '提示',
                                ),
                                onChanged: (v) => b.hint = v,
                              ),
                              TextFormField(
                                initialValue: b.answer,
                                minLines: 2,
                                maxLines: 5,
                                decoration: const InputDecoration(
                                  labelText: '答案与解析',
                                ),
                                onChanged: (v) => b.answer = v,
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    Future.delayed(const Duration(milliseconds: 400), () {
      title.dispose();
      for (final ctl in controls) ctl.dispose();
    });
    if (!mounted || saved != true) return;
    final d = document!;
    if (!d.editable(original.layer)) {
      _toast('该图层不可编辑');
      return;
    }
    if (card.blocks.any(
      (b) =>
          b.type == 'table' &&
          (b.columns.isEmpty ||
              b.columns.length > 8 ||
              b.rows.any((r) => r.length != b.columns.length)),
    )) {
      _toast('表格各行的列数须相同');
      return;
    }
    d.checkpoint();
    original
      ..title = title.text
      ..blocks = card.blocks;
    d.changed();
  }

  Future<void> _connectionSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, refresh) => SizedBox(
          height: 420,
          child: Column(
            children: [
              const ListTile(
                title: Text('知识关联'),
                subtitle: Text('关系随对象移动；更改与删除都可撤销。'),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: document!.connections.length,
                  itemBuilder: (c, i) {
                    final link = document!.connections[i];
                    final a = document!.cards
                            .where((v) => v.id == link.from)
                            .firstOrNull,
                        b = document!.cards
                            .where((v) => v.id == link.to)
                            .firstOrNull;
                    final editable =
                        a != null &&
                        b != null &&
                        document!.editable(a.layer) &&
                        document!.editable(b.layer);
                    return ListTile(
                      title: Text(
                        '${a?.title ?? link.from} → ${b?.title ?? link.to}',
                      ),
                      subtitle: Text(link.label),
                      onTap: editable
                          ? () async {
                              final input = TextEditingController(
                                text: link.label,
                              );
                              final label = await showDialog<String>(
                                context: c,
                                builder: (d) => AlertDialog(
                                  title: const Text('关系说明'),
                                  content: TextField(
                                    controller: input,
                                    maxLength: 240,
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(d),
                                      child: const Text('取消'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.pop(d, input.text),
                                      child: const Text('保存'),
                                    ),
                                  ],
                                ),
                              );
                              Future.delayed(
                                const Duration(milliseconds: 400),
                                input.dispose,
                              );
                              if (!mounted || label == null) return;
                              document!.checkpoint();
                              link.label = label;
                              document!.changed();
                              if (c.mounted) refresh(() {});
                            }
                          : null,
                      trailing: IconButton(
                        tooltip: '移除关联',
                        onPressed: editable
                            ? () {
                                document!.checkpoint();
                                document!.connections.remove(link);
                                document!.changed();
                                refresh(() {});
                              }
                            : null,
                        icon: const Icon(Icons.link_off),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectionPainter extends CustomPainter {
  _ConnectionPainter(this.document, this.stage, Listenable repaint)
    : super(repaint: repaint);
  final StudyDocument document;
  final Rect stage;
  @override
  void paint(Canvas canvas, Size size) {
    final d = document, objects = {for (final c in document.cards) c.id: c};
    canvas.save();
    canvas.translate(-stage.left, -stage.top);
    final viewport = stage;
    Offset edge(Rect r, Offset toward) {
      final delta = toward - r.center;
      final scale = math.min(
        delta.dx.abs() < .001 ? double.infinity : r.width / 2 / delta.dx.abs(),
        delta.dy.abs() < .001 ? double.infinity : r.height / 2 / delta.dy.abs(),
      );
      return scale.isFinite ? r.center + delta * scale : r.center;
    }

    for (final link in d.connections) {
      final a = objects[link.from], b = objects[link.to];
      if (a == null || b == null || !d.visible(a.layer) || !d.visible(b.layer))
        continue;
      if (!Rect.fromPoints(
        a.rect.center,
        b.rect.center,
      ).inflate(60).overlaps(viewport))
        continue;
      final start = edge(a.rect, b.rect.center),
          end = edge(b.rect, a.rect.center),
          mid = (start + end) / 2;
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(mid.dx, start.dy, mid.dx, end.dy, end.dx, end.dy);
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xff9d91cb)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 / d.zoom,
      );
      canvas.drawCircle(
        end,
        4 / d.zoom,
        Paint()..color = const Color(0xff8170b8),
      );
      final label = TextPainter(
        text: TextSpan(
          text: link.label,
          style: TextStyle(
            color: const Color(0xff61518a),
            fontSize: 12 / d.zoom,
            backgroundColor: const Color(0xfff6f3ff),
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 2,
      )..layout(maxWidth: 180 / d.zoom);
      label.paint(canvas, mid - Offset(label.width / 2, label.height / 2));
      label.dispose();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ConnectionPainter old) => true;
  @override
  bool shouldRebuildSemantics(_ConnectionPainter old) => false;
}

class _KnowledgeBody extends StatelessWidget {
  const _KnowledgeBody({
    required this.card,
    required this.onSource,
    required this.onBeginAnswer,
    required this.onAnswer,
    required this.editable,
  });
  final StudyCard card;
  final ValueChanged<StudyAnchor> onSource;
  final VoidCallback onBeginAnswer;
  final void Function(int, String) onAnswer;
  final bool editable;
  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final b in card.blocks)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: switch (b.type) {
                'heading' => SelectableText(
                  b.text,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: Color(0xff25344a),
                  ),
                ),
                'list' || 'steps' => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < b.items.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: SelectableText(
                          '${b.type == 'steps' ? '${i + 1}.' : '•'} ${b.items[i]}',
                        ),
                      ),
                  ],
                ),
                'table' => SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: [
                      for (final c in b.columns) DataColumn(label: Text(c)),
                    ],
                    rows: [
                      for (final r in b.rows)
                        DataRow(
                          cells: [
                            for (final v in r) DataCell(SelectableText(v)),
                          ],
                        ),
                    ],
                  ),
                ),
                'code' => Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  color: const Color(0xffedf0f6),
                  child: SelectableText(
                    '${b.language}\n${b.text}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                  ),
                ),
                'math' => SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Math.tex(
                    b.text,
                    onError: (_, _) => SelectableText(b.text),
                  ),
                ),
                'exercise' => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      b.text,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    _StudyAnswer(
                      key: ValueKey(
                        '${card.id}/answer/${card.blocks.indexOf(b)}',
                      ),
                      value: card.responses['${card.blocks.indexOf(b)}'] ?? '',
                      enabled: editable,
                      onBegin: onBeginAnswer,
                      onChanged: (v) => onAnswer(card.blocks.indexOf(b), v),
                    ),
                    if (b.hint.isNotEmpty)
                      ExpansionTile(
                        title: const Text('提示'),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: SelectableText(b.hint),
                          ),
                        ],
                      ),
                    if (b.answer.isNotEmpty)
                      ExpansionTile(
                        title: const Text('答案与解析'),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: SelectableText(b.answer),
                          ),
                        ],
                      ),
                  ],
                ),
                _ => SelectableText(b.text),
              },
            ),
          const Divider(),
          const Text(
            '引用来源',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          for (final a in card.sources)
            TextButton.icon(
              style: TextButton.styleFrom(alignment: Alignment.centerLeft),
              onPressed: () => onSource(a),
              icon: const Icon(Icons.link, size: 15),
              label: Text(
                a.kind == 'video'
                    ? '视频 · ${(a.timeStartMs / 1000).floor()}–${(a.timeEndMs / 1000).ceil()} 秒'
                    : a.kind == 'ink'
                    ? '手写选区 · ${a.strokeIds.length} 段'
                    : '${a.kind.toUpperCase()}${a.page > 0 ? ' · 第 ${a.page} 页' : ''} · ${a.quote.substring(0, math.min(50, a.quote.length))}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    ),
  );
}

class _StudyAnswer extends StatefulWidget {
  const _StudyAnswer({
    super.key,
    required this.value,
    required this.enabled,
    required this.onBegin,
    required this.onChanged,
  });
  final String value;
  final bool enabled;
  final VoidCallback onBegin;
  final ValueChanged<String> onChanged;
  @override
  State<_StudyAnswer> createState() => _StudyAnswerState();
}

class _StudyAnswerState extends State<_StudyAnswer> {
  late final controller = TextEditingController(text: widget.value);
  final focus = FocusNode();
  @override
  void initState() {
    super.initState();
    focus.addListener(_focusChanged);
  }

  void _focusChanged() {
    if (focus.hasFocus) widget.onBegin();
  }

  @override
  void didUpdateWidget(_StudyAnswer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (controller.text != widget.value) {
      controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    focus.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    focusNode: focus,
    enabled: widget.enabled,
    minLines: 2,
    maxLines: 6,
    maxLength: 4000,
    decoration: const InputDecoration(labelText: '我的作答', helperText: '随工作区保存'),
    onChanged: widget.onChanged,
  );
}
