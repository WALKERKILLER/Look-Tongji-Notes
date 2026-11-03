import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/features/study_canvas/study_document.dart';
import '../lib/features/study_canvas/study_shape.dart';
import 'study_canvas_ui_test.dart' as fixture;
import 'study_handwriting_test.dart' show close, saveReviewImage;

List<Offset> polygon(List<Offset> corners) => [
  for (var edge = 0; edge < corners.length; edge++)
    for (var i = 0; i < 20; i++)
      Offset.lerp(
            corners[edge],
            corners[(edge + 1) % corners.length],
            i / 20,
          )! +
          Offset(math.sin(i * 2) * .6, math.cos(i) * .5),
  corners.first,
];
List<Offset> ellipse({
  double x = 100,
  double y = 60,
  double angle = .6,
  double turns = 1,
}) => [
  for (var i = 0; i <= 100; i++)
    () {
      final a = i * math.pi * 2 * turns / 100;
      final p =
          Offset(x * math.cos(a), y * math.sin(a)) *
          (1 + .02 * math.sin(i * 3));
      return Offset(
        350 + p.dx * math.cos(angle) - p.dy * math.sin(angle),
        350 + p.dx * math.sin(angle) + p.dy * math.cos(angle),
      );
    }(),
];

Future<void> draw(
  WidgetTester t,
  List<Offset> points, {
  double pressure = .35,
}) async {
  final origin = t.getTopLeft(find.byKey(const ValueKey('study-input')));
  await t.sendEventToBinding(
    PointerDownEvent(
      pointer: 91,
      kind: ui.PointerDeviceKind.stylus,
      position: origin + points.first,
      pressure: pressure,
      pressureMin: 0,
      pressureMax: 1,
    ),
  );
  for (final p in points.skip(1)) {
    await t.sendEventToBinding(
      PointerMoveEvent(
        pointer: 91,
        kind: ui.PointerDeviceKind.stylus,
        position: origin + p,
        pressure: pressure,
        pressureMin: 0,
        pressureMax: 1,
      ),
    );
    await t.pump(const Duration(milliseconds: 10));
  }
}

Future<void> lift(WidgetTester t, Offset p, {bool cancel = false}) async {
  final origin = t.getTopLeft(find.byKey(const ValueKey('study-input')));
  await t.sendEventToBinding(
    cancel
        ? PointerCancelEvent(
            pointer: 91,
            kind: ui.PointerDeviceKind.stylus,
            position: origin + p,
          )
        : PointerUpEvent(
            pointer: 91,
            kind: ui.PointerDeviceKind.stylus,
            position: origin + p,
          ),
  );
  await t.pumpAndSettle();
}

const wavyLine = [
  Offset(250, 350),
  Offset(280, 353),
  Offset(310, 348),
  Offset(350, 352),
  Offset(390, 350),
  Offset(430, 352),
  Offset(470, 351),
];

void main() {
  test('fits noisy geometry at different zoom levels and keeps rotation', () {
    final examples = <String, List<Offset>>{
      'line': wavyLine,
      'circle': ellipse(x: 90, y: 90),
      'ellipse': ellipse(),
      'triangle': polygon([
        const Offset(300, 220),
        const Offset(410, 400),
        const Offset(200, 400),
      ]),
      'rectangle': polygon([
        const Offset(220, 250),
        const Offset(450, 270),
        const Offset(440, 400),
        const Offset(210, 380),
      ]),
      'quadrilateral': polygon([
        const Offset(250, 250),
        const Offset(390, 250),
        const Offset(450, 400),
        const Offset(180, 400),
      ]),
    };
    for (final entry in examples.entries) {
      for (final zoom in [.25, 1.0, 4.0]) {
        final shape = recognizeStudyShape(
          entry.value.map((p) => p / zoom).toList(),
          zoom: zoom,
        );
        expect(shape?.kind, entry.key, reason: '${entry.key} at zoom $zoom');
        if (entry.key != 'line') expect(shape!.points.last, shape.points.first);
      }
    }
    final fitted = recognizeStudyShape(examples['rectangle']!)!.points;
    final a = fitted[1] - fitted[0], b = fitted[2] - fitted[1];
    expect((a.dx * b.dx + a.dy * b.dy).abs(), lessThan(.001));
    expect(
      a.dy.abs(),
      greaterThan(5),
      reason: 'rotated rectangles keep their direction',
    );
  });

  test(
    'rejects dots, open arcs, spirals, repeated loops and scribbled text',
    () {
      for (final trace in [
        List.filled(20, const Offset(40, 40)),
        ellipse(x: 3, y: 3),
        ellipse(turns: .65),
        ellipse(turns: 2),
        [
          for (var i = 0; i < 90; i++)
            Offset(300 + i * math.cos(i / 8), 300 + i * math.sin(i / 8)),
        ],
        [
          const Offset(200, 200),
          const Offset(400, 210),
          const Offset(200, 240),
          const Offset(400, 260),
          const Offset(200, 300),
          const Offset(390, 330),
        ],
        polygon([
          const Offset(100, 100),
          const Offset(300, 300),
          const Offset(100, 300),
          const Offset(300, 100),
        ]),
      ]) {
        expect(recognizeStudyShape(trace), isNull);
      }
    },
  );

  test(
    'held line adjusts its endpoint; closed shapes rotate and scale as a whole',
    () {
      final line = recognizeStudyShape(wavyLine)!;
      final moved = line.adjust(wavyLine.last, const Offset(520, 420));
      expect(moved, [wavyLine.first, const Offset(520, 420)]);
      final circle = recognizeStudyShape(ellipse(x: 90, y: 90))!;
      final movedCircle = circle.adjust(
        const Offset(440, 350),
        const Offset(350, 530),
      );
      expect(
        (movedCircle[24] - movedCircle[0]).distance,
        closeTo((circle.points[24] - circle.points[0]).distance * 2, 2),
      );
    },
  );

  test(
    'single-stroke arrows and convex pentagons/hexagons fit, zigzags do not',
    () {
      final arrow = [
        const Offset(100, 200),
        const Offset(400, 200),
        const Offset(330, 145),
        const Offset(400, 200),
        const Offset(330, 255),
      ];
      final trace = [
        for (var k = 1; k < arrow.length; k++)
          for (var i = 0; i < 30; i++)
            Offset.lerp(arrow[k - 1], arrow[k], i / 30)!,
        arrow.last,
      ];
      expect(recognizeStudyShape(trace)?.kind, 'arrow');
      for (final sides in [5, 6]) {
        final corners = [
          for (var i = 0; i < sides; i++)
            Offset(
              300 + 100 * math.cos(i * 2 * math.pi / sides),
              300 + 100 * math.sin(i * 2 * math.pi / sides),
            ),
        ];
        expect(recognizeStudyShape(polygon(corners))?.kind, 'polygon');
      }
      expect(
        recognizeStudyShape([
          const Offset(100, 200),
          const Offset(400, 200),
          const Offset(330, 145),
          const Offset(450, 260),
          const Offset(500, 200),
        ]),
        isNull,
      );
    },
  );

  test('rough closed shapes tolerate gaps and uneven hand drawn sides', () {
    final rectangle = polygon([
      const Offset(200, 240),
      const Offset(440, 250),
      const Offset(430, 410),
      const Offset(210, 400),
    ]);
    final roughRectangle = [
      for (var i = 0; i < rectangle.length - 3; i++)
        rectangle[i] + Offset(6 * math.sin(i * .39), 5 * math.cos(i * .31)),
    ];
    expect(recognizeStudyShape(roughRectangle)?.kind, 'rectangle');
    // A nearly closed circle, with an intentionally visible gap at the tail.
    final circle = ellipse(x: 100, y: 96, turns: .9);
    expect(recognizeStudyShape(circle)?.kind, 'circle');
    final triangle = polygon([
      const Offset(300, 220),
      const Offset(440, 430),
      const Offset(180, 420),
    ]);
    expect(
      recognizeStudyShape([
        for (var i = 0; i < triangle.length - 2; i++)
          triangle[i] + Offset(5 * math.sin(i * .4), 4 * math.cos(i * .3)),
      ])?.kind,
      'triangle',
    );
  });

  testWidgets('heavy endpoint hold fits a closed shape without erasing ink', (
    t,
  ) async {
    final original = StudyDocument()
      ..camera = Offset.zero
      ..zoom = 1;
    final key = await fixture.open(t, fixture.FixtureApi(original.json()));
    await t.tap(find.byKey(const ValueKey('study-tool-pen')));
    await t.pumpAndSettle();
    final trace = ellipse(x: 95, y: 95, angle: 0);
    await draw(t, trace, pressure: .95);
    await t.pump(const Duration(milliseconds: 750));
    await lift(t, trace.last);
    final d = key.currentState!.document!;
    final fitted = d.strokes.expand((s) => s.points).map((p) => p.p).toList();
    expect(fitted, isNotEmpty);
    expect(
      (fitted.first - fitted.last).distance,
      lessThan(.01),
      reason: 'a heavy hold after drawing must close the circle, not erase its tail',
    );
    final saved = jsonEncode(d.strokes.map((s) => s.json()).toList());
    d.undo();
    expect(d.strokes, isNotEmpty, reason: 'first undo restores freehand');
    expect(jsonEncode(d.strokes.map((s) => s.json()).toList()), isNot(saved));
    d.undo();
    expect(d.strokes, isEmpty);
    await close(t);
  });

  testWidgets(
    'hold previews and commits geometry, saves ordinary ink, and undo restores freehand',
    (t) async {
      final original = StudyDocument()
        ..camera = Offset.zero
        ..zoom = 1;
      final api = fixture.FixtureApi(original.json()), capture = GlobalKey();
      final key = await fixture.open(t, api, capture: capture);
      await t.tap(find.byKey(const ValueKey('study-tool-pen')));
      await t.pumpAndSettle();
      await draw(t, wavyLine);
      await t.pump(const Duration(milliseconds: 750));
      expect(
        key.currentState!.document!.strokes,
        isEmpty,
        reason: 'preview is not saved until lift',
      );
      final origin = t.getTopLeft(find.byKey(const ValueKey('study-input')));
      for (final p in [wavyLine.last + const Offset(70, 60), wavyLine.last]) {
        await t.sendEventToBinding(
          PointerMoveEvent(
            pointer: 91,
            kind: ui.PointerDeviceKind.stylus,
            position: origin + p,
            pressure: .35,
          ),
        );
        await t.pump();
      }
      await saveReviewImage(t, capture, 'shape-held-line');
      await lift(t, wavyLine.last);
      final d = key.currentState!.document!;
      expect(d.strokes.single.points.length, 2);
      expect(d.strokes.single.points[0].p.dy, d.strokes.single.points[1].p.dy);
      await key.currentState!.flush();
      expect(
        StudyDocument.fromJson(api.doc).strokes.single.json(),
        d.strokes.single.json(),
      );
      d.undo();
      expect(d.strokes.expand((s) => s.points).length, greaterThan(30));
      expect(
        d.strokes.expand((s) => s.points).map((p) => p.p.dy).toSet().length,
        greaterThan(3),
      );
      d.undo();
      expect(d.strokes, isEmpty);
      await close(t);
    },
  );

  testWidgets(
    'quick lift stays freehand and pointer cancellation discards a fitted preview',
    (t) async {
      final key = await fixture.open(
        t,
        fixture.FixtureApi(
          (StudyDocument()
                ..camera = Offset.zero
                ..zoom = 1)
              .json(),
        ),
      );
      await t.tap(find.byKey(const ValueKey('study-tool-pen')));
      await t.pumpAndSettle();
      await draw(t, wavyLine);
      await lift(t, wavyLine.last);
      final before = jsonEncode(key.currentState!.document!.json());
      expect(
        key.currentState!.document!.strokes.first.points.length,
        greaterThan(2),
      );
      await draw(t, ellipse());
      await t.pump(const Duration(milliseconds: 750));
      await lift(t, ellipse().last, cancel: true);
      expect(jsonEncode(key.currentState!.document!.json()), before);
      await close(t);
    },
  );

  testWidgets(
    'per-pen switch survives reopening and disables held recognition',
    (t) async {
      final api = fixture.FixtureApi(
        (StudyDocument()
              ..camera = Offset.zero
              ..zoom = 1)
            .json(),
      );
      await fixture.open(t, api);
      await t.tap(find.byKey(const ValueKey('study-tool-pen')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('study-tool-pen')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('study-shape-assist')));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('关闭设置'));
      await close(t);
      final key = await fixture.open(t, api, resetPreferences: false);
      await t.tap(find.byKey(const ValueKey('study-tool-pen')));
      await t.pumpAndSettle();
      await draw(t, wavyLine);
      await t.pump(const Duration(milliseconds: 750));
      await lift(t, wavyLine.last);
      expect(
        key.currentState!.document!.strokes.first.points.length,
        greaterThan(2),
      );
      await close(t);
    },
  );
}
