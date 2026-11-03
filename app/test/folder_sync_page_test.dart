import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:look_studio/features/settings/folder_sync_page.dart';

void main() {
  // The form polls and its text fields blink a cursor, so the tests step frames
  // by hand instead of waiting for the tree to settle.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('a WebDAV account plus selected courses is all the sync needs', (
    tester,
  ) async {
    final calls = <String>[];
    Map? saved;
    Future<dynamic> call(String m, String p, [Object? body]) async {
      calls.add('$m $p');
      if (p == '/api/sync/folder/preview') {
        return {
          'courses': {'pilot': '操作系统期末速成', 'other': '另一门课'},
          'files': 165,
          'bytes': 433000000,
        };
      }
      if (m == 'PUT') {
        saved = body as Map;
        return {};
      }
      return {'kind': 'folder', 'configured': false};
    }

    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: FolderSyncPage(api: call)));
    await settle(tester);
    await tester.enterText(
      find.widgetWithText(TextField, '服务器地址'),
      'https://nas.example.com/dav/',
    );
    await tester.enterText(find.widgetWithText(TextField, '账号'), 'me');
    await tester.enterText(find.widgetWithText(TextField, '应用密码'), 'secret');
    await settle(tester);
    await tester.tap(find.text('刷新课程'));
    await settle(tester);
    expect(find.text('操作系统期末速成'), findsOneWidget);
    await tester.tap(find.text('操作系统期末速成'));
    await settle(tester);
    await tester.ensureVisible(find.text('连接并同步'));
    await tester.tap(find.text('连接并同步'));
    await settle(tester);
    expect(find.text('连接课程同步'), findsOneWidget);
    expect(saved, isNull);
    await tester.tap(find.widgetWithText(FilledButton, '连接并同步').last);
    await settle(tester);
    expect(saved?['course_ids'], ['pilot']);
    expect(saved?['kind'], 'folder');
    expect(saved?['url'], 'https://nas.example.com/dav/');
    expect(saved?['password'], 'secret');
    expect(calls, contains('POST /api/sync/run'));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the account form never offers a local folder', (tester) async {
    var puts = 0;
    Future<dynamic> call(String m, String p, [Object? body]) async {
      if (m == 'PUT') puts++;
      if (p.endsWith('/preview')) return {'courses': {}};
      return {};
    }

    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: FolderSyncPage(api: call)));
    await settle(tester);
    expect(find.text('选择文件夹'), findsNothing);
    expect(find.text('Syncthing'), findsNothing);
    expect(puts, 0);
    await tester.pumpWidget(const SizedBox());
  });
}
