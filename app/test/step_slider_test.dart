import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:look_studio/features/assistant/thinking_control.dart';
import 'package:look_studio/widgets/step_slider.dart';

void main() {
  Future<List<String>> pump(WidgetTester tester, {String start = 'medium', double width = 320}) async {
    final changes = <String>[];
    var value = start;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: StatefulBuilder(
              builder: (context, set) => ThinkingControl(
                value: value,
                onChanged: (v) {
                  changes.add(v);
                  set(() => value = v);
                },
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return changes;
  }

  testWidgets('tapping a label or a stop picks that level', (tester) async {
    final changes = await pump(tester);
    expect(find.text('兼顾速度与深度'), findsOneWidget);
    await tester.tap(find.text('最高'));
    await tester.pumpAndSettle();
    expect(changes, ['xhigh']);
    expect(find.text('尽可能深入，最慢，花费也最多'), findsOneWidget);

    // The track's start edge is the 关闭 stop.
    final track = tester.getRect(find.byType(CustomPaint).last);
    await tester.tapAt(Offset(track.left + 4, track.center.dy));
    await tester.pumpAndSettle();
    expect(changes.last, 'off');
  });

  testWidgets('dragging commits once, at the nearest stop', (tester) async {
    final changes = await pump(tester, start: 'off');
    final track = tester.getRect(find.byType(CustomPaint).last);
    final g = await tester.startGesture(Offset(track.left + 8, track.center.dy));
    for (var i = 1; i <= 10; i++) {
      await g.moveBy(Offset(track.width * 0.059, 0)); // to about 60%
      await tester.pump();
    }
    expect(changes, isEmpty, reason: 'no request per step while dragging');
    await g.up();
    await tester.pumpAndSettle();
    expect(changes, ['medium']);
  });

  testWidgets('arrow keys step and the value is announced', (tester) async {
    final changes = await pump(tester, start: 'low');
    final handle = tester.ensureSemantics();
    final slider = find.byWidgetPredicate((w) => w is StepSlider<String>);
    expect(tester.getSemantics(slider), matchesSemantics(isSlider: true, value: '低', increasedValue: '中', decreasedValue: '最少', label: '思考强度',
        hasIncreaseAction: true, hasDecreaseAction: true, isFocusable: true, hasFocusAction: true, hasEnabledState: true, isEnabled: true));
    Focus.of(tester.element(find.text('低'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pumpAndSettle();
    expect(changes, ['medium', 'xhigh']);
    handle.dispose();
  });

  testWidgets('labels stay inside a narrow phone width', (tester) async {
    await pump(tester, width: 248);
    expect(tester.takeException(), isNull);
    final box = tester.getRect(find.byType(ThinkingControl));
    for (final l in ['关闭', '最少', '低', '中', '高', '最高']) {
      final r = tester.getRect(find.text(l));
      expect(r.left >= box.left - 0.5 && r.right <= box.right + 0.5, isTrue, reason: '$l at $r in $box');
    }
  });
}
