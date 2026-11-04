import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/features/player/video_card_hold.dart';
import '../lib/features/study_canvas/study_document.dart';
import 'study_canvas_ui_test.dart' as fixture;
import 'study_handwriting_test.dart' show sheet, close;

void main() {
  testWidgets(
    'video picture pans and holds cards while playback controls keep their input',
    (t) async {
      var taps = 0, scrubs = 0;
      final d = sheet()..zoom = .6;
      d.camera = const Offset(150, 120);
      d.cards.add(
        StudyCard(
          id: 'video',
          type: 'lecture',
          layer: 'main',
          rect: const Rect.fromLTWH(300, 300, 900, 600),
          title: 'Lecture',
        ),
      );
      final key = await fixture.open(
        t,
        fixture.FixtureApi(d.json()),
        video: Stack(
          fit: StackFit.expand,
          children: [
            VideoCardHoldRegion(
              child: GestureDetector(
                key: const ValueKey('picture'),
                behavior: HitTestBehavior.opaque,
                onTap: () => taps++,
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 70,
              child: GestureDetector(
                key: const ValueKey('controls'),
                behavior: HitTestBehavior.opaque,
                onTap: () => taps++,
                onHorizontalDragUpdate: (_) => scrubs++,
                child: const ColoredBox(color: Colors.grey),
              ),
            ),
          ],
        ),
      );
      final actual = key.currentState!.document!;
      final before = actual.cards.single.rect, camera = actual.camera;
      for (final kind in [
        ui.PointerDeviceKind.touch,
        ui.PointerDeviceKind.mouse,
      ]) {
        final g = await t.startGesture(
          t.getCenter(find.byKey(const ValueKey('picture'))),
          kind: kind,
        );
        await t.pump(const Duration(milliseconds: 700));
        expect(actual.cards.single.rect, before);
        await t.pump(const Duration(milliseconds: 110));
        await g.moveBy(const Offset(60, 30));
        await g.up();
        await t.pumpAndSettle();
        expect(actual.cards.single.rect, before.shift(const Offset(100, 50)));
        expect(actual.camera, camera);
        expect(taps, 0);
        expect(scrubs, 0);
        actual.undo();
        await t.pumpAndSettle();
      }
      await t.tap(find.byKey(const ValueKey('controls')));
      await t.pumpAndSettle();
      expect(taps, 1);
      final controls = await t.startGesture(
        t.getCenter(find.byKey(const ValueKey('controls'))),
      );
      await t.pump(const Duration(milliseconds: 900));
      await controls.moveBy(const Offset(60, 0));
      await controls.moveBy(const Offset(30, 0));
      await controls.up();
      await t.pumpAndSettle();
      expect(scrubs, greaterThan(0));
      expect(actual.cards.single.rect, before);
      scrubs = 0;
      await t.drag(find.byKey(const ValueKey('picture')), const Offset(80, 0));
      await t.pumpAndSettle();
      expect(scrubs, 0);
      expect(actual.camera, camera + const Offset(80, 0));
      expect(actual.cards.single.rect, before);
      final cancel = await t.startGesture(
        t.getCenter(find.byKey(const ValueKey('picture'))),
      );
      await t.pump(const Duration(milliseconds: 900));
      await cancel.cancel();
      await t.pumpAndSettle();
      await key.currentState!.flush();
      expect(actual.cards.single.rect, before);
      final zoom = actual.zoom;
      final a = await t.startGesture(
        t.getCenter(find.byKey(const ValueKey('picture'))),
        pointer: 21,
      );
      await t.pump(const Duration(milliseconds: 850));
      final b = await t.startGesture(const Offset(1300, 700), pointer: 22);
      await b.moveBy(const Offset(100, 50));
      await t.pump();
      expect(actual.zoom, greaterThan(zoom));
      expect(actual.cards.single.rect, before);
      await a.up();
      await b.moveBy(const Offset(20, 10));
      await b.up();
      await t.pumpAndSettle();
      expect(taps, 1, reason: 'hold/pinch must not trigger a picture tap');
      expect(actual.cards.single.rect, before);
      await close(t);
    },
  );

  testWidgets(
    'an imported video reserves its playback lane from canvas gestures',
    (t) async {
      var controls = 0;
      final d = sheet()
        ..cards.add(
          StudyCard(
            id: 'lecture',
            type: 'lecture',
            layer: 'main',
            rect: const Rect.fromLTWH(250, 200, 700, 500),
          ),
        );
      final key = await fixture.open(
        t,
        fixture.FixtureApi(d.json()),
        video: VideoCardHoldRegion(
          bottomControlsHeight: 84,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(
                key: ValueKey('local-picture'),
                color: Colors.black,
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: 84,
                child: GestureDetector(
                  key: const ValueKey('local-controls'),
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (_) => controls++,
                  child: const SizedBox.expand(),
                ),
              ),
            ],
          ),
        ),
      );
      final actual = key.currentState!.document!;
      final before = actual.cards.single.rect;
      await t.drag(
        find.byKey(const ValueKey('local-controls')),
        const Offset(50, 0),
      );
      await t.pumpAndSettle();
      expect(controls, greaterThan(0));
      expect(actual.camera, Offset.zero);
      expect(actual.cards.single.rect, before);
      final count = controls;
      await t.drag(
        find.byKey(const ValueKey('local-picture')),
        const Offset(50, 30),
      );
      await t.pumpAndSettle();
      expect(actual.camera, const Offset(50, 30));
      expect(actual.cards.single.rect, before);
      expect(controls, count);
      await close(t);
    },
  );

  testWidgets('outside a canvas the picture retains its original long press', (
    t,
  ) async {
    var boosts = 0;
    await t.pumpWidget(
      MaterialApp(
        home: VideoCardHoldRegion(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPress: () => boosts++,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    await t.longPress(find.byType(GestureDetector));
    expect(boosts, 1);
  });
}
