import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../l10n/l10n.dart';
import 'study_content.dart';
import 'study_brush.dart';
export 'study_content.dart';
export 'study_brush.dart';

String studyId() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${_nextId++}';
int _nextId = 0;
double _n(dynamic v, [double fallback = 0]) =>
    v is num && v.isFinite ? v.toDouble() : fallback;

class StudyLayer {
  StudyLayer(this.id, this.name, {this.visible = true, this.locked = false});
  final String id;
  String name;
  bool visible, locked;
  StudyLayer copy() => StudyLayer(id, name, visible: visible, locked: locked);
  Map<String, dynamic> json() => {
    'id': id,
    'name': name,
    'visible': visible,
    'locked': locked,
  };
}

class StudyCard {
  StudyCard({
    required this.id,
    required this.type,
    required this.layer,
    required this.rect,
    this.title = '',
    this.text = '',
    this.path = '',
    this.source = '',
    this.documentId = '',
    this.page = 0,
    this.pageCount = 0,
    this.pageAspect = .75,
    this.textBoxes = const [],
    this.generation = '',
    this.conversationId = '',
    this.sourceLectureId = '',
    this.originalPath = '',
    this.pdfColumn = '',
    this.collapsed = false,
    this.expandedH = 0,
    List<StudyBlock>? blocks,
    List<StudyAnchor>? sources,
    Map<String, String>? responses,
  }) : responses = responses ?? {},
       blocks = blocks ?? [],
       sources = sources ?? [];
  final String id, type;
  String layer, title, text, path, source;
  Rect rect;
  String documentId, generation, conversationId, sourceLectureId, originalPath;
  String pdfColumn;
  bool collapsed;
  double expandedH;
  int page, pageCount;
  double pageAspect;
  List<Map> textBoxes;
  List<StudyBlock> blocks;
  List<StudyAnchor> sources;
  Map<String, String> responses;
  bool get generated =>
      const {'note', 'explanation', 'knowledge', 'practice'}.contains(type);
  String get contentStamp => jsonEncode({
    "type": type,
    "text": text,
    "path": path,
    "source": source,
    "page": page,
    "blocks": blocks.map((b) => b.json()).toList(),
    "responses": responses,
  });
  String get contentText {
    final value = generated ? blocks.map((b) => b.plainText).join('\n') : text;
    final keys = responses.keys.toList()..sort();
    return responses.isEmpty
        ? value
        : '$value\n用户作答\n${keys.map((k) => '$k: ${responses[k]}').join('\n')}';
  }

  factory StudyCard.fromJson(Map m) => StudyCard(
    id: '${m['id']}',
    type: '${m['type']}',
    layer: '${m['layer']}',
    rect: Rect.fromLTWH(
      _n(m['x']),
      _n(m['y']),
      _n(m['w'], 600),
      _n(m['h'], 440),
    ),
    title: '${m['title'] ?? ''}',
    text: '${m['text'] ?? ''}',
    path: '${m['path'] ?? ''}',
    source: '${m['source'] ?? ''}',
    documentId: '${m['document_id'] ?? m['source'] ?? ''}',
    page: (m['page'] as num? ?? 0).toInt(),
    pageCount: (m['page_count'] as num? ?? 0).toInt(),
    pageAspect: _n(m['page_aspect'], .75),
    textBoxes: (m['text_boxes'] as List? ?? []).cast<Map>(),
    generation: '${m['generation'] ?? ''}',
    conversationId: '${m['conversation_id'] ?? ''}',
    sourceLectureId: '${m['source_lecture_id'] ?? ''}',
    originalPath: '${m['original_path'] ?? ''}',
    pdfColumn: '${m['pdf_column'] ?? ''}',
    collapsed: m['collapsed'] == true,
    expandedH: _n(m['expanded_h']),
    responses: Map<String, String>.from(m['responses'] as Map? ?? {}),
    blocks: [
      for (final b in m['blocks'] as List? ?? []) StudyBlock.fromJson(b as Map),
    ],
    sources: [
      for (final a in m['sources'] as List? ?? [])
        StudyAnchor.fromJson(a as Map),
    ],
  );
  StudyCard copy() => StudyCard.fromJson(json());
  Map<String, dynamic> json() => {
    'id': id,
    'type': type,
    'layer': layer,
    'x': rect.left,
    'y': rect.top,
    'w': rect.width,
    'h': rect.height,
    'title': title,
    'text': text,
    'path': path,
    'source': source,
    'document_id': documentId,
    'page': page,
    'page_count': pageCount,
    'page_aspect': pageAspect,
    'text_boxes': textBoxes,
    'generation': generation,
    'conversation_id': conversationId,
    'source_lecture_id': sourceLectureId,
    'original_path': originalPath,
    if (pdfColumn.isNotEmpty) 'pdf_column': pdfColumn,
    'collapsed': collapsed,
    'expanded_h': expandedH,
    'responses': responses,
    'blocks': blocks.map((b) => b.json()).toList(),
    'sources': sources.map((a) => a.json()).toList(),
  };
}

class InkPoint {
  const InkPoint(this.p, this.pressure);
  final Offset p;
  final double pressure;
  List<double> json() => [p.dx, p.dy, pressure];
}

class StudyStroke {
  StudyStroke({
    required this.id,
    required this.layer,
    required this.points,
    required this.color,
    required this.width,
    this.tool = 'pen',
    this.anchor = '',
    this.page = 0,
    String? gesture,
    this.brush,
  }) : gesture = gesture ?? id;
  final String id, layer, tool, anchor, gesture;
  final int page;
  final List<InkPoint> points;
  final int color;
  final double width;
  final StudyBrush? brush;
  late final Rect bounds = points.fold<Rect>(
    Rect.fromCircle(center: points.first.p, radius: width),
    (r, p) => r.expandToInclude(Rect.fromCircle(center: p.p, radius: width)),
  );
  // Pictures are bounded to 64 segments. Long input never regenerates its prefix.
  // CustomPainter's repaint boundary: https://api.flutter.dev/flutter/rendering/CustomPainter-class.html
  Picture? _picture;
  void paint(Canvas canvas) {
    _picture ??= () {
      final recorder = PictureRecorder();
      paintInk(Canvas(recorder), points, color, width, tool, brush: brush);
      return recorder.endRecording();
    }();
    canvas.drawPicture(_picture!);
  }

  Map<String, dynamic> json() => {
    'id': id,
    'layer': layer,
    'anchor': anchor,
    'page': page,
    'gesture': gesture,
    if (brush != null) 'brush': brush!.json(),
    'color': color,
    'width': width,
    'tool': tool,
    'points': points.map((p) => p.json()).toList(),
  };
  factory StudyStroke.fromJson(Map m) => StudyStroke(
    id: '${m['id']}',
    layer: '${m['layer']}',
    anchor: '${m['anchor'] ?? ''}',
    page: (m['page'] as num? ?? 0).toInt(),
    gesture: m['gesture'] as String?,
    brush: m['brush'] is Map ? StudyBrush.fromJson(m['brush'] as Map) : null,
    color: (m['color'] as num).toInt(),
    width: _n(m['width'], 3),
    tool: '${m['tool']}',
    points: [
      for (final p in m['points'] as List)
        InkPoint(Offset(_n(p[0]), _n(p[1])), _n(p[2], .5)),
    ],
  );
}

void paintInk(
  Canvas canvas,
  List<InkPoint> points,
  int color,
  double width,
  String tool, {
  StudyBrush? brush,
}) {
  if (points.isEmpty) return;
  final paint = Paint()
    ..color = Color(color)
        .withValues(alpha: brush?.opacity ?? (tool == 'highlighter' ? .3 : 1))
    ..strokeCap = brush?.squareTip == true ? StrokeCap.square : StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  if (points.length == 1) {
    canvas.drawCircle(points.first.p, width * .5, paint);
    return;
  }
  if (tool == 'highlighter') {
    final path = Path()..moveTo(points.first.p.dx, points.first.p.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.p.dx, point.p.dy);
    }
    canvas.drawPath(
      path,
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = width,
    );
    return;
  }
  for (var i = 1; i < points.length; i++) {
    paint.strokeWidth =
        width *
        (brush != null
            ? brush.radiusScale(
                (points[i].pressure + points[i - 1].pressure) / 2,
              )
            : tool == 'highlighter'
            ? 1
            : .35 + .65 * (points[i].pressure + points[i - 1].pressure) / 2);
    canvas.drawLine(points[i - 1].p, points[i].p, paint);
    if (brush?.family == 'pencil') {
      final delta = points[i].p - points[i - 1].p;
      if (delta.distance > 0) {
        final normal =
            Offset(-delta.dy, delta.dx) /
            delta.distance *
            paint.strokeWidth *
            .22;
        final grain = Paint()
          ..color = Color(color).withValues(alpha: brush!.opacity * .18)
          ..strokeWidth = math.max(.25, width * .08);
        canvas.drawLine(points[i - 1].p + normal, points[i].p + normal, grain);
      }
    }
  }
}

class _StudySnapshot {
  _StudySnapshot(StudyDocument d)
    : appliedRuns = Set.of(d.appliedRuns),
      layers = d.layers.map((a) => a.copy()).toList(),
      cards = d.cards.map((a) => a.copy()).toList(),
      connections = d.connections
          .map((a) => StudyConnection.fromJson(a.json()))
          .toList(),
      strokes = List.of(d.strokes);
  final Set<String> appliedRuns;
  final List<StudyLayer> layers;
  final List<StudyCard> cards;
  final List<StudyStroke> strokes;
  final List<StudyConnection> connections;
}

class StudyDocument extends ChangeNotifier {
  int revision = 0, edit = 0;
  String baseHash = "";
  Set<String> appliedRuns = {};
  Offset camera = const Offset(40, 70);
  double zoom = .75;
  String activeLayer = 'main';
  List<StudyLayer> layers = [StudyLayer('main', l10n.studyDefaultLayer)];
  List<StudyCard> cards = [];
  List<StudyStroke> strokes = [];
  List<StudyConnection> connections = [];
  final _undo = <_StudySnapshot>[], _redo = <_StudySnapshot>[];
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  bool visible(String id) => layers.any((a) => a.id == id && a.visible);
  bool strokeVisible(StudyStroke s) {
    if (!visible(s.layer)) return false;
    final card = cards.where((c) => c.id == s.anchor).firstOrNull;
    return card == null ||
        (!card.collapsed && (s.page == 0 || card.page == s.page));
  }

  bool editable(String id) =>
      layers.any((a) => a.id == id && a.visible && !a.locked);
  bool canTransformCard(StudyCard card) =>
      editable(card.layer) &&
      !strokes.any(
        (s) =>
            s.anchor == card.id &&
            layers.any((l) => l.id == s.layer && l.locked),
      );
  factory StudyDocument.fromJson(Map m) {
    if (m['version'] != 1 && m['version'] != 2 && m['version'] != 3)
      throw FormatException(l10n.studyUnknownVersion);
    final d = StudyDocument();
    d.revision = (m['revision'] as num).toInt();
    d.baseHash = m['base_hash'] as String? ?? '';
    d.appliedRuns = (m['applied_runs'] as List? ?? []).cast<String>().toSet();
    final c = m['camera'] as Map;
    d.camera = Offset(_n(c['x']), _n(c['y']));
    d.zoom = _n(c['z'], 1).clamp(.05, 8);
    d.layers = [
      for (final a in m['layers'] as List)
        StudyLayer(
          '${a['id']}',
          '${a['name']}',
          visible: a['visible'] == true,
          locked: a['locked'] == true,
        ),
    ];
    d.activeLayer = d.layers.first.id;
    d.cards = [
      for (final a in m['objects'] as List) StudyCard.fromJson(a as Map),
    ];
    d.connections = [
      for (final a in m['connections'] as List? ?? [])
        StudyConnection.fromJson(a as Map),
    ];
    // Older files may contain long strokes; normalize their render/erase work into bounded chunks.
    d.strokes = [
      for (final a in m['strokes'] as List)
        ...chunks(StudyStroke.fromJson(a as Map)),
    ];
    return d;
  }
  StudyDocument();
  Map<String, dynamic> json() => {
    'version': 3,
    'revision': revision,
    if (baseHash.isNotEmpty) 'base_hash': baseHash,
    'applied_runs': appliedRuns.toList(),
    'camera': {'x': camera.dx, 'y': camera.dy, 'z': zoom},
    'layers': layers.map((a) => a.json()).toList(),
    'objects': cards.map((a) => a.json()).toList(),
    'strokes': strokes.map((a) => a.json()).toList(),
    'connections': connections.map((a) => a.json()).toList(),
  };
  static List<StudyStroke> chunks(StudyStroke s) {
    if (s.points.length <= 65) return [s];
    return [
      for (var i = 0; i < s.points.length - 1; i += 64)
        StudyStroke(
          id: '${s.id}-$i',
          layer: s.layer,
          points: s.points.sublist(i, math.min(i + 65, s.points.length)),
          color: s.color,
          width: s.width,
          tool: s.tool,
          anchor: s.anchor,
          page: s.page,
          gesture: s.gesture,
          brush: s.brush,
        ),
    ];
  }

  void checkpoint() {
    _undo.add(_StudySnapshot(this));
    if (_undo.length > 40) _undo.removeAt(0);
    _redo.clear();
  }

  void changed() {
    edit++;
    notifyListeners();
  }

  void _restore(_StudySnapshot s) {
    appliedRuns = Set.of(s.appliedRuns);
    layers = s.layers.map((a) => a.copy()).toList();
    cards = s.cards.map((a) => a.copy()).toList();
    strokes = List.of(s.strokes);
    connections = s.connections
        .map((a) => StudyConnection.fromJson(a.json()))
        .toList();
    if (!layers.any((a) => a.id == activeLayer)) activeLayer = layers.first.id;
    changed();
  }

  void undo() {
    if (!canUndo) return;
    _redo.add(_StudySnapshot(this));
    _restore(_undo.removeLast());
  }

  void redo() {
    if (!canRedo) return;
    _undo.add(_StudySnapshot(this));
    _restore(_redo.removeLast());
  }

  void addStroke(StudyStroke s) {
    if (s.points.isEmpty) return;
    checkpoint();
    strokes.addAll(chunks(s));
    changed();
  }

  /// Validate every staged operation before creating one undo entry.
  List<String> applyAgentBatch(
    Map result,
    int expectedEdit,
    Rect viewport, {
    bool allowUpdates = false,
    Map<String, String>? expectedContents,
  }) {
    if (appliedRuns.contains('${result['id']}')) return [];
    if (expectedContents != null) {
      for (final entry in expectedContents.entries) {
        if (entry.key.startsWith('ink/')) {
          final stroke = strokes
              .where((s) => s.id == entry.key.substring(4))
              .firstOrNull;
          if (stroke == null || jsonEncode(stroke.json()) != entry.value)
            throw const FormatException('引用的笔迹已改变，请重新生成');
          continue;
        }
        final card = cards.where((c) => c.id == entry.key).firstOrNull;
        if (card == null || card.contentStamp != entry.value)
          throw const FormatException("引用资料或待修改内容已改变，请重新生成");
      }
    }
    if (expectedContents == null && edit != expectedEdit)
      throw const FormatException('画布在生成期间已改变，请重新生成以免覆盖你的编辑');
    if (!editable(activeLayer)) throw const FormatException('请先选择可编辑图层');
    final ops = result['operations'] as List;
    if (ops.length > 20) throw const FormatException('单次最多 20 个画布操作');
    final anchors = {
      for (final a in result['sources'] as List)
        '${a['id']}': StudyAnchor.fromJson(a as Map),
    };
    final allowedEdits = (result['editable_ids'] as List? ?? [])
        .cast<String>()
        .toSet();
    final next = cards.map((c) => c.copy()).toList();
    final links = connections
        .map((c) => StudyConnection.fromJson(c.json()))
        .toList();
    final created = <String>[];
    List<StudyAnchor> citations(Map op) => [
      for (final id in op['source_ids'] as List? ?? [])
        anchors['$id'] ?? (throw const FormatException('生成物引用了本次没有提供的来源')),
    ];
    List<StudyBlock> blocks(Map op) {
      final values = op['blocks'] as List? ?? [];
      if (values.isEmpty || values.length > 32)
        throw const FormatException('卡片内容结构无效');
      final out = [for (final v in values) StudyBlock.fromJson(v as Map)];
      for (final b in out) {
        if (!const {
              'heading',
              'paragraph',
              'list',
              'steps',
              'table',
              'code',
              'math',
              'exercise',
            }.contains(b.type) ||
            b.plainText.length > 12000 ||
            b.items.length > 30 ||
            b.rows.length > 30 ||
            b.columns.length > 8 ||
            (b.type == 'table' &&
                (b.columns.isEmpty ||
                    b.rows.any((r) => r.length != b.columns.length)))) {
          throw const FormatException('卡片内容超过限制或结构无效');
        }
      }
      return out;
    }

    Rect place() {
      for (var i = 0; i < 150; i++) {
        final p =
            viewport.topLeft +
            Offset(30 + (i % 3) * 560.0, 30 + (i ~/ 3) * 480.0);
        final r = Rect.fromLTWH(p.dx, p.dy, 520, 440);
        if (!next.any(
          (c) => visible(c.layer) && c.rect.inflate(16).overlaps(r),
        ))
          return r;
      }
      throw const FormatException('附近空间不足，请移动到画布空白处重试');
    }

    for (final raw in ops) {
      final op = raw as Map, kind = op['op'];
      if (kind == 'create') {
        final id = '${op['id']}',
            title = '${op['title']}',
            type = '${op['kind']}';
        if (next.any((c) => c.id == id) ||
            !const {
              'note',
              'explanation',
              'knowledge',
              'practice',
            }.contains(type) ||
            title.length > 240)
          throw const FormatException('生成卡片标识或类型无效');
        next.add(
          StudyCard(
            id: id,
            type: type,
            layer: activeLayer,
            rect: place(),
            title: title,
            blocks: blocks(op),
            sources: citations(op),
            generation: '${result['id']}',
          ),
        );
        created.add(id);
      } else if (kind == 'update') {
        if (!allowUpdates) throw const FormatException('修改已有卡片前需要确认预览');
        final c = next.where((c) => c.id == op['object_id']).firstOrNull;
        if (c == null ||
            !c.generated ||
            !editable(c.layer) ||
            !allowedEdits.contains(c.id))
          throw const FormatException('只能修改本次选中的可编辑知识卡片');
        final title = '${op['title']}';
        if (title.length > 240) throw const FormatException('标题过长');
        final cited = citations(op)
            .expand((a) => a.objectId == c.id ? c.sources : [a])
            .toList();
        c
          ..title = title
          ..blocks = blocks(op)
          ..responses = {}
          ..sources = cited;
      } else if (kind == 'connect') {
        final from = '${op['from']}',
            to = '${op['to']}',
            label = '${op['label']}';
        if (from == to ||
            !next.any((c) => c.id == from && editable(c.layer)) ||
            !next.any((c) => c.id == to && editable(c.layer)) ||
            label.length > 240)
          throw const FormatException('关联对象或标签无效');
        links.add(StudyConnection('${op['id']}', from, to, label));
      } else if (kind != 'focus') {
        throw const FormatException('未知画布操作');
      }
    }
    if (next.length > 2000 || links.length > 4000)
      throw const FormatException('画布对象数量超过限制');
    if (ops.any((o) => o['op'] != 'focus')) {
      checkpoint();
      appliedRuns.add('${result['id']}');
      if (appliedRuns.length > 256) appliedRuns.remove(appliedRuns.first);
      cards = next;
      connections = links;
      changed();
    }
    return created;
  }

  void transformCards(Set<String> ids, Rect from, Rect to) {
    final movable = cards
        .where((c) => ids.contains(c.id) && canTransformCard(c))
        .map((c) => c.id)
        .toSet();
    final sx = to.width / from.width, sy = to.height / from.height;
    Offset move(Offset p) => Offset(
      to.left + (p.dx - from.left) * sx,
      to.top + (p.dy - from.top) * sy,
    );
    for (final c in cards.where((a) => movable.contains(a.id))) {
      final tl = move(c.rect.topLeft), br = move(c.rect.bottomRight);
      c.rect = Rect.fromPoints(tl, br);
    }
    strokes = [
      for (final s in strokes)
        if (movable.contains(s.anchor))
          StudyStroke(
            id: s.id,
            layer: s.layer,
            points: [for (final p in s.points) InkPoint(move(p.p), p.pressure)],
            color: s.color,
            width: s.width * math.sqrt(sx * sy),
            tool: s.tool,
            anchor: s.anchor,
            page: s.page,
            gesture: s.gesture,
            brush: s.brush,
          )
        else
          s,
    ];
    changed();
  }

  bool erase(Offset a, Offset b, double radius) {
    final hit = Rect.fromPoints(a, b).inflate(radius);
    var touched = false;
    final next = <StudyStroke>[];
    for (final s in strokes) {
      if (!editable(s.layer) || !strokeVisible(s) || !s.bounds.overlaps(hit)) {
        next.add(s);
        continue;
      }
      final fragments = <List<InkPoint>>[];
      var fragment = <InkPoint>[];
      for (var i = 0; i < s.points.length; i++) {
        final p = s.points[i];
        final erased = _distanceToSegment(p.p, a, b) <= radius + s.width / 2;
        final cross =
            i > 0 &&
            _segmentsNear(s.points[i - 1].p, p.p, a, b, radius + s.width / 2);
        if (erased || cross) {
          if (fragment.isNotEmpty) fragments.add(fragment);
          fragment = [];
          touched = true;
        }
        if (!erased) fragment.add(p);
      }
      if (fragment.isNotEmpty) fragments.add(fragment);
      for (final f in fragments) {
        next.add(
          StudyStroke(
            id: studyId(),
            layer: s.layer,
            points: f,
            color: s.color,
            width: s.width,
            tool: s.tool,
            anchor: s.anchor,
            page: s.page,
            gesture: s.gesture,
            brush: s.brush,
          ),
        );
      }
    }
    if (touched) {
      strokes = next;
      changed();
    }
    return touched;
  }

  bool eraseWhole(Offset a, Offset b, double radius) {
    final hit = Rect.fromPoints(a, b).inflate(radius), gestures = <String>{};
    for (final s in strokes) {
      if (!editable(s.layer) || !strokeVisible(s) || !s.bounds.overlaps(hit))
        continue;
      if (s.points.length == 1 &&
          _distanceToSegment(s.points.first.p, a, b) <= radius + s.width / 2)
        gestures.add(s.gesture);
      for (var i = 1; i < s.points.length; i++) {
        if (_segmentsNear(
          s.points[i - 1].p,
          s.points[i].p,
          a,
          b,
          radius + s.width / 2,
        )) {
          gestures.add(s.gesture);
          break;
        }
      }
    }
    if (gestures.isEmpty) return false;
    strokes.removeWhere(
      (s) => editable(s.layer) && gestures.contains(s.gesture),
    );
    changed();
    return true;
  }

  bool eraseLasso(List<Offset> polygon) {
    if (polygon.length < 3) return false;
    var bounds = Rect.fromPoints(polygon.first, polygon.first);
    for (final p in polygon)
      bounds = bounds.expandToInclude(Rect.fromPoints(p, p));
    bool inside(Offset p) {
      var yes = false;
      for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
        final a = polygon[i], b = polygon[j];
        if ((a.dy > p.dy) != (b.dy > p.dy) &&
            p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx)
          yes = !yes;
      }
      return yes;
    }

    final hit = <String>{};
    for (final s in strokes) {
      if (editable(s.layer) &&
          strokeVisible(s) &&
          s.bounds.overlaps(bounds) &&
          s.points.any((p) => inside(p.p)))
        hit.add(s.gesture);
    }
    if (hit.isEmpty) return false;
    strokes.removeWhere((s) => editable(s.layer) && hit.contains(s.gesture));
    changed();
    return true;
  }

  /// Select whole physical strokes, including sparse segments crossing the loop.
  Set<String> strokesInPolygon(List<Offset> polygon) {
    if (polygon.length < 3) return {};
    var region = Rect.fromPoints(polygon.first, polygon.first);
    for (final p in polygon)
      region = region.expandToInclude(Rect.fromPoints(p, p));
    bool inside(Offset p) {
      var yes = false;
      for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
        final a = polygon[i], b = polygon[j];
        if ((a.dy > p.dy) != (b.dy > p.dy) &&
            p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx)
          yes = !yes;
      }
      return yes;
    }

    final hit = <String>{};
    for (final s in strokes.where(strokeVisible)) {
      if (!s.bounds.overlaps(region)) continue;
      var selected = s.points.any((p) => inside(p.p));
      for (var i = 1; !selected && i < s.points.length; i++) {
        for (var j = 0; j < polygon.length; j++) {
          if (_segmentsNear(
            s.points[i - 1].p,
            s.points[i].p,
            polygon[j],
            polygon[(j + 1) % polygon.length],
            0,
          )) {
            selected = true;
            break;
          }
        }
      }
      if (selected) hit.add(s.gesture);
    }
    return strokes
        .where((s) => strokeVisible(s) && hit.contains(s.gesture))
        .map((s) => s.id)
        .toSet();
  }

  /// Caller owns the gesture checkpoint; source IDs survive edits and undo.
  void transformInk(
    Set<String> ids,
    Rect from,
    Rect to, {
    int? color,
    double? width,
  }) {
    final sx = to.width / math.max(.001, from.width);
    final sy = to.height / math.max(.001, from.height);
    var touched = false;
    strokes = [
      for (final s in strokes)
        if (ids.contains(s.id) && editable(s.layer))
          (() {
            touched = true;
            return StudyStroke(
              id: s.id,
              layer: s.layer,
              anchor: s.anchor,
              page: s.page,
              gesture: s.gesture,
              tool: s.tool,
              brush: s.brush,
              color: color ?? s.color,
              width: (width ?? s.width * math.sqrt(sx * sy)).clamp(.2, 80),
              points: [
                for (final p in s.points)
                  InkPoint(
                    Offset(
                      to.left + (p.p.dx - from.left) * sx,
                      to.top + (p.p.dy - from.top) * sy,
                    ),
                    p.pressure,
                  ),
              ],
            );
          })()
        else
          s,
    ];
    if (touched) changed();
  }

  String contextText(Set<String> ids) {
    final out = StringBuffer('画布材料（文字内容，不含手写识别）：\n');
    for (final c in cards.where(
      (a) => visible(a.layer) && (ids.isEmpty || ids.contains(a.id)),
    )) {
      out.writeln('${c.title}\n${c.text}');
      if (out.length > 12000) break;
    }
    final value = out.toString();
    return value.length <= 12000 ? value : value.substring(0, 12000);
  }
}

double _distanceToSegment(Offset p, Offset a, Offset b) {
  final v = b - a;
  final t = v.distanceSquared == 0
      ? 0.0
      : (((p - a).dx * v.dx + (p - a).dy * v.dy) / v.distanceSquared).clamp(
          0.0,
          1.0,
        );
  return (p - a - v * t).distance;
}

bool _segmentsNear(Offset a, Offset b, Offset c, Offset d, double r) {
  double cross(Offset p, Offset q) => p.dx * q.dy - p.dy * q.dx;
  final v = b - a, w = d - c, denominator = cross(v, w);
  if (denominator.abs() > 1e-8) {
    final t = cross(c - a, w) / denominator, u = cross(c - a, v) / denominator;
    if (t >= 0 && t <= 1 && u >= 0 && u <= 1) return true;
  }
  return math.min(
        math.min(_distanceToSegment(a, c, d), _distanceToSegment(b, c, d)),
        math.min(_distanceToSegment(c, a, b), _distanceToSegment(d, a, b)),
      ) <=
      r;
}
