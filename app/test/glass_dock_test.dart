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

  testWidgets('the lens is inset evenly so its corners follow the pill', (t) async {
    await t.pumpWidget(dock(selected: 0));
    await t.pumpAndSettle();
    final lens = t.getRect(find.byKey(const ValueKey('dock-lens')));
    final pill = t.getRect(find.byKey(const ValueKey('dock-bar')));
    expect(lens.top - pill.top, GlassNavDock.inset);
    expect(pill.bottom - lens.bottom, GlassNavDock.inset);
    expect(lens.left - pill.left, GlassNavDock.inset);
    expect(GlassNavDock.lensRadius, GlassNavDock.height / 2 - GlassNavDock.inset);
  });

  testWidgets('pressing and sliding along the dock selects where the finger lifts', (t) async {
    final picked = <int>[];
    await t.pumpWidget(dock(onSelected: picked.add));
    await t.pumpAndSettle();
    final g = await t.startGesture(t.getCenter(find.text('首页')));
    await t.pump();
    for (final label in ['课程', '日程', '下载']) {
      await g.moveTo(t.getCenter(find.text(label)));
      await t.pump();
    }
    // The lens follows the finger before anything is selected.
    final lens = t.getRect(find.byKey(const ValueKey('dock-lens')));
    expect(lens.center.dx, closeTo(t.getCenter(find.text('下载')).dx, 8));
    expect(picked, isEmpty);
    await g.up();
    await t.pumpAndSettle();
    expect(picked, [3]);
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
