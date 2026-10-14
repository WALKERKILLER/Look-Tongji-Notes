import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:look_studio/features/assistant/tasks_page.dart';

void main() {
  test('schedule and time wording', () {
    expect(fmtSchedule({'type': 'daily', 'time': '21:30'}), '每天 21:30');
    expect(fmtSchedule({'type': 'weekly', 'days': [1, 2, 3, 4, 5], 'time': '08:00'}), '工作日 08:00');
    expect(fmtSchedule({'type': 'weekly', 'days': [1, 5], 'time': '08:00'}), '每周一、五 08:00');
    expect(fmtSchedule({'type': 'once', 'at': '2026-10-15T07:00'}), '10月15日 07:00（一次）');
    final now = DateTime(2026, 10, 14, 10); // Wednesday
    expect(fmtWhen(DateTime(2026, 10, 14, 21, 30), now), '今天 21:30');
    expect(fmtWhen(DateTime(2026, 10, 15, 8), now), '明天 08:00');
    expect(fmtWhen(DateTime(2026, 10, 16, 8), now), '周五 08:00');
    expect(fmtWhen(DateTime(2026, 11, 2, 8), now), '11月2日 08:00');
  });

  testWidgets('list, toggle and create', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime(2026, 10, 14, 10);
    final calls = <(String, String, Object?)>[];
    var tasks = <Map<String, dynamic>>[];
    Future<dynamic> api(String method, String path, [Object? body]) async {
      calls.add((method, path, body));
      if (method == 'GET') return tasks;
      return {'id': 't9', ...?(body as Map?)?.cast<String, dynamic>()};
    }

    await tester.pumpWidget(MaterialApp(home: TasksPage(api: api, now: () => now)));
    await tester.pumpAndSettle();
    expect(find.text('每晚复盘今天的课'), findsOneWidget); // templates when empty

    tasks = [
      {
        'id': 't1',
        'name': '每晚复盘',
        'prompt': 'p',
        'schedule': {'type': 'daily', 'time': '21:30'},
        'enabled': true,
        'state': 'idle',
        'next_run': DateTime(2026, 10, 14, 21, 30).millisecondsSinceEpoch,
        'last_run': {'status': 'budget', 'started': DateTime(2026, 10, 13, 21, 30).millisecondsSinceEpoch, 'cost': 0.21},
      },
    ];
    await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();
    expect(find.text('每天 21:30 · 下次 今天 21:30'), findsOneWidget);
    expect(find.text(r'超出费用上限 · 昨天 21:30 · $0.21'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.$1 == 'PUT').single.$3, {'enabled': false});

    await tester.tap(find.text('新建任务'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('每周一出一组复习题'));
    await tester.pump();
    await tester.tap(find.text('周五'));
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    final post = calls.where((c) => c.$1 == 'POST').single;
    expect(post.$2, '/agent/tasks');
    final body = post.$3 as Map;
    expect(body['name'], '每周一出一组复习题');
    expect(body['schedule'], {'type': 'weekly', 'days': [1, 5], 'time': '08:00'});
    expect(body['catch_up'], true);
    expect(find.text('新建定时任务'), findsNothing); // dialog closed
  });
}
