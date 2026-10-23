import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:look_studio/features/notifications/notification_center.dart';

void main() {
  testWidgets('lists notifications, marks one read on open and all read at once', (tester) async {
    final events = StreamController<Map<String, dynamic>>.broadcast();
    addTearDown(events.close);
    final calls = <(String, String, Object?)>[];
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    var items = [
      {
        'id': 'lecture_ready:1',
        'kind': 'lecture_ready',
        'title': '高等数学 有新回放',
        'body': '第 3 讲',
        'lecture_id': '1',
        'at': now,
        'read': false,
      },
      {
        'id': 'assignment_new:9',
        'kind': 'assignment_new',
        'title': '新作业：实验报告',
        'url': 'https://canvas.example/9',
        'at': now - 60,
        'read': false,
      },
    ];
    Future<dynamic> api(String method, String path, [Object? body]) async {
      calls.add((method, path, body));
      return {'items': items, 'unread': items.where((n) => n['read'] != true).length};
    }

    Map<String, dynamic>? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotificationList(api: api, events: events.stream, onOpen: (n) => opened = n),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('高等数学 有新回放'), findsOneWidget);
    expect(find.byIcon(Icons.smart_display_outlined), findsOneWidget);
    expect(find.byIcon(Icons.assignment_outlined), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('未读')), findsNWidgets(2));

    await tester.tap(find.text('高等数学 有新回放'));
    await tester.pumpAndSettle();
    expect(opened?['lecture_id'], '1');
    expect(calls.last.$2, '/api/notifications/read');
    expect(calls.last.$3, {
      'ids': ['lecture_ready:1'],
    });
    expect(find.bySemanticsLabel(RegExp('未读')), findsOneWidget);

    await tester.tap(find.text('全部已读'));
    await tester.pumpAndSettle();
    expect(calls.last.$3, {'all': true});
    expect(find.text('全部已读'), findsNothing);

    items = [
      {'id': 'announcement:3', 'kind': 'announcement', 'title': '新公告', 'at': now, 'read': false},
      ...items.map((n) => {...n, 'read': true}),
    ];
    events.add({'type': 'notification', 'data': items.first});
    await tester.pumpAndSettle();
    expect(find.text('新公告'), findsOneWidget);
  });
}
