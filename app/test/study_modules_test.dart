import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

void main() {
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
