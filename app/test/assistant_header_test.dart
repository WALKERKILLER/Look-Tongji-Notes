import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:look_studio/features/assistant/assistant_panel.dart';

Widget _host(Widget child, {double width = 360, double textScale = 1}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 780), textScaler: TextScaler.linear(textScale)),
        child: Scaffold(body: Center(child: child)),
      ),
    );

/// The phone header: avatar (44), gaps and the close button take ~108 of 360.
Widget _header(String name, ValueChanged<String> on) => SizedBox(width: 252, child: AssistantViewSwitch(botName: name, view: 'bot', onChanged: on));

void main() {
  testWidgets('the bot name shows in full on a phone', (tester) async {
    final picked = <String>[];
    await tester.pumpWidget(_host(_header('小Look', picked.add)));
    final name = tester.renderObject<RenderParagraph>(find.text('小Look'));
    expect(name.size.width, greaterThanOrEqualTo(name.getMaxIntrinsicWidth(double.infinity) - 0.5), reason: 'not cut off');
    await tester.tap(find.text('会话'));
    expect(picked, ['sessions']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('where the names do not fit, the segments become icons with tooltips', (tester) async {
    await tester.pumpWidget(_host(_header('一个很长很长的助手名字叫小Look', (_) {})));
    expect(find.textContaining('很长'), findsNothing);
    expect(find.byIcon(Icons.smart_toy_outlined), findsOneWidget);
    expect(find.byTooltip('一个很长很长的助手名字叫小Look'), findsOneWidget);

    await tester.pumpWidget(_host(_header('小Look', (_) {}), textScale: 2));
    expect(find.byIcon(Icons.forum_outlined), findsOneWidget, reason: 'large text falls back too');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the approval chip names the mode and switches it from its menu', (tester) async {
    var mode = 'auto';
    await tester.pumpWidget(_host(StatefulBuilder(
      builder: (context, setState) => ApprovalModeChip(mode: mode, onChanged: (m) => setState(() => mode = m)),
    )));
    expect(find.text('自动'), findsOneWidget);
    expect(find.bySemanticsLabel('操作模式：自动'), findsOneWidget);
    await tester.tap(find.text('自动'));
    await tester.pumpAndSettle();
    expect(find.text('改动先生成卡片，由你应用'), findsOneWidget);
    expect(find.text('删除文件在两种模式下都会先问你'), findsOneWidget);
    await tester.tap(find.text('询问'));
    await tester.pumpAndSettle();
    expect(mode, 'ask');
    expect(find.text('询问'), findsOneWidget);
    expect(find.byIcon(Icons.front_hand_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
