import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:look_studio/widgets/horizontal_scroller.dart';

Widget row(int n, {ScrollController? controller}) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            height: 80,
            child: HorizontalScroller(
              controller: controller,
              builder: (c) => ListView(
                controller: c,
                scrollDirection: Axis.horizontal,
                children: [for (var i = 0; i < n; i++) SizedBox(width: 100, child: Text('item $i'))],
              ),
            ),
          ),
        ),
      ),
    );

double opacityOf(WidgetTester tester, String tooltip) {
  final o = find.ancestor(of: find.byTooltip(tooltip), matching: find.byType(AnimatedOpacity));
  return tester.widget<AnimatedOpacity>(o.first).opacity;
}

void main() {
  testWidgets('a mouse can drag the row and page it with the edge buttons', (tester) async {
    final c = ScrollController();
    addTearDown(c.dispose);
    await tester.pumpWidget(row(12, controller: c));
    await tester.pumpAndSettle();
    expect(opacityOf(tester, '向右滚动'), 0);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(find.byType(ListView)));
    await mouse.moveTo(tester.getCenter(find.byType(ListView)));
    await tester.pumpAndSettle();
    expect(opacityOf(tester, '向右滚动'), 1);
    expect(opacityOf(tester, '向左滚动'), 0, reason: 'nothing before the start');

    await tester.tap(find.byTooltip('向右滚动'));
    await tester.pumpAndSettle();
    expect(c.offset, closeTo(320, 0.1)); // 80 % of the viewport
    expect(opacityOf(tester, '向左滚动'), 1);

    await tester.dragFrom(tester.getCenter(find.byType(ListView)), const Offset(-200, 0), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(c.offset, greaterThan(400));

    await tester.tap(find.byTooltip('向右滚动'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('向右滚动'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(c.offset, c.position.maxScrollExtent);
    expect(opacityOf(tester, '向右滚动'), 0);
  });

  testWidgets('no buttons when everything fits', (tester) async {
    await tester.pumpWidget(row(3));
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(find.byType(ListView)));
    await tester.pumpAndSettle();
    expect(opacityOf(tester, '向右滚动'), 0);
    expect(opacityOf(tester, '向左滚动'), 0);
  });

  testWidgets('a carousel pages by whole items', (tester) async {
    late CarouselController controller;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 600,
            height: 200,
            child: HorizontalScroller(
              carousel: true,
              itemExtent: 200,
              builder: (c) => CarouselView(
                controller: controller = c as CarouselController,
                itemExtent: 200,
                children: [for (var i = 0; i < 10; i++) Text('card $i')],
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(find.byType(CarouselView)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('向右滚动'));
    await tester.pumpAndSettle();
    expect(controller.leadingItem, 3);
  });
}
