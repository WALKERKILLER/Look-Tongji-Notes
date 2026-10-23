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

  final now = DateTime(2026, 10, 14, 10); // Wednesday
  int ms(DateTime d) => d.millisecondsSinceEpoch;
  final yesterday = DateTime(2026, 10, 13, 21, 30);

  Map<String, dynamic> nightly() => {
        'id': 't1',
        'name': '每晚复盘',
        'prompt': '复盘今天的课',
        'schedule': {'type': 'daily', 'time': '21:30'},
        'enabled': true,
        'state': 'idle',
        'budget_usd': 0.2,
        'catch_up': true,
        'next_run': ms(DateTime(2026, 10, 14, 21, 30)),
        'last_run': {'status': 'budget', 'started': ms(yesterday), 'cost': 0.21},
      };
  Map<String, dynamic> morning() => {
        'id': 't2',
        'name': '早间截止',
        'prompt': '汇总截止',
        'schedule': {'type': 'weekly', 'days': [1, 2, 3, 4, 5], 'time': '08:00'},
        'enabled': false,
        'state': 'idle',
        'next_run': null,
        'last_run': null,
      };
  List<Map<String, dynamic>> history() => [
        {'task_id': 't2', 'name': '早间截止', 'status': 'skipped', 'started': ms(DateTime(2026, 10, 14, 9)), 'finished': ms(DateTime(2026, 10, 14, 9)), 'summary': '错过了 10-14 08:00 的运行（应用当时未运行）'},
        {'task_id': 't1', 'name': '每晚复盘', 'status': 'budget', 'started': ms(yesterday), 'finished': ms(yesterday) + 40000, 'cost': 0.21, 'summary': '超出预算'},
        {'task_id': 'gone', 'name': '旧任务', 'deleted': true, 'status': 'ok', 'started': ms(DateTime(2026, 10, 13, 8)), 'finished': ms(DateTime(2026, 10, 13, 8, 1)), 'cost': 0.01},
      ];

  Future<List<(String, String, Object?)>> pumpPage(WidgetTester tester, Size size, List<Map<String, dynamic>> tasks, List<Map<String, dynamic>> runs) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final calls = <(String, String, Object?)>[];
    Future<dynamic> api(String method, String path, [Object? body]) async {
      calls.add((method, path, body));
      if (method != 'GET') return {'id': 't9', ...?(body as Map?)?.cast<String, dynamic>()};
      if (path.startsWith('/agent/tasks/runs')) return runs;
      final one = RegExp(r'^/agent/tasks/([^/]+)/runs$').firstMatch(path);
      if (one != null) return runs.where((r) => r['task_id'] == one[1]).toList();
      return tasks;
    }

    await tester.pumpWidget(MaterialApp(home: TasksPage(api: api, now: () => now)));
    await tester.pumpAndSettle();
    return calls;
  }

  testWidgets('wide window: list beside detail, toggle and run history', (tester) async {
    final calls = await pumpPage(tester, const Size(1200, 900), [nightly(), morning()], history());
    expect(find.text('任务 2'), findsOneWidget);
    expect(find.text('每晚复盘'), findsNWidgets(2)); // list row and detail header
    expect(find.text(r'超出费用上限 · 昨天 21:30 · $0.21'), findsOneWidget); // row
    expect(find.text('超出费用上限 · 昨天 21:30'), findsOneWidget); // detail history
    expect(find.text('只读：结果写在总结里，不改动课程库'), findsOneWidget); // a task without writes

    await tester.tap(find.text('早间截止'));
    await tester.pumpAndSettle();
    expect(find.text('汇总截止'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget); // only in the detail pane
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    final put = calls.where((c) => c.$1 == 'PUT').single;
    expect(put.$2, '/agent/tasks/t2');
    expect(put.$3, {'enabled': true});

    await tester.tap(find.descendant(of: find.byType(SegmentedButton<int>), matching: find.text('运行记录')));
    await tester.pumpAndSettle();
    expect(find.text('今天'), findsOneWidget);
    expect(find.text('昨天'), findsOneWidget);
    expect(find.text('旧任务（已删除）'), findsOneWidget);
    expect(find.textContaining('应用当时未运行'), findsOneWidget); // why a run was skipped
    await tester.tap(find.text('失败'));
    await tester.pumpAndSettle();
    expect(find.text('每晚复盘'), findsOneWidget);
    expect(find.text('早间截止'), findsNothing);
  });

  testWidgets('narrow window: cards with switches open a detail page', (tester) async {
    final calls = await pumpPage(tester, const Size(500, 900), [nightly(), morning()], history());
    expect(find.text('每天 21:30 · 下次 今天 21:30'), findsOneWidget);
    expect(find.text('工作日 08:00 · 已暂停'), findsOneWidget);
    expect(find.byType(Switch), findsNWidgets(2));
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.$1 == 'PUT').single.$3, {'enabled': false});

    await tester.tap(find.text('每晚复盘'));
    await tester.pumpAndSettle();
    expect(find.byType(BackButton), findsOneWidget);
    expect(find.text('任务内容'), findsOneWidget);
  });

  testWidgets('empty tab offers templates; the editor saves weekly and workday schedules', (tester) async {
    final calls = await pumpPage(tester, const Size(1000, 1000), [], []);
    expect(find.text('每晚复盘今天的课'), findsOneWidget);
    await tester.tap(find.text('每周一出一组复习题'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('周五'));
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    var body = calls.where((c) => c.$1 == 'POST').single.$3 as Map;
    expect(body['name'], '每周一出一组复习题');
    expect(body['schedule'], {'type': 'weekly', 'days': [1, 5], 'time': '08:00'});
    expect(body['catch_up'], true);
    expect(body['writes'], ['quiz']); // the template allows only what it produces
    expect(find.text('新建定时任务'), findsNothing); // dialog closed

    await tester.tap(find.text('新建任务'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(Dialog), matching: find.text('每晚复盘今天的课')));
    await tester.pump();
    await tester.tap(find.text('工作日'));
    await tester.pump();
    await tester.ensureVisible(find.text('标记与修改日程'));
    await tester.tap(find.text('标记与修改日程'));
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    body = calls.where((c) => c.$1 == 'POST').last.$3 as Map;
    expect(body['schedule'], {'type': 'weekly', 'days': [1, 2, 3, 4, 5], 'time': '21:30'});
    expect(body['writes'], ['notes', 'schedule']);
  });
}
