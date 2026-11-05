import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/features/study_canvas/study_document.dart';
import 'study_canvas_ui_test.dart' as fixture;
import 'study_handwriting_test.dart' show sheet, stroke, close;
import 'study_pdf_column_test.dart' as pdf;

void main() {
  testWidgets(
    'hold static material selects and drags without panning or losing ink',
    (t) async {
      for (final kind in [
        ui.PointerDeviceKind.touch,
        ui.PointerDeviceKind.mouse,
      ]) {
        final d = sheet()..cards.add(pdf.pdf());
        d.strokes.add(pdf.ink('pdf', 2, const Offset(300, 350)));
        final api = pdf.PDFApi(d.json());
        final key = await fixture.open(t, api);
        final actual = key.currentState!.document!;
        final before = actual.cards.single.rect;
        final origin = t.getTopLeft(find.byKey(const ValueKey('study-input')));
        final g = await t.startGesture(
          origin + const Offset(300, 350),
          kind: kind,
        );
        await t.pump(const Duration(milliseconds: 700));
        await g.moveBy(const Offset(2, 2));
        await t.pump(const Duration(milliseconds: 110));
        expect(actual.camera, Offset.zero);
        await g.moveBy(const Offset(80, 40));
        await g.up();
        await t.pumpAndSettle();
        expect(actual.cards.single.rect, before.shift(const Offset(80, 40)));
        expect(actual.camera, Offset.zero);
        expect(actual.strokes.single.points.single.p, const Offset(380, 390));
        actual.undo();
        expect(actual.cards.single.rect, before);
        expect(actual.strokes.single.points.single.p, const Offset(300, 350));
        await close(t);
      }
    },
  );

  testWidgets('finger holds video and PDF bodies with hand or pen selected', (
    t,
  ) async {
    for (final type in ['lecture', 'pdfdoc']) {
      for (final tool in ['hand', 'pen']) {
        final d = sheet()
          ..cards.add(StudyCard.fromJson({...pdf.pdf().json(), 'type': type}));
        final key = await fixture.open(t, pdf.PDFApi(d.json()));
        await t.tap(find.byKey(ValueKey('study-tool-$tool')));
        await t.pumpAndSettle();
        final actual = key.currentState!.document!;
        final before = actual.cards.single.rect, camera = actual.camera;
        final origin = t.getTopLeft(find.byKey(const ValueKey('study-input')));
        final g = await t.startGesture(origin + before.center);
        await t.pump(const Duration(milliseconds: 810));
        await g.moveBy(const Offset(60, 40));
        await g.up();
        await t.pumpAndSettle();
        expect(actual.cards.single.rect, before.shift(const Offset(60, 40)));
        expect(actual.camera, camera);
        expect(actual.strokes, isEmpty);
        actual.undo();
        expect(actual.cards.single.rect, before);
        await close(t);
      }
    }
  });

  testWidgets('moving early or adding a second finger cancels material hold', (
    t,
  ) async {
    final d = sheet()..cards.add(pdf.pdf());
    final key = await fixture.open(t, pdf.PDFApi(d.json()));
    final actual = key.currentState!.document!;
    final before = actual.cards.single.rect;
    final origin = t.getTopLeft(find.byKey(const ValueKey('study-input')));
    var g = await t.startGesture(origin + const Offset(300, 350));
    await t.pump(const Duration(milliseconds: 700));
    await g.moveBy(const Offset(50, 30));
    await t.pump(const Duration(milliseconds: 900));
    await g.moveBy(const Offset(50, 30));
    await g.up();
    await t.pumpAndSettle();
    expect(actual.camera, const Offset(100, 60));
    expect(actual.cards.single.rect, before);
    g = await t.startGesture(
      origin + actual.camera + const Offset(250, 350),
      pointer: 21,
    );
    final second = await t.startGesture(
      origin + actual.camera + const Offset(400, 350),
      pointer: 22,
    );
    await t.pump(const Duration(milliseconds: 900));
    await second.moveBy(const Offset(70, 0));
    await t.pump();
    expect(actual.zoom, greaterThan(1));
    expect(actual.cards.single.rect, before);
    await g.up();
    await second.up();
    await close(t);
  });
  testWidgets('material title grips move cards at normal and reduced zoom', (
    t,
  ) async {
    for (final type in ['lecture', 'pdfdoc']) {
      for (final zoom in [1.0, .42]) {
        final d = sheet()..zoom = zoom;
        final card = StudyCard.fromJson({...pdf.pdf().json(), 'type': type});
        card.rect = const Rect.fromLTWH(500, 500, 600, 472);
        d.cards.add(card);
        final key = await fixture.open(t, pdf.PDFApi(d.json()));
        final actual = key.currentState!.document!;
        final before = actual.cards.single.rect, camera = actual.camera;
        final origin = t.getTopLeft(find.byKey(const ValueKey('study-input')));
        final grip =
            origin + camera + Offset(before.right - 16, before.top + 18) * zoom;
        final g = await t.startGesture(
          grip,
          kind: zoom == 1
              ? ui.PointerDeviceKind.touch
              : ui.PointerDeviceKind.mouse,
        );
        if (zoom == 1) await t.pump(const Duration(milliseconds: 810));
        await g.moveBy(const Offset(60, 30));
        await g.up();
        await t.pumpAndSettle();
        expect(
          actual.cards.single.rect.left,
          closeTo(before.left + 60 / zoom, .01),
          reason: '$type at $zoom',
        );
        expect(
          actual.cards.single.rect.top,
          closeTo(before.top + 30 / zoom, .01),
        );
        expect(actual.camera, camera);
        actual.undo();
        expect(actual.cards.single.rect, before);
        await close(t);
      }
    }
  });
  testWidgets(
    'a finger pans from the title and only a stationary hold moves the card',
    (t) async {
      final d = sheet()..cards.add(pdf.pdf());
      final key = await fixture.open(t, pdf.PDFApi(d.json()));
      final actual = key.currentState!.document!;
      final before = actual.cards.single.rect;
      final origin = t.getTopLeft(find.byKey(const ValueKey('study-input')));
      final grip = origin + before.topLeft + const Offset(80, 18);
      await t.dragFrom(grip, const Offset(60, 30));
      await t.pumpAndSettle();
      expect(actual.camera, const Offset(60, 30));
      expect(actual.cards.single.rect, before);
      await close(t);
    },
  );

  for (final type in ['lecture', 'pdfdoc', 'image']) {
    testWidgets(
      'stylus moves $type only after enclosing it with the selection tool',
      (t) async {
        final card = StudyCard.fromJson({...pdf.pdf().json(), 'type': type})
          ..rect = const Rect.fromLTWH(300, 300, 400, 300);
        final d = sheet()..cards.add(card);
        final key = await fixture.open(t, pdf.PDFApi(d.json()));
        final actual = key.currentState!.document!;
        final before = actual.cards.single.rect;
        final origin = t.getTopLeft(find.byKey(const ValueKey('study-input')));
        var g = await t.startGesture(
          origin + before.topLeft + const Offset(80, 18),
          kind: ui.PointerDeviceKind.stylus,
        );
        await t.pump(const Duration(milliseconds: 850));
        await g.moveBy(const Offset(50, 30));
        await g.up();
        await t.pumpAndSettle();
        expect(
          actual.cards.single.rect,
          before,
          reason: 'a title hit or a hold with the pen is not a selection',
        );
        await t.tap(find.byKey(const ValueKey('study-tool-pen')));
        await t.pumpAndSettle();
        await t.dragFrom(
          origin + before.center,
          const Offset(40, 20),
          kind: ui.PointerDeviceKind.stylus,
        );
        await t.pumpAndSettle();
        expect(actual.cards.single.rect, before);
        expect(actual.strokes, isNotEmpty);
        final inkBefore = actual.strokes.last.points.first.p;
        await t.tap(find.byKey(const ValueKey('study-tool-region')));
        await t.pumpAndSettle();
        await t.tap(find.byTooltip('矩形框选'));
        await t.pumpAndSettle();
        g = await t.startGesture(
          origin + before.topLeft - const Offset(20, 20),
          kind: ui.PointerDeviceKind.stylus,
        );
        await g.moveTo(origin + before.bottomRight + const Offset(20, 20));
        await g.up();
        await t.pumpAndSettle();
        await t.dragFrom(
          origin + before.center,
          const Offset(60, 30),
          kind: ui.PointerDeviceKind.stylus,
        );
        await t.pumpAndSettle();
        expect(actual.cards.single.rect, before.shift(const Offset(60, 30)));
        expect(
          actual.strokes.last.points.first.p,
          inkBefore + const Offset(60, 30),
        );
        actual.undo();
        expect(actual.cards.single.rect, before);
        expect(actual.strokes.last.points.first.p, inkBefore);
        await close(t);
      },
    );
  }

  for (final mode in ['partial', 'stroke', 'lasso']) {
    for (final trigger in ['pressure', 'button', 'inverted']) {
      testWidgets('$trigger respects $mode and restores pen after lift', (
        t,
      ) async {
        SharedPreferences.setMockInitialValues({
          'study.brush-presets.v1': jsonEncode({
            'presets': [
              {'name': '钢笔'},
            ],
            'eraser_mode': mode,
          }),
        });
        final d = sheet()..strokes.add(stroke('original'));
        final api = fixture.FixtureApi(d.json());
        final key = await fixture.open(t, api, resetPreferences: false);
        await t.tap(find.byKey(const ValueKey('study-tool-pen')));
        await t.pumpAndSettle();
        final origin = t.getTopLeft(find.byKey(const ValueKey('study-input')));
        final kind = trigger == 'inverted'
            ? ui.PointerDeviceKind.invertedStylus
            : ui.PointerDeviceKind.stylus;
        final point =
            origin +
            (mode == 'lasso' ? const Offset(275, 320) : const Offset(400, 350));
        await t.sendEventToBinding(
          PointerDownEvent(
            pointer: 91,
            kind: kind,
            position: point,
            buttons: trigger == 'button' ? kPrimaryStylusButton : 0,
            pressure: trigger == 'pressure' ? .95 : .35,
            pressureMin: 0,
            pressureMax: 1,
          ),
        );
        await t.pump(const Duration(milliseconds: 400));
        if (mode == 'lasso') {
          expect(key.currentState!.document!.strokes.single.id, 'original');
          for (final corner in [
            const Offset(530, 320),
            const Offset(530, 390),
            const Offset(275, 390),
            const Offset(275, 320),
          ]) {
            await t.sendEventToBinding(
              PointerMoveEvent(
                pointer: 91,
                kind: kind,
                position: origin + corner,
              ),
            );
            await t.pump();
          }
        }
        await t.sendEventToBinding(
          PointerUpEvent(pointer: 91, kind: kind, position: point),
        );
        await t.pumpAndSettle();
        final actual = key.currentState!.document!;
        if (mode != 'partial') {
          expect(actual.strokes, isEmpty);
        } else {
          expect(actual.strokes.length, 2);
          expect(
            actual.strokes
                .expand((s) => s.points)
                .any((p) => (p.p.dx - 400).abs() < 15),
            false,
          );
        }
        actual.undo();
        expect(actual.strokes.single.id, 'original');
        await t.dragFrom(
          origin + const Offset(600, 450),
          const Offset(50, 20),
          kind: ui.PointerDeviceKind.stylus,
        );
        await t.pumpAndSettle();
        expect(actual.strokes.any((s) => s.points.first.p.dx >= 600), true);
        await key.currentState!.flush();
        expect(
          StudyDocument.fromJson(api.doc).strokes.length,
          actual.strokes.length,
        );
        await close(t);
      });
    }
  }
  for (final type in ['pdfdoc', 'pdf', 'image']) {
    for (final kind in [
      ui.PointerDeviceKind.touch,
      ui.PointerDeviceKind.mouse,
    ]) {
      testWidgets('$kind drags canvas from $type without moving material', (
        t,
      ) async {
        final d = sheet();
        final card = StudyCard.fromJson({...pdf.pdf().json(), 'type': type});
        d.cards.add(card);
        final key = await fixture.open(t, pdf.PDFApi(d.json()));
        final actual = key.currentState!.document!;
        final before = actual.cards.single.rect;
        final origin = t.getTopLeft(find.byKey(const ValueKey('study-input')));
        await t.dragFrom(
          origin + const Offset(320, 350),
          const Offset(100, 60),
          kind: kind,
        );
        await t.pumpAndSettle();
        expect(actual.camera, const Offset(100, 60));
        expect(actual.cards.single.rect, before);
        expect(actual.strokes, isEmpty);
        await close(t);
      });
    }
  }
  testWidgets(
    'PDF pinch, paging and header drag retain text without selection UI',
    (t) async {
      final d = sheet()..cards.add(pdf.pdf());
      final api = pdf.PDFApi(d.json());
      final key = await fixture.open(t, api);
      final actual = key.currentState!.document!;
      final origin = t.getTopLeft(find.byKey(const ValueKey('study-input')));
      final first = await t.startGesture(
        origin + const Offset(200, 350),
        pointer: 51,
      );
      final second = await t.startGesture(
        origin + const Offset(400, 350),
        pointer: 52,
      );
      await second.moveBy(const Offset(100, 0));
      await t.pump();
      expect(actual.zoom, closeTo(1.5, .01));
      await first.up();
      await second.up();
      await t.pumpAndSettle();
      expect(find.text('选择文字'), findsNothing);
      expect(find.byTooltip('选择文档文字'), findsNothing);
      final camera = actual.camera;
      await t.tap(find.byTooltip('下一页'));
      await t.pumpAndSettle();
      expect(actual.cards.single.page, 3);
      expect(actual.cards.single.text, 'Page 3');
      expect(actual.camera, camera);
      await key.currentState!.flush();
      expect(StudyDocument.fromJson(api.doc).cards.single.text, 'Page 3');
      final before = actual.cards.single.rect;
      final header =
          origin +
          actual.camera +
          (before.topLeft + const Offset(100, 18)) * actual.zoom;
      await t.dragFrom(
        header,
        const Offset(60, 30),
        kind: ui.PointerDeviceKind.mouse,
      );
      await t.pumpAndSettle();
      expect(actual.cards.single.rect.left, closeTo(before.left + 40, .01));
      expect(actual.camera, camera);
      await close(t);
    },
  );
}
