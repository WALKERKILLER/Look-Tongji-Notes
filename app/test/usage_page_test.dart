import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:look_studio/features/usage/usage_page.dart';
import 'package:look_studio/widgets/charts.dart';

Map<String, dynamic> _summary({required bool empty}) {
  final day = {'input': 100, 'output': 20, 'cache_read': 300, 'cache_write': 0, 'cost': 0.002, 'calls': 1, 'errors': 0};
  final zero = {'input': 0, 'output': 0, 'cache_read': 0, 'cache_write': 0, 'cost': 0, 'calls': 0, 'errors': 0};
  final totals = empty ? zero : {...day, 'calls': 2, 'cost': 0.004, 'input': 200, 'output': 40, 'cache_read': 600};
  return {
    'from': '2026-10-01',
    'to': '2026-10-03',
    'totals': totals,
    'previous': {...zero, 'cost': 0.002, 'calls': 1},
    'days': [
      {'date': '2026-10-01', ...(empty ? zero : day)},
      {'date': '2026-10-02', ...zero},
      {'date': '2026-10-03', ...(empty ? zero : day)},
    ],
    'by_model': empty ? [] : [{'key': 'deepseek/deepseek-chat', ...totals}],
    'by_purpose': empty ? [] : [{'key': 'chat', ...totals}],
    'by_session': empty ? [] : [{'key': 's1', 'title': '第一章复习', ...totals}],
  };
}

Future<void> _pump(WidgetTester tester, {required bool empty}) async {
  await tester.binding.setSurfaceSize(const Size(1000, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    home: UsagePage(
      fetch: (path, query) async => path.endsWith('/summary')
          ? _summary(empty: empty)
          : [
              if (!empty)
                {'ts': DateTime(2026, 10, 3, 9, 5).millisecondsSinceEpoch, 'provider': 'deepseek', 'model': 'deepseek-chat', 'purpose': 'chat', 'input': 100, 'output': 20, 'cache_read': 300, 'cache_write': 0, 'cost': 0.002, 'ms': 1800, 'ok': true},
            ],
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows tiles, chart toggle, breakdown and recent calls', (tester) async {
    await _pump(tester, empty: false);
    expect(find.descendant(of: find.byType(StatTile), matching: find.text('\$0.0040')), findsOneWidget); // cost tile
    expect(find.text('比前 30 天多 100%'), findsNWidgets(2)); // cost and calls both doubled
    expect(find.text('75%'), findsOneWidget); // 600 cached of 800 prompt tokens
    expect(find.byType(DailyBarChart), findsOneWidget);

    await tester.tap(find.text('Tokens').last); // the chart toggle; the first is the stat tile
    await tester.pumpAndSettle();
    expect(find.byType(ChartLegend), findsOneWidget);

    await tester.tap(find.byTooltip('表格'));
    await tester.pumpAndSettle();
    expect(find.byType(DataTable), findsOneWidget);
    expect(find.byType(DailyBarChart), findsNothing);

    expect(find.text('deepseek-chat'), findsWidgets);
    await tester.tap(find.text('对话').first);
    await tester.pumpAndSettle();
    expect(find.text('第一章复习'), findsOneWidget);
  });

  testWidgets('empty range shows the empty state', (tester) async {
    await _pump(tester, empty: true);
    expect(find.text('这段时间没有用量'), findsOneWidget);
    expect(find.byType(DailyBarChart), findsNothing);
  });
}
