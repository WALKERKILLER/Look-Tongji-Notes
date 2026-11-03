import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/features/study_canvas/study_document.dart';
import 'study_canvas_ui_test.dart' as fixture;
import 'study_handwriting_test.dart' show close;

Future<void> native(WidgetTester t, Map value) async {
  await t.binding.defaultBinaryMessenger.handlePlatformMessage(
    'look/stylus/events',
    const StandardMethodCodec().encodeSuccessEnvelope(value),
    (_) {},
  );
  await t.pump();
}

Future<int> pixel(WidgetTester t, GlobalKey capture, Offset point) async {
  final boundary =
      capture.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final image = (await t.runAsync(() => boundary.toImage(pixelRatio: 1)))!;
  final bytes = (await t.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
  ))!;
  final offset = (point.dy.round() * image.width + point.dx.round()) * 4;
  final color = bytes.getUint32(offset);
  image.dispose();
  return color;
}

void main() {
  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('look/stylus'),
      (_) async => {'backend': 'androidx'},
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('look/stylus/events'),
      (_) async => null,
    );
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'native preview is visible, expires, ignores stale frames and is never saved',
    (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final capture = GlobalKey();
      final api = fixture.FixtureApi(
        (StudyDocument()
              ..camera = Offset.zero
              ..zoom = 1)
            .json(),
      );
      final key = await fixture.open(t, api, capture: capture);
      await t.tap(find.byKey(const ValueKey('study-tool-pen')));
      await t.pumpAndSettle();
      final origin = t.getTopLeft(find.byKey(const ValueKey('study-input')));
      await t.sendEventToBinding(
        PointerDownEvent(
          pointer: 91,
          kind: ui.PointerDeviceKind.stylus,
          timeStamp: const Duration(milliseconds: 1000),
          position: origin + const Offset(50, 300),
          pressure: .35,
        ),
      );
      await t.sendEventToBinding(
        PointerMoveEvent(
          pointer: 91,
          kind: ui.PointerDeviceKind.stylus,
          timeStamp: const Duration(milliseconds: 1010),
          position: origin + const Offset(400, 300),
          pressure: .35,
        ),
      );
      await t.pump();
      final probe = origin + const Offset(430, 300);
      final before = await pixel(t, capture, probe);
      final event = {
        'type': 'prediction',
        'time': 1010,
        'x': origin.dx + 400,
        'y': origin.dy + 300,
        'points': [
          [origin.dx + 440, origin.dy + 300, .35],
        ],
      };
      await native(t, event);
      expect(await pixel(t, capture, probe), isNot(before));
      expect(key.currentState!.document!.strokes, isEmpty);
      await t.pump(const Duration(milliseconds: 55));
      expect(await pixel(t, capture, probe), before);
      await native(t, {...event, 'time': 1000});
      expect(await pixel(t, capture, probe), before);
      await native(t, event);
      await t.sendEventToBinding(
        PointerUpEvent(
          pointer: 91,
          kind: ui.PointerDeviceKind.stylus,
          position: origin + const Offset(400, 300),
        ),
      );
      await t.pump();
      expect(await pixel(t, capture, probe), before);
      await key.currentState!.flush();
      final saved = StudyDocument.fromJson(api.doc);
      expect(saved.strokes, isNotEmpty);
      expect(
        saved.strokes.expand((s) => s.points).every((p) => p.p.dx <= 400),
        isTrue,
      );
      await native(t, event);
      expect(await pixel(t, capture, probe), before);
      await close(t);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'standard side button temporarily erases then resumes the same pen',
    (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final d = StudyDocument()
        ..camera = Offset.zero
        ..zoom = 1;
      d.strokes.add(
        StudyStroke(
          id: 'ink',
          layer: 'main',
          points: [
            InkPoint(const Offset(300, 300), .5),
            InkPoint(const Offset(450, 300), .5),
          ],
          color: 0xff000000,
          width: 3,
        ),
      );
      final key = await fixture.open(t, fixture.FixtureApi(d.json()));
      await t.tap(find.byKey(const ValueKey('study-tool-pen')));
      await t.pumpAndSettle();
      final origin = t.getTopLeft(find.byKey(const ValueKey('study-input')));
      await t.sendEventToBinding(
        PointerDownEvent(
          pointer: 91,
          kind: ui.PointerDeviceKind.stylus,
          position: origin + const Offset(375, 300),
          buttons: kPrimaryStylusButton,
          pressure: .35,
        ),
      );
      await t.sendEventToBinding(
        PointerUpEvent(
          pointer: 91,
          kind: ui.PointerDeviceKind.stylus,
          position: origin + const Offset(375, 300),
        ),
      );
      final edited = key.currentState!.document!;
      expect(edited.strokes.length, 2);
      expect(
        edited.strokes.any(
          (s) => s.points.any((p) => p.p.dx > 360 && p.p.dx < 390),
        ),
        isFalse,
      );
      edited.undo();
      expect(edited.strokes.single.id, 'ink');
      await t.sendEventToBinding(
        PointerDownEvent(
          pointer: 92,
          kind: ui.PointerDeviceKind.stylus,
          position: origin + const Offset(400, 400),
          pressure: .35,
        ),
      );
      await t.sendEventToBinding(
        PointerUpEvent(
          pointer: 92,
          kind: ui.PointerDeviceKind.stylus,
          position: origin + const Offset(400, 400),
        ),
      );
      expect(edited.strokes.length, 2);
      expect(edited.strokes.last.tool, 'pen');
      await close(t);
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
