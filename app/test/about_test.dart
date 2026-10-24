import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:look_studio/features/settings/about_page.dart';
import 'package:look_studio/widgets/look_logo.dart';

Map<String, dynamic> release(String tag, {bool pre = false, bool draft = false}) => {
      'tag_name': tag,
      'prerelease': pre,
      'draft': draft,
      'html_url': 'https://github.com/$repoSlug/releases/tag/$tag',
      'published_at': '2026-10-20T00:00:00Z',
      'assets': [
        {'name': 'look-studio-x-windows-x64-setup.exe', 'browser_download_url': 'https://example.com/$tag.exe'},
      ],
    };

void main() {
  test('versions order like semantic versioning', () {
    final sorted = ['0.2.1', '0.2.0', '0.2.0-beta.10', '0.2.0-beta.2', '0.2.0-alpha.1', '0.1.9']..sort(compareVersions);
    expect(sorted, ['0.1.9', '0.2.0-alpha.1', '0.2.0-beta.2', '0.2.0-beta.10', '0.2.0', '0.2.1']);
    expect(compareVersions('0.2.0', '0.2.0'), 0);
  });

  test('the newest newer release; pre-releases only for pre-release users', () {
    final list = [
      release('studio-v0.3.0-beta.1', pre: true),
      release('studio-v0.2.1'),
      release('studio-v0.4.0', draft: true),
      release('skill-v9.0.0'),
      release('studio-v0.2.0'),
    ];
    expect(newerRelease(list, '0.2.0')?.version, '0.2.1');
    expect(newerRelease(list, '0.2.0-beta.1')?.version, '0.3.0-beta.1');
    expect(newerRelease(list, '0.3.0-beta.1'), isNull);
    expect(newerRelease(list, '0.2.1'), isNull);
  });

  testWidgets('checking for updates offers the newer release', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final opened = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(children: [
          AboutSection(fetchReleases: () async => [release('studio-v9.0.0')], open: (u) async => opened.add(u)),
        ]),
      ),
    ));
    expect(find.text('Look Studio'), findsOneWidget);
    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle();
    expect(find.textContaining('有新版本 9.0.0'), findsOneWidget);
    await tester.tap(find.text('查看更新说明'));
    expect(opened.single, 'https://github.com/$repoSlug/releases/tag/studio-v9.0.0');

    await tester.tap(find.text('反馈问题'));
    expect(Uri.parse(opened.last).path, '/$repoSlug/issues/new');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the drawn logo heads the page and the tip code shows only on request', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ListView(children: [AboutSection(fetchReleases: () async => [], open: (_) async {})])),
    ));
    expect(find.byType(LookLogo), findsOneWidget);
    expect(find.text('开源许可'), findsOneWidget);
    expect(find.byType(Image), findsNothing, reason: 'the code is not on the page');
    await tester.scrollUntilVisible(find.text('赞赏'), 100, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('赞赏'));
    await tester.pumpAndSettle();
    expect(find.text('请作者喝杯咖啡'), findsOneWidget);
    expect(find.bySemanticsLabel('微信赞赏码'), findsOneWidget);
    expect(find.textContaining('截屏'), findsOneWidget, reason: 'a phone gets the screenshot hint');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed check says so and can be retried', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ListView(children: [AboutSection(fetchReleases: () async => throw Exception('offline'))])),
    ));
    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle();
    expect(find.textContaining('无法检查更新'), findsOneWidget);
    expect(find.text('检查更新'), findsOneWidget);
  });
}
