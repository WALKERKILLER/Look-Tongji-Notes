import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/core/models.dart';
import '../lib/features/study_canvas/study_canvas.dart';
import '../lib/features/study_canvas/study_document.dart';
import 'study_canvas_ui_test.dart' as fixture;

class AnswerApi extends fixture.FixtureApi {
  AnswerApi(super.doc);
  @override
  Future<dynamic> canvasRun(String id) async => {
    'id': id,
    'state': 'done',
    'answer': 'Model transport fixture answer',
    'context_key': 'scope',
    'operations': [
      {
        'op': 'create',
        'id': 'forbidden',
        'kind': 'note',
        'title': 'Unexpected card',
        'blocks': [
          {'type': 'paragraph', 'text': 'must not apply'},
        ],
        'source_ids': [],
      },
    ],
    'sources': [],
    'editable_ids': [],
    'trace': [],
  };
}

/// A lecture with three subtitle lines, one chapter and one note.
class ShelfPlayer extends fixture.FixturePlayer {
  @override
  final segments = [
    for (final (i, t) in ['缓存命中更快', '未命中要访问主存', '局部性原理'].indexed)
      Segment({'idx': i, 'start_ms': i * 4000, 'end_ms': i * 4000 + 3500, 'text': t}),
  ];
  @override
  final chapters = [
    Chapter({'idx': 0, 'start_ms': 0, 'end_ms': 12000, 'title': '存储层次'}),
  ];
  @override
  final notes = <Note>[];
  int? sought;
  @override
  int segmentAt(int ms) => segments.lastIndexWhere((s) => s.startMs <= ms);
  @override
  void seekTo(int ms) => sought = ms;
}

void main() {
  test('note Markdown becomes headings, lists, code and paragraphs', () {
    final blocks = studyBlocksFromMarkdown(
      '# 缓存\n命中率高。\n\n- 时间局部性\n- 空间局部性\n\n1. 查标签\n2. 比较\n\n```c\nint x;\n```',
    );
    expect(blocks.map((b) => b.type), ['heading', 'paragraph', 'list', 'steps', 'code']);
    expect(blocks[2].items, ['时间局部性', '空间局部性']);
    expect(blocks[4].language, 'c');
    expect(studyBlocksFromMarkdown(List.filled(40, '段落').join('\n\n')).length, 32);
  });

  testWidgets('subtitles drag from the shelf onto the canvas as cited cards', (
    t,
  ) async {
    final api = AnswerApi(StudyDocument().json());
    final player = ShelfPlayer();
    final key = await fixture.open(t, api, player: player);
    await t.tap(find.byKey(const ValueKey('study-open-shelf')));
    await t.pumpAndSettle();
    expect(find.text('存储层次'), findsOneWidget);
    // Tapping a line seeks; ＋ places it in view.
    await t.tap(find.text('未命中要访问主存'));
    expect(player.sought, 4000);
    await t.tap(find.byTooltip('放到画布').at(1));
    await t.pumpAndSettle();
    final cards = key.currentState!.document!.cards;
    final placed = cards.singleWhere((c) => c.type == 'note');
    expect(placed.blocks.single.text, contains('缓存命中更快'));
    expect(placed.sources.single.kind, 'video');
    expect(placed.sources.single.objectId, 'lecture');
    // A chapter drags sideways out of the shelf and lands where it drops.
    final chapter = t.getCenter(find.text('存储层次'));
    final gesture = await t.startGesture(chapter);
    await gesture.moveBy(const Offset(40, 0));
    await t.pump();
    await gesture.moveTo(const Offset(900, 500));
    await t.pump();
    expect(find.byType(CustomPaint), findsWidgets);
    await gesture.up();
    await t.pumpAndSettle();
    final chapterCard = key.currentState!.document!.cards.lastWhere(
      (c) => c.type == 'note',
    );
    expect(chapterCard, isNot(same(placed)));
    expect(chapterCard.blocks.single.text.split('\n'), hasLength(3));
    final d = key.currentState!.document!;
    final world = (const Offset(900, 500) - d.camera) / d.zoom;
    expect((chapterCard.rect.center - world).distance, lessThan(80));
    await t.tap(find.byKey(const ValueKey('study-shelf-threads')));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('放到画布').first);
    await t.pumpAndSettle();
    expect(d.cards.where((c) => c.type == 'conversation'), hasLength(1));
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
  });

  testWidgets(
    'independent conversation modules persist drafts; ordinary answers are not errors',
    (t) async {
      final api = AnswerApi(StudyDocument().json());
      final key = await fixture.open(t, api);
      expect(find.byTooltip('课程资料'), findsOneWidget);
      await t.tap(find.byTooltip('添加模块'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(PopupMenuItem<String>, 'AI 对话'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).last, 'first draft');
      await t.pump(const Duration(seconds: 1));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('添加模块'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(PopupMenuItem<String>, 'AI 对话'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).last, 'second question');
      await t.tap(find.byTooltip('发送').last);
      await t.pumpAndSettle();
      expect(
        find.textContaining(
          'Model transport fixture answer',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(
        key.currentState!.document!.cards
            .where((c) => c.type == 'conversation')
            .length,
        2,
      );
      expect(api.request!['selection']['include_video'], false);
      expect(
        key.currentState!.document!.cards.any((c) => c.id == 'forbidden'),
        false,
      );
      expect(find.text('预览并应用画布操作'), findsNothing);
      expect(
        api.conversations.values.any((c) => c['draft'] == 'first draft'),
        true,
      );
      expect(
        api.conversations.values.any(
          (c) => (c['turns'] as List).any((v) => v['state'] == 'done'),
        ),
        true,
      );
      await key.currentState!.flush();
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      for (final conversation in api.conversations.values) {
        for (final turn in conversation['turns'] as List) {
          turn['state'] = 'pending';
          turn['result'] = {
            'operations': [
              {'op': 'create', 'id': 'legacy-card'},
            ],
            'sources': [],
          };
        }
      }
      final reopened = await fixture.open(t, api);
      await t.pumpAndSettle();
      expect(find.text('预览并应用画布操作'), findsNothing);
      expect(find.text('历史画布操作已停用，回答仍保留在对话中。'), findsOneWidget);
      expect(
        reopened.currentState!.document!.cards.any(
          (c) => c.id == 'legacy-card',
        ),
        false,
      );
      expect(
        find.textContaining(
          'Model transport fixture answer',
          findRichText: true,
        ),
        findsOneWidget,
      );
      // The newest conversation is on stage; its node-mate opens from 「继续」.
      await t.tap(find.text('继续'));
      await t.pumpAndSettle();
      expect(
        t
            .widgetList<TextField>(find.byType(TextField))
            .any((v) => v.controller?.text == 'first draft'),
        true,
      );
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    },
  );
  testWidgets('the agent stage fits a phone in dark mode', (t) async {
    final api = AnswerApi(StudyDocument().json());
    await fixture.open(t, api, brightness: Brightness.dark);
    t.view.physicalSize = const Size(400, 800);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    final send = t.getRect(find.byTooltip('发送'));
    expect(send.right, lessThanOrEqualTo(400));
    expect(send.bottom, lessThanOrEqualTo(800));
    await t.enterText(find.byType(TextField).last, 'phone question');
    await t.tap(find.byTooltip('发送'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(
      find.textContaining(
        'Model transport fixture answer',
        findRichText: true,
      ),
      findsOneWidget,
    );
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
  });
  test(
    'PDF page ink and applied agent transaction IDs survive persistence',
    () {
      final d = StudyDocument()
        ..cards.add(
          StudyCard(
            id: 'pdf',
            type: 'pdfdoc',
            layer: 'main',
            rect: const Rect.fromLTWH(0, 0, 600, 800),
            page: 1,
            pageCount: 2,
          ),
        );
      final ink = StudyStroke(
        id: 'ink',
        layer: 'main',
        points: [const InkPoint(Offset(30, 30), .5)],
        color: 0xff000000,
        width: 3,
        anchor: 'pdf',
        page: 1,
      );
      d.strokes.add(ink);
      d.appliedRuns.add('run');
      expect(d.strokeVisible(ink), true);
      d.cards.first.page = 2;
      expect(d.strokeVisible(ink), false);
      expect(d.erase(const Offset(30, 30), const Offset(35, 35), 20), false);
      final reopened = StudyDocument.fromJson(d.json());
      expect(reopened.appliedRuns, contains('run'));
      expect(reopened.strokes.first.page, 1);
    },
  );
  test('unrelated drawing does not reject a result, but changed reference text does', () {
    final d = StudyDocument()
      ..cards.add(
        StudyCard(
          id: 'text',
          type: 'text',
          layer: 'main',
          rect: const Rect.fromLTWH(0, 0, 400, 300),
          text: 'original',
        ),
      );
    final stamps = {'text': d.cards.first.contentStamp};
    d.changed();
    final batch = {
      'id': 'run',
      'operations': [],
      'sources': [],
      'editable_ids': [],
    };
    expect(
      () => d.applyAgentBatch(
        batch,
        0,
        const Rect.fromLTWH(0, 0, 1000, 800),
        expectedContents: stamps,
      ),
      returnsNormally,
    );
    d.cards.first.text = 'edited';
    expect(
      () => d.applyAgentBatch(
        batch,
        0,
        const Rect.fromLTWH(0, 0, 1000, 800),
        expectedContents: stamps,
      ),
      throwsFormatException,
    );
  });
}
