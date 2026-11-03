import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import '../lib/features/study_canvas/study_document.dart';

StudyStroke line({String layer = 'main', String anchor = ''}) => StudyStroke(
  id: studyId(),
  layer: layer,
  anchor: anchor,
  points: [
    for (var i = 0; i <= 200; i++) InkPoint(Offset(i.toDouble(), 50), .7),
  ],
  color: 0xff111111,
  width: 3,
);
void main() {
  test('a card cannot move while an attached annotation layer is locked', () {
    final d = StudyDocument();
    final card = StudyCard(
      id: 'card',
      type: 'text',
      layer: 'main',
      rect: const Rect.fromLTWH(0, 0, 200, 100),
    );
    d.cards.add(card);
    d.layers.add(StudyLayer('annotation', '批注', locked: true));
    d.addStroke(line(layer: 'annotation', anchor: 'card'));
    d.transformCards(
      {'card'},
      card.rect,
      card.rect.shift(const Offset(50, 50)),
    );
    expect(card.rect.topLeft, Offset.zero);
    expect(d.strokes.first.points.first.p, const Offset(0, 50));
    d.layers.last
      ..locked = false
      ..visible = false;
    d.transformCards(
      {'card'},
      card.rect,
      card.rect.shift(const Offset(50, 50)),
    );
    expect(card.rect.topLeft, const Offset(50, 50));
    expect(d.strokes.first.points.first.p, const Offset(50, 100));
  });
  test('long gestures round trip as bounded chunks and undo as one action', () {
    final d = StudyDocument();
    d.addStroke(line());
    expect(d.strokes.length, 4);
    expect(d.strokes.every((s) => s.points.length <= 65), true);
    final restored = StudyDocument.fromJson(d.json());
    expect(restored.strokes.last.points.last.p, const Offset(200, 50));
    d.undo();
    expect(d.strokes, isEmpty);
    d.redo();
    expect(d.strokes.length, 4);
  });
  test(
    'eraser splits a stroke, respects locked/hidden layers and can undo',
    () {
      final d = StudyDocument();
      d.addStroke(line());
      d.checkpoint();
      expect(d.erase(const Offset(100, 0), const Offset(100, 100), 10), true);
      expect(
        d.strokes
            .expand((s) => s.points)
            .any((p) => (p.p.dx - 100).abs() <= 11),
        false,
      );
      d.undo();
      expect(d.strokes.expand((s) => s.points).any((p) => p.p.dx == 100), true);
      d.layers.first.locked = true;
      expect(d.erase(const Offset(0, 50), const Offset(200, 50), 20), false);
      d.layers.first
        ..locked = false
        ..visible = false;
      expect(d.erase(const Offset(0, 50), const Offset(200, 50), 20), false);
    },
  );
  test('card resize transforms attached ink, while AI context excludes hidden cards', () {
    final d = StudyDocument();
    d.cards.add(
      StudyCard(
        id: 'card',
        type: 'text',
        layer: 'main',
        rect: const Rect.fromLTWH(0, 0, 200, 100),
        text: '有界的课程材料',
        title: '课件',
      ),
    );
    d.addStroke(line(anchor: 'card'));
    d.checkpoint();
    d.transformCards(
      {'card'},
      const Rect.fromLTWH(0, 0, 200, 100),
      const Rect.fromLTWH(50, 50, 400, 200),
    );
    expect(d.strokes.first.points.first.p, const Offset(50, 150));
    expect(d.strokes.last.points.last.p, const Offset(450, 150));
    expect(d.contextText({'card'}), contains('有界的课程材料'));
    d.layers.first.visible = false;
    expect(d.contextText({'card'}), isNot(contains('有界的课程材料')));
  });
}
