import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:look_studio/features/nas/nas_page.dart';

class FakeNas {
  FakeNas({this.online = true});
  bool online;
  final calls = <(String, String)>[];
  Future<dynamic> call(String method, String path, [Object? body]) async {
    calls.add((method, path));
    if (method == 'POST') return {'state': 'accepted', 'message': '已接受请求'};
    if (path.endsWith('/text')) {
      return {'text': '课堂依据与报告正文', 'truncated': false};
    }
    return {
      'online': online,
      'observed_at': '2026-10-24T01:00:00Z',
      'course_links': {},
      'jobs': [
        {
          'course': 'CS 操作系统',
          'name': 'Lab3',
          'generation_state': 'ready',
          'submission_state': 'unconfirmed',
          'reports': [
            {
              'id': 'report',
              'path': 'CS 操作系统/4.课程作业/Lab3/报告.md',
              'available': true,
            },
          ],
        },
      ],
      'files': [
        {
          'id': 'report',
          'path': 'CS 操作系统/4.课程作业/Lab3/报告.md',
          'course': 'CS 操作系统',
          'size': 123,
          'modified': '2026-10-24',
        },
      ],
      'deadlines': [],
      'services': [
        {
          'id': 'homework',
          'active': 'inactive',
          'result': 'success',
          'health': {},
        },
      ],
    };
  }
}

void main() {
  testWidgets(
    'reading and refreshing never starts work; generation is separate from submission',
    (t) async {
      final f = FakeNas();
      await t.pumpWidget(MaterialApp(home: NasPage(call: f.call)));
      await t.pumpAndSettle();
      expect(find.text('已生成，待检查 · 提交待确认'), findsOneWidget);
      await t.tap(find.byTooltip('刷新状态'));
      await t.pumpAndSettle();
      await t.tap(find.text('报告.md'));
      await t.pumpAndSettle();
      expect(find.text('课堂依据与报告正文'), findsOneWidget);
      expect(f.calls.every((c) => c.$1 == 'GET'), isTrue);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
  for (final action in ['homework', 'calendar']) {
    testWidgets('$action requires confirmation and dispatches once', (t) async {
      final f = FakeNas();
      await t.pumpWidget(
        MaterialApp(home: NasPage(call: f.call, initialTab: 3)),
      );
      await t.pumpAndSettle();
      final label = action == 'homework' ? '运行一轮作业任务' : '刷新 NAS 日历';
      await t.tap(find.text(label));
      await t.pumpAndSettle();
      expect(f.calls.where((c) => c.$1 == 'POST'), isEmpty);
      await t.tap(find.text('取消'));
      await t.pumpAndSettle();
      expect(f.calls.where((c) => c.$1 == 'POST'), isEmpty);
      await t.tap(find.text(label));
      await t.pumpAndSettle();
      await t.tap(find.text('开始运行'));
      await t.pumpAndSettle();
      expect(f.calls.where((c) => c.$1 == 'POST').toList(), [
        ('POST', '/api/nas/actions/$action'),
      ]);
      await t.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets('offline services cannot run; narrow screen has no overflow', (
    t,
  ) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final f = FakeNas(online: false);
    await t.pumpWidget(MaterialApp(home: NasPage(call: f.call, initialTab: 3)));
    await t.pumpAndSettle();
    expect(
      t
          .widget<FilledButton>(find.widgetWithText(FilledButton, '运行一轮作业任务'))
          .onPressed,
      isNull,
    );
    expect(
      t
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, '刷新 NAS 日历'),
          )
          .onPressed,
      isNull,
    );
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
  });
}
