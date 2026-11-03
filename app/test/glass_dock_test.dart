import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/widgets/glass_dock.dart';

void main() {
  Widget dock({int selected = 0, bool minimized = false, ValueChanged<int>? onSelected, VoidCallback? onExpand}) => MaterialApp(
    theme: ThemeData(colorSchemeSeed: Colors.indigo),
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: 380,
          child: GlassNavDock(
            selected: selected,
            minimized: minimized,
            onSelected: onSelected ?? (_) {},
            onExpand: onExpand,
            accessory: const Icon(Icons.smart_toy_outlined),
            items: [
              for (final label in ['首页', '课程', '日程', '下载', '资料库', '设置'])
                GlassNavItem(
                  icon: const Icon(Icons.circle_outlined),
                  selectedIcon: const Icon(Icons.circle),
                  label: label,
                ),
            ],
          ),
        ),
      ),
    ),
  );

  testWidgets('every destination fits a phone and selects with a tap', (t) async {
    var picked = -1;
    await t.pumpWidget(dock(onSelected: (i) => picked = i));
    for (final label in ['首页', '课程', '日程', '下载', '资料库', '设置']) {
      expect(find.text(label), findsOneWidget);
    }
    await t.tap(find.text('资料库'));
    expect(picked, 4);
    await t.pumpWidget(dock(selected: 4));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });

  testWidgets('a minimized dock shows the current destination and expands on tap', (t) async {
    var expanded = false;
    await t.pumpWidget(dock(selected: 1, minimized: true, onExpand: () => expanded = true));
    await t.pumpAndSettle();
    expect(find.text('课程'), findsOneWidget);
    expect(find.text('首页'), findsNothing);
    expect(find.byIcon(Icons.smart_toy_outlined), findsOneWidget);
    await t.tap(find.text('课程'));
    expect(expanded, isTrue);
  });
}
