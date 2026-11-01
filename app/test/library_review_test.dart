import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:look_studio/features/library/catalog_browser.dart';
import 'package:look_studio/features/player/transcript_review.dart';

void main() {
  testWidgets(
    'course, category and format filters intersect and open exact item',
    (t) async {
      final items = <Map<String, dynamic>>[
        {
          'course_id': 'os',
          'course': '操作系统',
          'name': 'Lab 4.pdf',
          'path': 'os/Lab 4.pdf',
          'category': 'lab',
          'file_type': 'pdf',
          'bytes': 30,
        },
        {
          'course_id': 'os',
          'course': '操作系统',
          'name': 'Lab 4.docx',
          'path': 'os/Lab 4.docx',
          'category': 'lab',
          'file_type': 'docx',
          'bytes': 40,
        },
        {
          'course_id': 'os',
          'course': '操作系统',
          'name': '第一章.pdf',
          'path': 'os/第一章.pdf',
          'category': 'courseware',
          'file_type': 'pdf',
          'bytes': 50,
        },
        {
          'course_id': 'math',
          'course': '数学',
          'name': 'Lab 1.pdf',
          'path': 'math/Lab 1.pdf',
          'category': 'lab',
          'file_type': 'pdf',
          'bytes': 60,
        },
      ];
      Map<String, dynamic>? opened;
      String course = '';
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (c, set) => CatalogBrowser(
                  items: items,
                  query: '',
                  courseId: course,
                  onCourse: (v) => set(() => course = v),
                  onOpen: (v) => opened = v,
                ),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.byType(DropdownButtonFormField<String>).at(0));
      await t.pumpAndSettle();
      await t.tap(find.text('操作系统').last);
      await t.pumpAndSettle();
      await t.tap(find.byType(DropdownButtonFormField<String>).at(1));
      await t.pumpAndSettle();
      await t.tap(find.text('Lab / 实验 (2)').last);
      await t.pumpAndSettle();
      await t.tap(find.byType(DropdownButtonFormField<String>).at(2));
      await t.pumpAndSettle();
      await t.tap(find.text('PDF').last);
      await t.pumpAndSettle();
      expect(find.text('Lab 4.pdf'), findsOneWidget);
      expect(find.text('Lab 4.docx'), findsNothing);
      expect(find.text('第一章.pdf'), findsNothing);
      expect(find.text('Lab 1.pdf'), findsNothing);
      await t.tap(find.text('Lab 4.pdf'));
      expect(opened?['path'], 'os/Lab 4.pdf');
    },
  );
  for (final brightness in Brightness.values) {
    testWidgets(
      'guess is adjacent to intact original and dismisses through details in $brightness',
      (t) async {
        String? dismissed;
        await t.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Scaffold(
              body: ReviewedTranscriptText(
                text: '页表缓冲用于转换地址。',
                query: '地址',
                style: const TextStyle(fontSize: 16),
                suggestions: [
                  {
                    'id': 'a',
                    'original': '页表缓冲',
                    'guess': 'TLB',
                    'reason': '疑似术语误识别',
                    'evidence': '课堂 OCR：TLB',
                    'dismissed': false,
                  },
                ],
                onDismiss: (id) async {
                  dismissed = id;
                },
              ),
            ),
          ),
        );
        final text = t.widget<Text>(find.byType(Text).first);
        expect(text.textSpan!.toPlainText(), '页表缓冲（AI 推测：TLB）用于转换地址。');
        final spans = (text.textSpan! as TextSpan).children!
            .whereType<TextSpan>()
            .toList();
        final guess = spans.firstWhere((s) => (s.text ?? '').contains('AI 推测'));
        expect(guess.style!.fontStyle, FontStyle.italic);
        expect(guess.style!.color, isNotNull);
        await t.tap(find.text('页表缓冲 → TLB'));
        await t.pumpAndSettle();
        expect(find.textContaining('课堂 OCR：TLB'), findsOneWidget);
        await t.tap(find.text('忽略这条建议'));
        await t.pumpAndSettle();
        expect(dismissed, 'a');
      },
    );
  }
  testWidgets('review requires consent, shows progress, can cancel and hide', (
    t,
  ) async {
    final calls = <(String, String)>[];
    bool visible = true;
    var review = <String, dynamic>{'state': 'none', 'suggestions': []};
    Future<dynamic> call(String m, String p, [Object? b]) async {
      calls.add((m, p));
      if (m == 'POST')
        review = {
          'state': 'running',
          'completed': 1,
          'total': 3,
          'suggestions': [],
        };
      if (m == 'DELETE') review = {...review, 'state': 'cancelled'};
      return review;
    }

    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TranscriptReviewBar(
            lectureId: 'one',
            call: call,
            onChanged: (r, v) {
              visible = v;
            },
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('AI 审校'));
    await t.pumpAndSettle();
    expect(calls.where((c) => c.$1 == 'POST'), isEmpty);
    expect(find.textContaining('模型费用'), findsOneWidget);
    await t.tap(find.widgetWithText(FilledButton, 'AI 审校').last);
    await t.pumpAndSettle();
    expect(find.text('正在审校：1 / 3 段'), findsOneWidget);
    await t.tap(find.text('显示 AI 旁注'));
    await t.pumpAndSettle();
    expect(visible, isFalse);
    await t.tap(find.text('取消审校'));
    await t.pumpAndSettle();
    expect(calls.where((c) => c.$1 == 'DELETE').length, 1);
    await t.pumpWidget(const SizedBox.shrink());
  });
}
