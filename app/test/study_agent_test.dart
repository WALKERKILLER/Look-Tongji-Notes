import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import '../lib/features/study_canvas/study_document.dart';

StudyDocument base() {
  final d = StudyDocument();
  d.cards.add(
    StudyCard(
      id: 'pdf',
      type: 'text',
      layer: 'main',
      rect: const Rect.fromLTWH(0, 0, 500, 700),
      text: '前😀后选中内容',
      title: '实验要求',
    ),
  );
  return d;
}

Map<String, dynamic> batch() => {
  'id': 'run',
  'editable_ids': <String>[],
  'sources': [
    {
      'id': 'selected',
      'workspace_id': 'lecture-id',
      'object_id': 'pdf',
      'kind': 'pdf',
      'document_id': 'original-doc',
      'page': 3,
      'start': 3,
      'end': 6,
      'quote': '后选中',
      'region': [.1, .2, .3, .4],
    },
  ],
  'operations': [
    {
      'op': 'create',
      'id': 'one',
      'kind': 'explanation',
      'title': '解释',
      'blocks': [
        {'type': 'paragraph', 'text': '基于所选内容的说明'},
      ],
      'source_ids': ['selected'],
    },
    {
      'op': 'create',
      'id': 'two',
      'kind': 'practice',
      'title': '自测',
      'blocks': [
        {
          'type': 'exercise',
          'text': '请比较两种情况',
          'hint': '从访问路径入手',
          'answer': '答案与解释',
        },
      ],
      'source_ids': ['selected'],
    },
    {
      'op': 'connect',
      'id': 'link',
      'from': 'one',
      'to': 'two',
      'label': '理解后自测',
    },
  ],
};

void main() {
  test('agent batch creates nonoverlapping editable objects and one persistent undo transaction', () {
    final d = base();
    final ids = d.applyAgentBatch(
      batch(),
      d.edit,
      const Rect.fromLTWH(0, 0, 1000, 700),
    );
    expect(ids, ['one', 'two']);
    expect(d.cards[1].rect.overlaps(d.cards.first.rect), false);
    expect(d.cards[1].rect.overlaps(d.cards[2].rect), false);
    final anchor = d.cards[1].sources.single.json();
    d.transformCards(
      {'pdf'},
      d.cards.first.rect,
      d.cards.first.rect.shift(const Offset(800, 100)),
    );
    expect(d.cards[1].sources.single.json(), anchor);
    final reopened = StudyDocument.fromJson(d.json());
    expect(reopened.connections.single.label, '理解后自测');
    expect(reopened.cards[2].blocks.single.answer, '答案与解释');
    expect(reopened.cards[1].sources.single.page, 3);
    d.undo();
    expect(d.cards.length, 1);
    expect(d.connections, isEmpty);
    d.redo();
    expect(d.cards.length, 3);
    expect(d.connections.length, 1);
  });
  test('invalid later operation never partially applies earlier creation', () {
    final d = base(), result = batch();
    (result['operations'] as List)[1]['source_ids'] = ['fabricated'];
    expect(
      () => d.applyAgentBatch(result, 0, const Rect.fromLTWH(0, 0, 1000, 700)),
      throwsFormatException,
    );
    expect(d.cards.length, 1);
    expect(d.canUndo, false);
    expect(d.connections, isEmpty);
  });
  test('existing card edits need preview approval and stale runs cannot overwrite user work', () {
    final d = base();
    d.applyAgentBatch(batch(), 0, const Rect.fromLTWH(0, 0, 1000, 700));
    final expected = d.edit;
    final update = batch()
      ..['id'] = 'update-run'
      ..['editable_ids'] = ['one']
      ..['operations'] = [
        {
          'op': 'update',
          'object_id': 'one',
          'title': '简化解释',
          'blocks': [
            {
              'type': 'steps',
              'items': ['第一步', '第二步'],
            },
          ],
          'source_ids': ['selected'],
        },
      ];
    expect(
      () => d.applyAgentBatch(
        update,
        expected,
        const Rect.fromLTWH(0, 0, 1000, 700),
      ),
      throwsFormatException,
    );
    expect(d.cards[1].title, '解释');
    d.applyAgentBatch(
      update,
      expected,
      const Rect.fromLTWH(0, 0, 1000, 700),
      allowUpdates: true,
    );
    expect(d.cards[1].title, '简化解释');
    d.undo();
    expect(d.cards[1].title, '解释');
    expect(
      () => d.applyAgentBatch(
        batch()..['id'] = 'stale-run',
        expected,
        const Rect.fromLTWH(0, 0, 1000, 700),
      ),
      throwsFormatException,
    );
  });
  test(
    'whole eraser follows physical gesture across render chunks after reopen',
    () {
      final d = StudyDocument();
      d.addStroke(
        StudyStroke(
          id: 'long',
          layer: 'main',
          points: [
            for (var i = 0; i <= 200; i++)
              InkPoint(Offset(i.toDouble(), 50), .7),
          ],
          color: 0xff111111,
          width: 3,
          brush: const StudyBrush(family: 'pencil', opacity: .6, pressure: .8),
        ),
      );
      final reopened = StudyDocument.fromJson(d.json());
      expect(reopened.strokes.length, 4);
      expect(reopened.strokes.map((s) => s.gesture).toSet(), {'long'});
      reopened.checkpoint();
      expect(
        reopened.eraseWhole(const Offset(100, 0), const Offset(100, 100), 5),
        true,
      );
      expect(reopened.strokes, isEmpty);
      reopened.undo();
      expect(reopened.strokes.length, 4);
      expect(reopened.strokes.first.brush!.opacity, .6);
    },
  );
  test('brush opacity affects actual raster output and uniform pens ignore pressure', () async {
    final recorder = PictureRecorder();
    paintInk(
      Canvas(recorder),
      [const InkPoint(Offset(10, 50), .9), const InkPoint(Offset(90, 50), .9)],
      0xff000000,
      10,
      'pen',
      brush: const StudyBrush(family: 'ballpoint', opacity: .25),
    );
    final picture = recorder.endRecording(),
        image = await recorderImage(picture);
    final data = await image.toByteData(format: ImageByteFormat.rawRgba);
    expect(data!.getUint8((50 * 100 + 50) * 4 + 3), closeTo(64, 2));
    image.dispose();
    picture.dispose();
    const pen = StudyBrush(family: 'ballpoint', pressure: 1);
    expect(pen.radiusScale(.1), pen.radiusScale(1));
    const fountain = StudyBrush(pressure: 1);
    expect(fountain.radiusScale(.1), lessThan(fountain.radiusScale(1)));
  });
}

Future<Image> recorderImage(Picture p) => p.toImage(100, 100);
