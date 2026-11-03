import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:look_studio/features/settings/folder_sync_page.dart';

void main() {
  testWidgets(
    'folder selection previews the pilot and configures only selected courses',
    (tester) async {
      final calls = <String>[];
      Map? saved;
      Future<dynamic> call(String m, String p, [Object? body]) async {
        calls.add('$m $p');
        if (p == '/api/sync/folder/preview')
          return {
            'courses': {'pilot': '操作系统期末速成', 'other': '另一门课'},
            'files': 165,
            'bytes': 433000000,
          };
        if (m == 'PUT') {
          saved = body as Map;
          return {};
        }
        return {'kind': 'folder', 'configured': false};
      }

      await tester.pumpWidget(
        MaterialApp(
          home: FolderSyncPage(
            api: call,
            chooseFolder: () async => {'local_folder': '/sync/LookStudioSync'},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择文件夹'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('操作系统期末速成'));
      await tester.pump();
      await tester.ensureVisible(find.text('预览并接入'));
      await tester.tap(find.text('预览并接入'));
      await tester.pumpAndSettle();
      expect(find.text('接入同步资料库'), findsOneWidget);
      expect(saved, isNull);
      await tester.tap(find.text('接入并同步'));
      await tester.pumpAndSettle();
      expect(saved?['course_ids'], ['pilot']);
      expect(saved?['media'], true);
      expect(saved?['kind'], 'folder');
      expect(calls, contains('POST /api/sync/run'));
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('cancelled directory grant never configures sync', (
    tester,
  ) async {
    var puts = 0;
    Future<dynamic> call(String m, String p, [Object? body]) async {
      if (m == 'PUT') puts++;
      if (p.endsWith('/preview')) return {'courses': {}};
      return {};
    }

    await tester.pumpWidget(
      MaterialApp(
        home: FolderSyncPage(api: call, chooseFolder: () async => null),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择文件夹'));
    await tester.pumpAndSettle();
    expect(puts, 0);
    await tester.pumpWidget(const SizedBox());
  });
}
