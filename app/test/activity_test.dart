import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:look_studio/core/activity_tracker.dart';
import 'package:look_studio/core/app_state.dart';
import 'package:look_studio/core/lookd_service.dart';
import 'package:look_studio/features/activity/activity_page.dart';
import 'package:look_studio/widgets/heatmap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('heatmap layout', () {
    test('levels come from quartiles of non-zero days', () {
      final t = heatThresholds([0, 10, 20, 30, 40, 50, 0]);
      expect(t, [20, 30, 40]);
      expect([0, 10, 20, 25, 40, 41, 500].map((v) => heatLevel(v, t)), [0, 1, 1, 2, 3, 4, 4]);
      // A single active day still reads as activity.
      expect(heatLevel(3, heatThresholds([0, 3])), 1);
    });

    test('weeks are Monday-first and span a year end', () {
      final w = heatWeeks(DateTime(2025, 12, 25), DateTime(2026, 1, 8));
      expect(w.length, 3);
      expect(w.every((c) => c.length == 7), isTrue);
      expect(w[0].take(3), everyElement(isNull));
      expect(w[0][3], DateTime(2025, 12, 25));
      expect(w[1][0], DateTime(2025, 12, 29));
      expect(w[1][3], DateTime(2026, 1, 1));
      expect(w[2][3], DateTime(2026, 1, 8));
      expect(w[2].skip(4), everyElement(isNull));
    });

    test('tooltip lists minutes, kinds and counts', () {
      final d = ActivityDay({'date': '2026-10-14', 'minutes': 42, 'by_kind': {'watch': 1800, 'read': 720}, 'asks': 2, 'notes_created': 1});
      final (title, lines) = d.tooltip(DateTime(2026, 10, 14));
      expect(title, startsWith('10月14日'));
      expect(lines, ['学习 42 分钟', '看课 30 · 阅读 12', '提问 2 次 · 笔记 1 篇']);
      expect(ActivityDay.empty.tooltip(DateTime(2026, 10, 14)).$2, ['没有学习记录']);
      expect(fmtMinutes(125), '2 小时 5 分');
    });
  });

  group('tracker', () {
    late DateTime now;
    late ActivityTracker t;
    setUp(() {
      now = DateTime(2026, 10, 14, 9);
      t = ActivityTracker(AppState(LookdService()), now: () => now);
    });
    tearDown(() => t.dispose());

    void advance(int seconds) {
      for (var i = 0; i < seconds ~/ 10; i++) {
        now = now.add(const Duration(seconds: 10));
        t.tickNow();
      }
    }

    test('watching counts while visible, not while hidden', () {
      final c = t.clock('watch', lectureId: 'L1')..start();
      advance(60);
      t.didChangeAppLifecycleState(AppLifecycleState.inactive); // unfocused but visible
      advance(30);
      t.didChangeAppLifecycleState(AppLifecycleState.hidden);
      advance(60);
      c.stop();
      expect(t.pendingSeconds, {'watch/L1': 90});
    });

    test('reading needs focus and interaction within 2 minutes', () {
      final c = t.clock('read', interactive: true)..start();
      advance(300); // idle after the first 2 minutes
      c.touch();
      advance(30);
      t.didChangeAppLifecycleState(AppLifecycleState.inactive);
      advance(30);
      c.stop();
      expect(t.pendingSeconds, {'read/': 150});
    });
  });

  testWidgets('home card shows figures and a day tooltip', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final semantics = tester.ensureSemantics();
    final today = DateTime(2026, 10, 14);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ActivityCard(
          today: today,
          fetch: (path, q) async => path.endsWith('/day')
              ? {
                  'date': q['date'],
                  'minutes': 25,
                  'by_kind': {'read': 1500},
                  'asks': 1,
                  'lectures': [
                    {'lecture_id': 'L1', 'title': '第 3 讲 傅里叶变换', 'course_title': '信号与系统', 'kind': 'read', 'seconds': 1500},
                  ],
                  'notes': [],
                  'transcribed': [],
                }
              : {
            'days': [
              {'date': '2026-10-13', 'minutes': 50, 'by_kind': {'watch': 3000}},
              {'date': '2026-10-14', 'minutes': 25, 'by_kind': {'read': 1500}, 'asks': 1},
            ],
            'streak': {'current': 2, 'longest': 9},
            'totals': {'minutes': 75, 'active_days': 2},
            'courses': [],
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('1 小时 15 分'), findsOneWidget); // this week
    expect(find.text('2 天'), findsOneWidget);
    expect(find.text('9 天'), findsOneWidget);
    expect(find.semantics.byLabel('10月14日，学习 25 分钟'), findsOne);

    final grid = find.byType(ContributionHeatmap);
    final box = tester.getRect(grid);
    // Today is the Wednesday cell of the last column.
    const step = 12 + ContributionHeatmap.gap;
    final weeks = ContributionHeatmap.weeksFor(tester.getSize(grid).width);
    final cell = box.topLeft + Offset(ContributionHeatmap.labelWidth + (weeks - 1) * step + 6, ContributionHeatmap.monthHeight + 2 * step + 6);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(cell);
    await tester.pump();
    expect(find.text('阅读 25'), findsOneWidget);
    expect(find.text('提问 1 次'), findsOneWidget);
    semantics.dispose();

    await tester.tapAt(cell);
    await tester.pumpAndSettle();
    expect(find.text('第 3 讲 傅里叶变换'), findsOneWidget);
    expect(find.text('信号与系统 · 阅读 25 分钟'), findsOneWidget);
  });
}
