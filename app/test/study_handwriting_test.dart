import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/features/study_canvas/study_document.dart';
import 'study_canvas_ui_test.dart' as fixture;

StudyDocument sheet() => StudyDocument()
  ..camera = Offset.zero
  ..zoom = 1;
StudyStroke stroke(
  String id, {
  double y = 350,
  String layer = 'main',
  String? gesture,
}) => StudyStroke(
  id: id,
  layer: layer,
  gesture: gesture,
  color: 0xff26354a,
  width: 3,
  points: [
    for (var x = 300; x <= 500; x += 4) InkPoint(Offset(x.toDouble(), y), .6),
  ],
);
Future<void> close(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pumpAndSettle();
}

Future<void> selectInk(WidgetTester t) async {
  await t.tap(find.byKey(const ValueKey('study-tool-region')));
  await t.pumpAndSettle();
  final origin = t.getTopLeft(find.byKey(const ValueKey('study-input')));
  final g = await t.startGesture(
    origin + const Offset(275, 320),
    kind: ui.PointerDeviceKind.stylus,
  );
  for (final p in [
    const Offset(530, 320),
    const Offset(530, 390),
    const Offset(275, 390),
    const Offset(275, 320),
  ]) {
    await g.moveTo(origin + p);
    await t.pump();
  }
  await g.up();
  await t.pumpAndSettle();
}

Future<void> saveReviewImage(
  WidgetTester t,
  GlobalKey capture,
  String name,
) async {
  final folder = Platform.environment['STUDY_REVIEW_IMAGES'];
  if (folder == null) return;
  final boundary =
      capture.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final image = (await t.runAsync(() => boundary.toImage(pixelRatio: 1)))!;
  final bytes = (await t.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.png),
  ))!;
  await t.runAsync(
    () => File('$folder/$name.png').writeAsBytes(bytes.buffer.asUint8List()),
  );
  image.dispose();
}

void main() {
  test('lasso selects sparse crossing segments and whole gesture, excludes hidden layers', () {
    final d = sheet();
    d.layers.add(StudyLayer('hidden', 'hidden', visible: false));
    d.strokes = [
      StudyStroke(
        id: 'a',
        layer: 'main',
        gesture: 'g',
        color: 1,
        width: 2,
        points: [
          const InkPoint(Offset(0, 50), .3),
          const InkPoint(Offset(100, 50), .8),
        ],
      ),
      stroke('b', gesture: 'g'),
      stroke('hidden', layer: 'hidden'),
    ];
    expect(
      d.strokesInPolygon([
        const Offset(40, 40),
        const Offset(60, 40),
        const Offset(60, 60),
        const Offset(40, 60),
      ]),
      {'a', 'b'},
    );
  });
  test('selected ink transform preserves IDs, pressure and sources through save and undo', () {
    final d = sheet();
    d.strokes = [stroke('a'), stroke('locked', layer: 'locked')];
    d.layers.add(StudyLayer('locked', 'locked', locked: true));
    final old = jsonEncode(d.json());
    d.checkpoint();
    const from = Rect.fromLTWH(300, 345, 200, 10),
        to = Rect.fromLTWH(350, 395, 400, 20);
    d.transformInk({'a', 'locked'}, from, to, color: 0xffe65365);
    final restored = StudyDocument.fromJson(d.json());
    expect(restored.strokes.first.id, 'a');
    expect(restored.strokes.first.points.first.pressure, .6);
    expect(restored.strokes.first.points.first.p, const Offset(350, 405));
    expect(restored.strokes.last.points.first.p, const Offset(300, 350));
    d.undo();
    expect(jsonEncode(d.json()), old);
  });
  testWidgets(
    'arrow pans blank canvas; dock collapse and expand never create a selection or stroke',
    (t) async {
      final key = await fixture.open(t, fixture.FixtureApi(sheet().json()));
      final d = key.currentState!.document!;
      await t.dragFrom(
        const Offset(350, 450),
        const Offset(130, 65),
        kind: ui.PointerDeviceKind.mouse,
      );
      await t.pumpAndSettle();
      expect(d.camera, const Offset(130, 65));
      expect(find.text('副本'), findsNothing);
      await t.tap(find.byKey(const ValueKey('study-tool-pen')));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('收起笔盒'));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('展开笔盒'));
      await t.pumpAndSettle();
      expect(d.strokes, isEmpty);
      expect(find.text('副本'), findsNothing);
      expect(t.takeException(), isNull);
      await close(t);
    },
  );
  testWidgets(
    'eraser displays an actual radius ring and erases at that location',
    (t) async {
      final d = sheet()..strokes.add(stroke('a'));
      final key = await fixture.open(t, fixture.FixtureApi(d.json()));
      await t.tap(find.byKey(const ValueKey('study-tool-eraser')));
      await t.pumpAndSettle();
      // A single tap activates the eraser without opening a modal setting sheet.
      expect(find.byType(Dialog), findsNothing);
      final pos =
          t.getTopLeft(find.byKey(const ValueKey('study-input'))) +
          const Offset(400, 350);
      final g = await t.startGesture(pos, kind: ui.PointerDeviceKind.stylus);
      await t.pump();
      final painter = t
          .widget<CustomPaint>(find.byKey(const ValueKey('study-feedback')))
          .painter!;
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), const Size(1240, 992));
      final picture = recorder.endRecording();
      final image = (await t.runAsync(() => picture.toImage(1240, 992)))!;
      final data = (await t.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
      ))!;
      var outline = 0;
      for (var y = 330; y <= 370; y++) {
        for (var x = 380; x <= 420; x++) {
          final i = (y * 1240 + x) * 4;
          if (data.getUint8(i + 3) > 128 && data.getUint8(i) < 140) outline++;
        }
      }
      image.dispose();
      picture.dispose();
      expect(outline, greaterThan(40));
      expect(
        key.currentState!.document!.strokes
            .expand((s) => s.points)
            .any((p) => (p.p.dx - 400).abs() < 18),
        false,
      );
      await g.up();
      await t.pumpAndSettle();
      await close(t);
    },
  );
  testWidgets(
    'pressure hold temporarily erases, lifts back to pen, and cancel discards a draft',
    (t) async {
      final original = sheet()..strokes.add(stroke('a'));
      final key = await fixture.open(t, fixture.FixtureApi(original.json()));
      await t.tap(find.byKey(const ValueKey('study-tool-pen')));
      await t.pumpAndSettle();
      final origin = t.getTopLeft(find.byKey(const ValueKey('study-input'))),
          p = origin + const Offset(400, 350);
      await t.sendEventToBinding(
        PointerDownEvent(
          pointer: 21,
          kind: ui.PointerDeviceKind.stylus,
          position: p,
          pressure: .94,
          pressureMin: 0,
          pressureMax: 1,
        ),
      );
      await t.pump(const Duration(milliseconds: 400));
      final d = key.currentState!.document!;
      expect(
        d.strokes.expand((s) => s.points).any((p) => (p.p.dx - 400).abs() < 18),
        false,
      );
      await t.sendEventToBinding(
        PointerUpEvent(
          pointer: 21,
          kind: ui.PointerDeviceKind.stylus,
          position: p,
        ),
      );
      await t.pumpAndSettle();
      d.undo();
      await t.pumpAndSettle();
      expect(
        jsonEncode(d.strokes.map((s) => s.json()).toList()),
        jsonEncode(original.strokes.map((s) => s.json()).toList()),
      );
      await t.dragFrom(
        origin + const Offset(600, 450),
        const Offset(50, 20),
        kind: ui.PointerDeviceKind.stylus,
      );
      await t.pumpAndSettle();
      expect(d.strokes.any((s) => s.points.first.p.dx >= 600), true);
      final before = jsonEncode(d.strokes.map((s) => s.json()).toList());
      await t.sendEventToBinding(
        PointerDownEvent(
          pointer: 22,
          kind: ui.PointerDeviceKind.stylus,
          position: p,
          pressure: .3,
        ),
      );
      await t.sendEventToBinding(
        PointerCancelEvent(
          pointer: 22,
          kind: ui.PointerDeviceKind.stylus,
          position: p,
        ),
      );
      await t.pump(const Duration(milliseconds: 500));
      expect(jsonEncode(d.strokes.map((s) => s.json()).toList()), before);
      await close(t);
    },
  );
  testWidgets(
    'lasso actions move, recolor, duplicate and persist ink; undo is one action',
    (t) async {
      final d = sheet()..strokes.add(stroke('a'));
      final api = fixture.FixtureApi(d.json());
      final capture = GlobalKey();
      final key = await fixture.open(t, api, capture: capture);
      await selectInk(t);
      await saveReviewImage(t, capture, 'lasso');
      expect(find.text('复制'), findsOneWidget);
      final current = key.currentState!.document!;
      final before = current.strokes.single.points.first.p;
      final origin = t.getTopLeft(find.byKey(const ValueKey('study-input')));
      await t.dragFrom(
        origin + const Offset(400, 350),
        const Offset(50, 50),
        kind: ui.PointerDeviceKind.stylus,
      );
      await t.pumpAndSettle();
      expect(
        current.strokes.single.points.first.p,
        before + const Offset(50, 50),
      );
      await t.tap(find.byTooltip('选区改色'));
      await t.pumpAndSettle();
      await t.tap(find.text('#e65365'));
      await t.pumpAndSettle();
      expect(current.strokes.single.color, 0xffe65365);
      await t.tap(find.text('副本'));
      await t.pumpAndSettle();
      expect(current.strokes.length, 2);
      current.undo();
      await t.pumpAndSettle();
      expect(current.strokes.length, 1);
      await key.currentState!.flush();
      expect(StudyDocument.fromJson(api.doc).strokes.single.color, 0xffe65365);
      expect(t.takeException(), isNull);
      await close(t);
    },
  );
  testWidgets(
    'pinch retains document widgets and position, then edits at transformed coordinates',
    (t) async {
      final d = sheet()
        ..cards.add(
          StudyCard(
            id: 'text',
            type: 'text',
            layer: 'main',
            title: '保留的卡片',
            text: '缩放过程中不重新排版',
            rect: const Rect.fromLTWH(200, 100, 400, 260),
          ),
        );
      final key = await fixture.open(t, fixture.FixtureApi(d.json()));
      final cardFinder = find.byKey(const ValueKey('study-card/text'));
      final element = t.element(cardFinder), widget = t.widget(cardFinder);
      final g1 = await t.startGesture(
        const Offset(350, 600),
        pointer: 31,
        kind: ui.PointerDeviceKind.touch,
      );
      final g2 = await t.startGesture(
        const Offset(550, 600),
        pointer: 32,
        kind: ui.PointerDeviceKind.touch,
      );
      for (var i = 1; i <= 10; i++) {
        await g2.moveTo(Offset(550 + i * 10, 600));
        await t.pump(const Duration(milliseconds: 16));
      }
      expect(identical(t.element(cardFinder), element), true);
      expect(
        identical(t.widget(cardFinder), widget),
        true,
        reason: 'camera movement must retain world layout',
      );
      expect(key.currentState!.document!.zoom, closeTo(1.5, .01));
      await g2.up();
      await g1.up();
      await t.pumpAndSettle();
      final rect = t.getRect(find.text('保留的卡片'));
      expect(rect.width, greaterThan(0));
      expect(t.takeException(), isNull);
      await close(t);
    },
  );
  testWidgets('tablet portrait tool settings stay within screen', (t) async {
    final capture = GlobalKey();
    await fixture.open(t, fixture.FixtureApi(sheet().json()), capture: capture);
    t.view.physicalSize = const Size(800, 1100);
    await t.pumpAndSettle();
    // The panel can be hidden to provide the same writing viewport as a tablet.
    await t.tap(find.byTooltip('画笔与橡皮设置'));
    await t.pumpAndSettle();
    expect(t.getRect(find.byType(Dialog)).right, lessThanOrEqualTo(800));
    await saveReviewImage(t, capture, 'pen-settings');
    expect(t.takeException(), isNull);
    await close(t);
  });
  testWidgets(
    'moving pressure and devices without pressure ranges do not trigger erasing',
    (t) async {
      final d = sheet()..strokes.add(stroke('a'));
      final key = await fixture.open(t, fixture.FixtureApi(d.json()));
      await t.tap(find.byKey(const ValueKey('study-tool-pen')));
      await t.pumpAndSettle();
      final origin = t.getTopLeft(find.byKey(const ValueKey('study-input')));
      await t.sendEventToBinding(
        PointerDownEvent(
          pointer: 71,
          kind: ui.PointerDeviceKind.stylus,
          position: origin + const Offset(300, 500),
          pressure: .95,
          pressureMin: 0,
          pressureMax: 1,
        ),
      );
      for (var i = 1; i <= 10; i++) {
        await t.sendEventToBinding(
          PointerMoveEvent(
            pointer: 71,
            kind: ui.PointerDeviceKind.stylus,
            position: origin + Offset(300 + i * 12, 500),
            pressure: .95,
            pressureMin: 0,
            pressureMax: 1,
          ),
        );
        await t.pump(const Duration(milliseconds: 80));
      }
      await t.sendEventToBinding(
        PointerUpEvent(
          pointer: 71,
          kind: ui.PointerDeviceKind.stylus,
          position: origin + const Offset(420, 500),
        ),
      );
      await t.pumpAndSettle();
      expect(
        key.currentState!.document!.strokes.any(
          (s) => s.points.any((p) => p.p.dy == 500),
        ),
        true,
      );
      await t.sendEventToBinding(
        PointerDownEvent(
          pointer: 72,
          kind: ui.PointerDeviceKind.stylus,
          position: origin + const Offset(400, 350),
          pressure: 1,
          pressureMin: 1,
          pressureMax: 1,
        ),
      );
      await t.pump(const Duration(milliseconds: 500));
      expect(key.currentState!.document!.strokes.any((s) => s.id == 'a'), true);
      await t.sendEventToBinding(
        PointerCancelEvent(
          pointer: 72,
          kind: ui.PointerDeviceKind.stylus,
          position: origin + const Offset(400, 350),
        ),
      );
      await close(t);
    },
  );
  testWidgets(
    'a loop within a PDF keeps the PDF as source without moving the page',
    (t) async {
      final d = sheet()
        ..cards.add(
          StudyCard(
            id: 'pdf-page',
            type: 'text',
            layer: 'main',
            title: '页面',
            text: '用于检验页面选区的原文',
            rect: const Rect.fromLTWH(150, 150, 600, 550),
          ),
        );
      d.strokes.add(
        StudyStroke(
          id: 's',
          layer: 'main',
          color: 0xff26354a,
          width: 3,
          anchor: 'pdf-page',
          points: [
            const InkPoint(Offset(300, 350), .5),
            const InkPoint(Offset(500, 350), .5),
          ],
        ),
      );
      final api = fixture.FixtureApi(d.json());
      final key = await fixture.open(t, api);
      await selectInk(t);
      final before = key.currentState!.document!.cards.single.rect;
      await t.runAsync(() async {
        await t.tap(find.text('问 AI').last);
        for (var i = 0; i < 80 && api.selection == null; i++) {
          await t.pump();
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await t.pumpAndSettle();
      expect(api.selection?['objects'], ['pdf-page']);
      expect(api.selection?['selection']['object_id'], 'pdf-page');
      expect(api.selection?['selection']['stroke_ids'], ['s']);
      expect(
        key.currentState!.document!.cards
            .firstWhere((c) => c.id == 'pdf-page')
            .rect,
        before,
      );
      await close(t);
    },
  );
}
