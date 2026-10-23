import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:look_studio/features/settings/notion_page.dart';

class Fake {
  Map<String, dynamic> status = {'connected': false, 'bot': {}, 'auto': false, 'pages': 0, 'running': false};
  final calls = <(String, String, Object?)>[];

  Future<dynamic> call(String m, String p, [Object? body]) async {
    calls.add((m, p, body));
    switch ((m, p)) {
      case ('POST', '/api/notion/connect'):
        status = {
          ...status,
          'connected': true,
          'bot': {'name': 'Look Studio', 'workspace': '我的工作区'},
          'token_last4': '1234',
        };
      case ('PUT', '/api/notion'):
        final b = body as Map;
        if (b['parent'] != null) status = {...status, 'parent': {'id': b['parent'], 'title': '学习', 'url': 'https://www.notion.so/x', 'icon': '📚'}};
        if (b['auto'] != null) status = {...status, 'auto': b['auto']};
      case ('POST', '/api/notion/sync'):
        status = {...status, 'running': true};
      case ('GET', final String path) when path.startsWith('/api/notion/pages'):
        return [
          {'id': 'p1', 'title': '学习', 'url': 'https://www.notion.so/p1', 'icon': '📚'},
          {'id': 'p2', 'title': '日记', 'url': 'https://www.notion.so/p2'},
        ];
    }
    return status;
  }
}

Widget wrap(Widget w) => MaterialApp(home: w);

void main() {
  testWidgets('connects, picks a page and syncs', (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = Fake();
    final events = StreamController<Map<String, dynamic>>.broadcast();
    addTearDown(events.close);
    await tester.pumpWidget(wrap(NotionPage(api: api.call, events: events.stream)));
    await tester.pumpAndSettle();

    expect(find.text('未连接'), findsOneWidget);
    final connect = find.widgetWithText(FilledButton, '连接');
    expect(tester.widget<FilledButton>(connect).onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'ntn_secret1234');
    await tester.pump();
    await tester.tap(connect);
    await tester.pumpAndSettle();
    expect(api.calls.any((c) => c.$2 == '/api/notion/connect' && (c.$3 as Map)['token'] == 'ntn_secret1234'), isTrue);
    expect(find.text('已连接到 我的工作区'), findsOneWidget);
    expect(find.text('集成密钥 ••••1234'), findsOneWidget);
    expect(find.textContaining('ntn_secret'), findsNothing);

    await tester.tap(find.text('选择页面'));
    await tester.pumpAndSettle();
    expect(find.text('日记'), findsOneWidget);
    await tester.tap(find.text('学习'));
    await tester.pumpAndSettle();
    expect((api.calls.last.$1, api.calls.last.$2, (api.calls.last.$3 as Map)['parent']), ('PUT', '/api/notion', 'p1'));
    expect(find.text('课程库在这个页面下的「Look Studio 课程库」里'), findsOneWidget);

    await tester.tap(find.text('开始同步'));
    await tester.pump();
    await tester.pump(); // running: the progress bar animates, so no settling
    expect(api.calls.last.$2, '/api/notion/sync');
    events.add({'type': 'notion_progress', 'data': {'done': 3, 'total': 12}});
    await tester.pump();
    expect(find.text('正在同步 3 / 12'), findsOneWidget);

    api.status = {
      ...api.status,
      'running': false,
      'pages': 12,
      'last': {'at': DateTime.now().millisecondsSinceEpoch, 'created': 12, 'updated': 0, 'unchanged': 0, 'trashed': 0, 'conflicts': ['笔记 · 第一讲'], 'errors': []},
    };
    events.add({'type': 'notion_synced', 'data': {}});
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('新建 12 · 未变 0'), findsOneWidget);
    expect(find.text('1 个页面在 Notion 里改过，保留了你的版本'), findsOneWidget);
    expect(find.text('立即同步'), findsOneWidget);
  });

  test('summary', () {
    expect(notionSummary({'connected': false}), '同步到你的 Notion 工作区');
    expect(notionSummary({'connected': true}), '已连接 · 还没选同步位置');
    expect(notionSummary({'connected': true, 'parent': {'title': '学习'}, 'pages': 4, 'auto': true}), '学习 · 4 个页面 · 自动');
    expect(notionSummary({'connected': true, 'parent': {'title': '学习'}, 'last': {'error': '令牌失效'}}), '令牌失效');
  });
}
