import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:look_studio/widgets/glass_dock.dart';
import 'package:look_studio/widgets/glass_rail.dart';

void main() {
  const labels = ['首页', '课程', '日程', '下载', '资料库', '定时', '插件', '设置', 'NAS'];

  Widget rail(double height, {ValueChanged<int>? onSelected}) => MaterialApp(
    theme: ThemeData(colorSchemeSeed: Colors.indigo),
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          height: height,
          child: GlassNavRail(
            selected: 0,
            onSelected: onSelected ?? (_) {},
            brand: const SizedBox.square(key: ValueKey('brand'), dimension: 36),
            leading: const SizedBox.square(key: ValueKey('lead'), dimension: 56),
            trailing: const SizedBox.square(key: ValueKey('trail'), dimension: 96),
            items: [
              for (final l in labels)
                GlassNavItem(icon: const Icon(Icons.circle_outlined), selectedIcon: const Icon(Icons.circle), label: l),
            ],
          ),
        ),
      ),
    ),
  );

  testWidgets('a tall rail shows every labelled destination and the brand', (t) async {
    t.view.physicalSize = const Size(800, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(rail(1000));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.byKey(const ValueKey('brand')), findsOneWidget);
    for (final l in labels) {
      expect(find.text(l), findsOneWidget);
    }
  });

  testWidgets('a short rail keeps its pinned controls apart and scrolls the rest', (t) async {
    var picked = -1;
    await t.pumpWidget(rail(420, onSelected: (i) => picked = i));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.byKey(const ValueKey('brand')), findsNothing);
    // Labels gave way to tooltips.
    expect(find.text('首页'), findsNothing);
    expect(find.byTooltip('NAS'), findsOneWidget);
    final lead = t.getRect(find.byKey(const ValueKey('lead')));
    final trail = t.getRect(find.byKey(const ValueKey('trail')));
    expect(lead.bottom, lessThan(trail.top));
    await t.scrollUntilVisible(find.byTooltip('NAS'), 48, scrollable: find.byType(Scrollable));
    final nas = t.getRect(find.byTooltip('NAS'));
    expect(nas.bottom, lessThanOrEqualTo(trail.top));
    await t.tap(find.byTooltip('NAS'));
    expect(picked, 8);
  });
}
