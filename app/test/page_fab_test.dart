import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:look_studio/shell.dart';

/// The phone layout: the shell's assistant button over a tab whose page has
/// its own button, both in the bottom-right corner.
Widget phone({required bool pageButton, bool tabActive = true}) => MaterialApp(
      home: Scaffold(
        floatingActionButton: PageFabClearance(child: FloatingActionButton(key: const Key('assistant'), onPressed: () {}, child: const Icon(Icons.face))),
        bottomNavigationBar: const SizedBox(height: 80),
        body: TickerMode(
          enabled: tabActive,
          child: Navigator(
            key: ValueKey(pageButton),
            onGenerateRoute: (_) => MaterialPageRoute(
              builder: (_) => Scaffold(
                floatingActionButton: pageButton
                    ? PageFab(child: FloatingActionButton.extended(key: const Key('page'), onPressed: () {}, icon: const Icon(Icons.add), label: const Text('新建')))
                    : null,
                body: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  setUp(() => PageFab.shown.value = false);

  testWidgets("the assistant's button rises above a page's own and comes back", (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(phone(pageButton: false));
    await tester.pumpAndSettle();
    final alone = tester.getRect(find.byKey(const Key('assistant')));

    await tester.pumpWidget(phone(pageButton: true));
    await tester.pumpAndSettle();
    final page = tester.getRect(find.byKey(const Key('page')));
    final assistant = tester.getRect(find.byKey(const Key('assistant')));
    expect(assistant.overlaps(page), isFalse);
    expect(page.top - assistant.bottom, moreOrLessEquals(12));
    expect(assistant.right, moreOrLessEquals(page.right));

    // A hidden tab's button does not count.
    await tester.pumpWidget(phone(pageButton: true, tabActive: false));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(const Key('assistant'))), alone);

    await tester.pumpWidget(phone(pageButton: false));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(const Key('assistant'))), alone);
  });
}
