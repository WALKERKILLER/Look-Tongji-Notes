import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:look_studio/core/app_state.dart';
import 'package:look_studio/core/lookd_service.dart';
import 'package:look_studio/core/models.dart';
import 'package:look_studio/features/downloads/downloads_page.dart';
import 'package:provider/provider.dart';

class _App extends AppState {
  _App() : super(LookdService());
  final bulk = <(String, List<String>?)>[];

  @override
  Future<int> bulkJobs(String action, {List<String>? ids}) async {
    bulk.add((action, ids));
    return ids?.length ?? 1;
  }
}

Job job(String id, String state, {double progress = 0, int done = 0, int total = 0, int speed = 0, int updated = 0}) => Job({
      'id': id, 'lecture_id': id, 'course_id': 'C1', 'kind': 'video', 'title': '第 $id 讲', 'state': state, //
      'progress': progress, 'done_bytes': done, 'total_bytes': total, 'speed': speed, 'updated_at': updated,
    });

/// Pumps through animations; the sweeping bar never settles.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late _App app;

  Future<void> open(WidgetTester tester, {Size size = const Size(1000, 1400), double scale = 1}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    app = _App();
    for (final j in [
      job('1', 'running', progress: 0.42, done: 420 << 20, total: 1000 << 20, speed: 5 << 20, updated: 3),
      job('2', 'running', updated: 2),
      job('3', 'queued', updated: 1),
      job('4', 'paused', progress: 0.3, done: 30 << 20, total: 100 << 20),
      job('5', 'failed'),
      job('6', 'done', total: 10 << 20),
    ]) {
      app.jobs[j.id] = j;
    }
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: app),
        ChangeNotifierProvider(create: (_) => ScreenContext()),
      ],
      child: const MaterialApp(home: Scaffold(body: DownloadsPage())),
    ));
    await tester.pump(const Duration(seconds: 1));
  }

  LinearProgressIndicator bar(WidgetTester tester, String title) => tester.widget<LinearProgressIndicator>(
      find.descendant(of: find.ancestor(of: find.text(title), matching: find.byType(Card)), matching: find.byType(LinearProgressIndicator)));

  testWidgets('progress bars say what each state means', (tester) async {
    await open(tester);
    // Running with a known size: determinate, accent colour, percent shown.
    expect(bar(tester, '第 1 讲').value, closeTo(0.42, 0.001));
    expect(find.text('42%'), findsOneWidget);
    expect(find.text('下载中 · 5.0 MB/s · 420 MB / 1000 MB'), findsOneWidget);
    // Running before the size is known: the only sweeping bar.
    expect(bar(tester, '第 2 讲').value, isNull);
    // Waiting in the queue does not pretend to work.
    expect(bar(tester, '第 3 讲').value, 0);
    // Paused keeps its progress on a muted bar.
    final paused = bar(tester, '第 4 讲');
    expect(paused.value, closeTo(0.3, 0.001));
    expect(paused.color, isNot(Theme.of(tester.element(find.text('第 4 讲'))).colorScheme.primary));
    expect(find.text('30%'), findsOneWidget);
  });

  testWidgets('section buttons pause and resume everything', (tester) async {
    await open(tester);
    await tester.tap(find.text('全部暂停'));
    await tester.pump();
    await tester.tap(find.text('全部继续'));
    await tester.pump();
    expect(app.bulk, [('pause', null), ('resume', null)]);
  });

  testWidgets('picked jobs are paused, resumed and cancelled together', (tester) async {
    await open(tester, size: const Size(360, 1400));
    await tester.longPress(find.text('第 1 讲'));
    await settle(tester);
    expect(find.text('已选 1 项'), findsOneWidget);
    expect(find.text('全部暂停'), findsNothing);
    await tester.tap(find.text('第 4 讲'));
    await tester.pump();
    expect(find.text('已选 2 项'), findsOneWidget);
    // Finished jobs can't be picked.
    await tester.ensureVisible(find.text('第 6 讲'));
    await tester.tap(find.text('第 6 讲'));
    await tester.pump();
    expect(find.text('已选 2 项'), findsOneWidget);

    await tester.tap(find.byTooltip('暂停'));
    await settle(tester);
    expect(app.bulk.last.$1, 'pause');
    expect(app.bulk.last.$2, ['1']);
    expect(find.text('已选 2 项'), findsNothing);

    await tester.tap(find.text('选择任务'));
    await tester.pump();
    await tester.tap(find.byTooltip('全选'));
    await tester.pump();
    expect(find.text('已选 5 项'), findsOneWidget);
    await tester.tap(find.byTooltip('取消下载'));
    await settle(tester);
    expect(find.text('取消 4 个下载？'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '取消下载'));
    await settle(tester);
    expect(app.bulk.last.$1, 'cancel');
    expect(app.bulk.last.$2, ['1', '2', '3', '4']);
  });

  for (final (size, scale) in [(const Size(360, 1400), 1.0), (const Size(360, 1600), 1.3)]) {
    testWidgets('lays out at ${size.width.toInt()} wide, text ×$scale', (tester) async {
      await open(tester, size: size, scale: scale);
      await tester.longPress(find.text('第 1 讲'));
      await settle(tester);
      expect(tester.takeException(), isNull);
    });
  }
}
