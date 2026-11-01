// Protocol fixtures verify widgets, not real model inference.
import 'dart:async';
import 'dart:ui' as ui;
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/core/api.dart';
import '../lib/core/models.dart';
import '../lib/features/player/lecture_player.dart';
import '../lib/features/study_canvas/study_canvas.dart';
import '../lib/features/study_canvas/study_document.dart';
import '../lib/features/study_canvas/study_canvas_surface.dart';
import '../lib/theme/prefs.dart';
import '../lib/theme/theme.dart';

class FixtureApi extends Api {
  FixtureApi(this.doc) : super('http://127.0.0.1:9', 'fixture');
  Map<String, dynamic> doc;
  final syncEvents = StreamController<Map<String, dynamic>>.broadcast();
  Map? savedDraft;
  int saveConflicts = 0;
  Completer<Map<String, dynamic>>? nextRead;
  @override
  Stream<Map<String, dynamic>> sse(
    String path, {
    String method = 'GET',
    Object? body,
  }) => syncEvents.stream;
  @override
  Future<dynamic> post(String path, [Object? body, Duration? timeout]) async {
    if (path.endsWith('/draft')) {
      savedDraft = body as Map;
      return {'ok': true};
    }
    return super.post(path, body, timeout);
  }

  Map? selection;
  Map? request;
  final conversations = <String, Map>{};
  @override
  Future<dynamic> studyConversation(String lecture, String id) async =>
      conversations[id] ??
      {
        'version': 1,
        'revision': 0,
        'id': id,
        'draft': '',
        'query': {'objects': [], 'selection': {}, 'include_video': false},
        'turns': [],
      };
  @override
  Future<dynamic> saveStudyConversation(
    String lecture,
    String id,
    Map data,
  ) async {
    conversations[id] = jsonDecode(
      jsonEncode({...data, 'revision': (data['revision'] as int) + 1}),
    ) as Map;
    return conversations[id];
  }

  @override
  Future<dynamic> studyCanvas(String id) async {
    final read = nextRead;
    nextRead = null;
    return read == null ? doc : read.future;
  }

  @override
  Future<dynamic> saveStudyCanvas(
    String id,
    Map<String, dynamic> document,
  ) async {
    if (saveConflicts > 0) {
      saveConflicts--;
      throw ApiError(409, 'another save arrived');
    }
    if (document['revision'] != doc['revision'] ||
        (document['base_hash'] ?? '') != (doc['base_hash'] ?? '')) {
      throw ApiError(409, 'stale canvas');
    }
    final revision = (doc['revision'] as int) + 1;
    doc = {...document, 'revision': revision, 'base_hash': 'saved-$revision'};
    return doc;
  }

  @override
  Future<dynamic> studyContext(String id, Map<String, dynamic> query) async {
    selection = query;
    return {
      'sources': [
        {
          'id': 'object-text',
          'label': '所选原文',
          'text': '真实选择',
          'availability': 'text',
          'anchor': {'object_id': 'text'},
        },
      ],
    };
  }

  @override
  Future<dynamic> startCanvasRun(Map<String, dynamic> value) async {
    request = value;
    return {'id': 'run'};
  }

  @override
  Future<dynamic> canvasRun(String id) async => {
    'state': 'error',
    'error': '尚未配置模型，请到设置添加',
    'trace': [],
  };
}

class FixturePlayer implements LecturePlayer {
  @override
  final lectureId = 'fixture';
  @override
  Lecture? get lecture => null;
  @override
  List<CoursewareFile> get courseware => [];
  @override
  final position = ValueNotifier(const Duration(seconds: 530));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<GlobalKey<StudyCanvasState>> open(
  WidgetTester t,
  FixtureApi api, {
  GlobalKey? capture,
  Brightness brightness = Brightness.light,
  bool resetPreferences = true,
}) async {
  if (resetPreferences) SharedPreferences.setMockInitialValues({});
  final prefs = await UiPrefs.load();
  t.view.physicalSize = const Size(1600, 1100);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final key = GlobalKey<StudyCanvasState>();
  await t.pumpWidget(
    RepaintBoundary(
      key: capture,
      child: MaterialApp(
        theme: buildTheme(buildScheme(prefs, brightness), prefs),
        home: Scaffold(
          body: StudyCanvasSurface(
            prefs: prefs,
            child: StudyCanvas(
              key: key,
              api: api,
              ctl: FixturePlayer(),
              video: const Text('视频占位'),
              panel: const SizedBox(width: 240),
              onClassic: () {},
              onAsk: (_) {},
              onBack: () {},
            ),
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return key;
}

void main() {
  testWidgets(
    'paper appearance survives reopening without editing the course',
    (t) async {
      final api = FixtureApi(StudyDocument().json());
      final capture = GlobalKey();
      final key = await open(t, api, capture: capture);
      final before = jsonEncode(key.currentState!.document!.json());
      await t.tap(find.byTooltip('纸张背景'));
      await t.pumpAndSettle();
      await t.tap(find.text('空白'));
      await t.tap(find.text('米色'));
      await t.tap(find.text('完成'));
      await t.pumpAndSettle();
      expect(jsonEncode(key.currentState!.document!.json()), before);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      await open(t, api, capture: capture, resetPreferences: false);
      final boundary =
          capture.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = (await t.runAsync(() => boundary.toImage(pixelRatio: 1)))!;
      final pixels = (await t.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
      ))!;
      final i = (500 * image.width + 500) * 4;
      expect(
        [pixels.getUint8(i), pixels.getUint8(i + 1), pixels.getUint8(i + 2)],
        [255, 246, 221],
      );
      image.dispose();
      await t.tap(find.byTooltip('纸张背景'));
      await t.pumpAndSettle();
      expect(
        t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '米色')).selected,
        isTrue,
      );
      await t.tap(find.text('方格'));
      await t.tap(find.text('完成'));
      await t.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      expect(
        jsonDecode(prefs.getString('study.notein-layout.v2')!)['paper'],
        'grid',
      );
      await t.pumpWidget(const SizedBox());
      await api.syncEvents.close();
    },
  );

  testWidgets('edge docking persists without changing course content', (
    t,
  ) async {
    final doc = StudyDocument()
      ..camera = Offset.zero
      ..zoom = 1;
    final api = FixtureApi(doc.json());
    final key = await open(t, api);
    final before = jsonEncode(key.currentState!.document!.json());
    await t.sendEventToBinding(
      PointerScrollEvent(
        position: t.getCenter(
          find.byKey(const ValueKey('study-dock-handle-pens')),
        ),
        scrollDelta: const Offset(0, 80),
      ),
    );
    await t.pumpAndSettle();
    final stage = t.getRect(find.byKey(const ValueKey('study-input')));
    expect(stage.top, 0);
    expect(find.textContaining('拖动卡片标题'), findsNothing);
    final handle = find.byKey(const ValueKey('study-dock-handle-pens'));
    Future<void> dragDock(Offset target) async {
      final start = t.getCenter(handle);
      final gesture = await t.startGesture(start);
      await gesture.moveTo((start + target) / 2);
      await t.pump(const Duration(milliseconds: 32));
      await gesture.moveTo(target);
      await t.pump(const Duration(milliseconds: 32));
      await gesture.up();
      await t.pumpAndSettle();
    }

    await dragDock(stage.centerLeft);
    expect(t.getRect(find.byKey(const ValueKey('study-dock-pens'))).left, 0);
    expect(
      t.getRect(find.byKey(const ValueKey('study-dock-modules'))).top,
      stage.top,
    );
    for (final target in [
      stage.topCenter,
      stage.bottomCenter,
      stage.centerRight,
      stage.centerLeft,
    ]) {
      await dragDock(target);
      final rect = t.getRect(find.byKey(const ValueKey('study-dock-pens')));
      expect(stage.contains(rect.topLeft), isTrue);
      expect(rect.right, lessThanOrEqualTo(stage.right));
      expect(rect.bottom, lessThanOrEqualTo(stage.bottom));
      final error = t.takeException();
      expect(error, isNull, reason: 'docking to $target');
    }
    t.view.physicalSize = const Size(400, 700);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    t.view.physicalSize = const Size(1600, 1100);
    await t.pumpAndSettle();
    expect(jsonEncode(key.currentState!.document!.json()), before);
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
    await open(t, api, resetPreferences: false);
    expect(t.getRect(find.byKey(const ValueKey('study-dock-pens'))).left, 0);
    await t.pumpWidget(const SizedBox());
    await api.syncEvents.close();
  });

  testWidgets(
    'pen selection recalls its settings and second tap opens settings',
    (t) async {
      final api = FixtureApi(StudyDocument().json());
      await open(t, api);
      final first = find.byKey(const ValueKey('study-tool-pen'));
      final second = find.byKey(const ValueKey('study-pen-1'));
      await t.tap(first);
      await t.pumpAndSettle();
      expect(find.text('实时笔迹预览'), findsNothing);
      await t.tap(find.byTooltip('笔宽 6'));
      await t.tap(second);
      await t.pumpAndSettle();
      expect(
        t
            .widget<IconButton>(
              find
                  .ancestor(
                    of: find.byTooltip('笔宽 6'),
                    matching: find.byType(IconButton),
                  )
                  .first,
            )
            .isSelected,
        isFalse,
      );
      await t.tap(first);
      await t.pumpAndSettle();
      expect(
        t
            .widget<IconButton>(
              find
                  .ancestor(
                    of: find.byTooltip('笔宽 6'),
                    matching: find.byType(IconButton),
                  )
                  .first,
            )
            .isSelected,
        isTrue,
      );
      await t.tap(first);
      await t.pumpAndSettle();
      expect(find.text('实时笔迹预览'), findsOneWidget);
      expect(
        t.getRect(find.byKey(const ValueKey('study-pen-popover'))).bottom,
        lessThan(t.getRect(first).top),
      );
      await t.tap(find.byTooltip('关闭设置'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('study-tool-eraser')));
      await t.pumpAndSettle();
      final color = find.byKey(const ValueKey('study-pen-color-4293284709'));
      await t.ensureVisible(color);
      await t.tap(color);
      await t.pumpAndSettle();
      expect(
        t
            .getSemantics(find.byKey(const ValueKey('study-tool-eraser')))
            .getSemanticsData()
            .hasFlag(ui.SemanticsFlag.isSelected),
        isFalse,
      );
      await t.pumpWidget(const SizedBox());
      await api.syncEvents.close();
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets('canvas controls remain readable in ${brightness.name} mode', (
      t,
    ) async {
      await open(t, FixtureApi(StudyDocument().json()), brightness: brightness);

      void readable(Finder control, double minimum) {
        final glyph = find
            .descendant(of: control, matching: find.byType(RichText))
            .first;
        final foreground = t.widget<RichText>(glyph).text.style!.color!;
        final background = find
            .ancestor(of: glyph, matching: find.byType(Material))
            .evaluate()
            .map((e) => e.widget as Material)
            .firstWhere((m) => m.color?.a == 1)
            .color!;
        final ink = Color.alphaBlend(foreground, background).computeLuminance();
        final paper = background.computeLuminance();
        final ratio =
            (ink > paper ? ink + .05 : paper + .05) /
            (ink > paper ? paper + .05 : ink + .05);
        expect(ratio, greaterThanOrEqualTo(minimum), reason: '$control');
      }

      readable(find.byKey(const ValueKey('study-tool-select')), 3);
      readable(find.byKey(const ValueKey('study-tool-hand')), 3);
      readable(find.byTooltip('画笔与橡皮设置'), 3);
      readable(find.byTooltip('添加模块'), 3);
      readable(find.byTooltip('课程资料'), 3);
      readable(find.byTooltip('问 AI'), 3);
      expect(
        t
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.undo))
            .onPressed,
        isNull,
      );
      await t.tap(find.byTooltip('画笔与橡皮设置'));
      await t.pumpAndSettle();
      readable(find.text('笔盒'), 4.5);
      readable(find.text('实时笔迹预览'), 4.5);
      readable(find.text('圆珠笔与荧光笔保持均匀宽度；钢笔、铅笔与软笔响应压力。鼠标使用固定压力。'), 4.5);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    });
  }

  testWidgets(
    'latest saved whole canvas refreshes and pending edits finish automatically',
    (t) async {
      final first = StudyDocument()..baseHash = 'old';
      final api = FixtureApi(first.json());
      final key = await open(t, api);
      final remote = StudyDocument()..baseHash = 'remote';
      remote.cards.add(
        StudyCard(
          id: 'remote',
          type: 'text',
          layer: 'main',
          rect: const Rect.fromLTWH(40, 70, 300, 200),
          text: '另一端内容',
          title: '远端',
        ),
      );
      api.doc = remote.json();
      api.syncEvents.add({
        'type': 'sync_done',
        'data': {'downloaded': 1},
      });
      await t.pumpAndSettle();
      expect(key.currentState!.document!.cards.single.id, 'remote');
      final local = key.currentState!.document!;
      local.cards.single.text = '本机未保存';
      local.changed();
      await t.pump(const Duration(milliseconds: 10));
      final latest = StudyDocument.fromJson(remote.json())
        ..baseHash = 'new-remote';
      latest.cards.single.text = '另一端再次修改';
      api.doc = latest.json();
      api.syncEvents.add({
        'type': 'sync_done',
        'data': {'downloaded': 1},
      });
      await t.pumpAndSettle();
      expect(key.currentState!.document!.cards.single.text, '本机未保存');
      expect(find.text('保留本机'), findsNothing);
      expect(find.text('采用另一端'), findsNothing);
      await t.pump(const Duration(seconds: 2));
      await t.pumpAndSettle();
      expect(api.doc['objects'].single['text'], '本机未保存');
      expect(api.savedDraft!['objects'].single['text'], '另一端再次修改');
      expect(find.byTooltip('已保存到本机'), findsOneWidget);
      final next = StudyDocument.fromJson(api.doc)..baseHash = 'next';
      next.cards.clear();
      api.doc = next.json();
      api.syncEvents.add({
        'type': 'sync_done',
        'data': {'downloaded': 1},
      });
      await t.pumpAndSettle();
      expect(key.currentState!.document!.cards, isEmpty);
      await t.pumpWidget(const SizedBox());
      await api.syncEvents.close();
    },
  );

  testWidgets('canvas catches up when a sync notification is missed', (
    t,
  ) async {
    final api = FixtureApi(StudyDocument().json());
    final key = await open(t, api);
    final remote = StudyDocument()..baseHash = 'arrived-without-event';
    remote.cards.add(
      StudyCard(
        id: 'arrived',
        type: 'text',
        layer: 'main',
        rect: const Rect.fromLTWH(40, 70, 300, 200),
        text: '已到本机但未推送',
        title: '收到更新',
      ),
    );
    api.doc = remote.json();
    await t.pump(const Duration(seconds: 5));
    await t.pumpAndSettle();
    expect(key.currentState!.document!.cards.single.id, 'arrived');
    await t.pumpWidget(const SizedBox());
    await api.syncEvents.close();
  });

  testWidgets('a local edit started during a remote read finishes saving', (
    t,
  ) async {
    final api = FixtureApi(StudyDocument().json());
    final key = await open(t, api);
    final read = Completer<Map<String, dynamic>>();
    api.nextRead = read;
    api.syncEvents.add({
      'type': 'sync_done',
      'data': {'downloaded': 1},
    });
    await t.pump();
    final doc = key.currentState!.document!;
    doc.cards.add(
      StudyCard(
        id: 'typing',
        type: 'text',
        layer: 'main',
        rect: const Rect.fromLTWH(40, 70, 300, 200),
        text: '刚刚开始写',
        title: '本机',
      ),
    );
    doc.changed();
    api.doc = (StudyDocument()..baseHash = 'remote-read').json();
    read.complete(api.doc);
    await t.pumpAndSettle();
    expect(key.currentState!.document!.cards.single.text, '刚刚开始写');
    await t.pump(const Duration(seconds: 2));
    await t.pumpAndSettle();
    expect(api.doc['objects'].single['text'], '刚刚开始写');
    await t.pumpWidget(const SizedBox());
    await api.syncEvents.close();
  });

  for (final conflicts in [2, 3]) {
    testWidgets('canvas save retries are bounded after $conflicts races', (
      t,
    ) async {
      final api = FixtureApi(StudyDocument().json())..saveConflicts = conflicts;
      final key = await open(t, api);
      final doc = key.currentState!.document!;
      doc.camera = const Offset(90, 100);
      doc.changed();
      final saved = await key.currentState!.flush();
      expect(saved, conflicts == 2);
      expect(doc.camera, const Offset(90, 100));
      if (saved) {
        expect(api.doc['camera']['x'], 90);
      } else {
        expect(doc.edit, greaterThan(0));
      }
      await t.pumpWidget(const SizedBox());
      await api.syncEvents.close();
    });
  }

  testWidgets('pen dock does not draw ink and brush choice is saved', (
    t,
  ) async {
    final capture = GlobalKey();
    final key = await open(
      t,
      FixtureApi(StudyDocument().json()),
      capture: capture,
    );
    await t.tap(find.byKey(const ValueKey('study-tool-pen')));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('画笔与橡皮设置'));
    await t.pumpAndSettle();
    final header = t.getRect(find.text('笔盒'));
    final boundary =
        capture.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = (await t.runAsync(() => boundary.toImage(pixelRatio: 1)))!;
    final pixels = (await t.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    ))!;
    var dark = 0;
    for (var y = header.top.ceil(); y < header.bottom.floor(); y++) {
      for (var x = header.left.ceil(); x < header.right.floor(); x++) {
        final i = (y * image.width + x) * 4;
        if (pixels.getUint8(i) < 120 &&
            pixels.getUint8(i + 1) < 120 &&
            pixels.getUint8(i + 2) < 120)
          dark++;
      }
    }
    image.dispose();
    expect(dark, greaterThan(20), reason: '笔触预览不能覆盖其边界外的笔盒标题');
    await t.tap(find.text('铅笔').last);
    await t.pumpAndSettle();
    expect(key.currentState!.document!.strokes, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('study.brush-presets.v1'), contains('pencil'));
    final saved = jsonDecode(prefs.getString('study.brush-presets.v1')!);
    expect(saved['presets'][0]['name'], '铅笔');
    // Older versions could save a new brush under a stale built-in name.
    saved['presets'][0]['name'] = '钢笔';
    await prefs.setString('study.brush-presets.v1', jsonEncode(saved));
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
    await open(t, FixtureApi(StudyDocument().json()), resetPreferences: false);
    expect(find.byTooltip('钢笔：点选，再点设置'), findsNothing);
    expect(find.byTooltip('铅笔：点选，再点设置'), findsNWidgets(2));
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
  });
  testWidgets(
    'real text selection offsets and video time reach context; missing model is visible',
    (t) async {
      final d = StudyDocument()
        ..cards.add(
          StudyCard(
            id: 'text',
            type: 'text',
            layer: 'main',
            rect: const Rect.fromLTWH(130, 80, 500, 400),
            text: '前😀后选中内容',
            title: '材料',
          ),
        );
      final api = FixtureApi(d.json());
      final key = await open(t, api);
      final selectable = t.widget<SelectableText>(
        find.byWidgetPredicate(
          (w) => w is SelectableText && w.data == '前😀后选中内容',
        ),
      );
      selectable.onSelectionChanged!(
        const TextSelection(baseOffset: 3, extentOffset: 6),
        SelectionChangedCause.drag,
      );
      await t.tap(find.byTooltip('问 AI'));
      await t.pumpAndSettle();
      expect(api.selection?['objects'], ['text']);
      expect(api.selection?['selection']['start'], 3);
      expect(api.selection?['selection']['end'], 6);
      expect(api.selection?['include_video'], false);
      expect(find.text('所选原文'), findsOneWidget);
      await t.enterText(find.byType(TextField).last, '解释选区');
      await t.tap(find.byTooltip('发送'));
      await t.pumpAndSettle();
      expect(find.text('尚未配置模型，请到设置添加'), findsOneWidget);
      expect(key.currentState!.document!.cards.length, 2);
      expect(api.conversations.values.single['turns'], isNotEmpty);

      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    },
  );
  testWidgets('exercise responses persist and undo refreshes the editor', (
    t,
  ) async {
    final d = StudyDocument()
      ..cards.add(
        StudyCard(
          id: 'practice',
          type: 'practice',
          layer: 'main',
          rect: const Rect.fromLTWH(130, 60, 520, 650),
          title: '自测',
          generation: 'fixture-run',
          blocks: [
            StudyBlock(
              type: 'exercise',
              text: '为什么 miss 更慢？',
              answer: '需要访问主存',
            ),
          ],
        ),
      );
    final api = FixtureApi(d.json());
    final key = await open(t, api);
    final input = find.byType(TextField);
    await t.tap(input);
    await t.enterText(input, '需要访问下一层存储');
    await t.pumpAndSettle();
    expect(
      key.currentState!.document!.cards.single.responses['0'],
      '需要访问下一层存储',
    );
    await key.currentState!.flush();
    expect(
      StudyDocument.fromJson(api.doc).cards.single.responses['0'],
      '需要访问下一层存储',
    );
    key.currentState!.document!.undo();
    await t.pumpAndSettle();
    expect(t.widget<TextField>(input).controller!.text, '');
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
  });
  testWidgets(
    'drawn ink is sent as a bounded real PNG only after visual opt-in',
    (t) async {
      final api = FixtureApi(StudyDocument().json());
      final key = await open(t, api);
      await t.tap(find.byKey(const ValueKey('study-tool-pen')));
      await t.pumpAndSettle();
      await t.dragFrom(
        const Offset(400, 350),
        const Offset(160, 90),
        kind: ui.PointerDeviceKind.stylus,
      );
      await t.pumpAndSettle();
      expect(key.currentState!.document!.strokes, isNotEmpty);
      await t.runAsync(() async {
        await t.tap(find.byTooltip('问 AI'));
        for (var i = 0; i < 80 && api.selection == null; i++) {
          await t.pump();
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await t.pumpAndSettle();
      await t.tap(find.byType(Checkbox));
      await t.enterText(find.byType(TextField).last, '解释这条实际笔迹');
      // Real raster readback must run outside the widget test's fake clock.
      await t.runAsync(() async {
        await t.tap(find.byTooltip('发送'));
        for (var i = 0; i < 80 && api.request == null; i++) {
          await t.pump();
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await t.pumpAndSettle();
      final attachment = (api.request!['visuals'] as List).single as Map;
      expect(attachment['source_id'], 'selected-ink');
      final bytes = base64Decode(attachment['data'] as String);
      expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      final codec = (await t.runAsync(() => ui.instantiateImageCodec(bytes)))!;
      final frame = (await t.runAsync(codec.getNextFrame))!;
      expect(frame.image.width, lessThan(400));
      expect(frame.image.height, lessThan(400));
      final pixels = (await t.runAsync(
        () => frame.image.toByteData(format: ui.ImageByteFormat.rawRgba),
      ))!;
      var dark = 0;
      for (var i = 0; i < pixels.lengthInBytes; i += 4) {
        if (pixels.getUint8(i) < 120 &&
            pixels.getUint8(i + 1) < 120 &&
            pixels.getUint8(i + 2) < 120)
          dark++;
      }
      expect(dark, greaterThan(10), reason: '选区附件必须包含实际画出的深色笔迹');
      frame.image.dispose();
      codec.dispose();

      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    },
  );
  testWidgets(
    'clicking a citation focuses the moved source and exposes its real excerpt',
    (t) async {
      final d = StudyDocument()
        ..cards.addAll([
          StudyCard(
            id: 'source',
            type: 'text',
            layer: 'main',
            rect: const Rect.fromLTWH(1800, 800, 500, 600),
            title: '原资料',
            text: '前😀后选中内容',
          ),
          StudyCard(
            id: 'answer',
            type: 'explanation',
            layer: 'main',
            rect: const Rect.fromLTWH(130, 60, 520, 440),
            title: '协议卡',
            generation: 'protocol-fixture',
            blocks: [StudyBlock(type: 'paragraph', text: '引用导航测试')],
            sources: [
              StudyAnchor(
                id: 'object-source',
                objectId: 'source',
                kind: 'text',
                workspaceId: 'fixture',
                start: 3,
                end: 6,
                quote: '后选中',
              ),
            ],
          ),
        ]);
      final key = await open(t, FixtureApi(d.json()));
      final before = key.currentState!.document!.camera;
      await t.tap(find.textContaining('TEXT · 后选中'));
      await t.pumpAndSettle();
      expect(key.currentState!.document!.camera, isNot(before));
      expect(find.text('来源原文：后选中'), findsOneWidget);
      expect(find.text('原资料'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    },
  );
}
