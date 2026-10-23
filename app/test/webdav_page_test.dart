import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:look_studio/core/api.dart';
import 'package:look_studio/features/settings/data_settings.dart';
import 'package:look_studio/features/settings/webdav_page.dart';

class Fake {
  Map<String, dynamic> status = {'configured': false, 'has_password': false, 'folder': 'LookStudio', 'auto': false, 'media': false, 'running': false};
  final calls = <(String, String, Object?)>[];
  Object? failPut;

  Future<dynamic> call(String m, String p, [Object? body]) async {
    calls.add((m, p, body));
    switch ((m, p)) {
      case ('PUT', '/api/sync'):
        if (failPut != null) throw failPut!;
        final b = body as Map;
        status = {...status, 'configured': true, 'has_password': true, 'url': b['url'], 'user': b['user'], 'folder': b['folder'], 'auto': b['auto'], 'media': b['media']};
      case ('POST', '/api/sync/run'):
        status = {...status, 'running': true};
      case ('POST', '/api/sync/auto'):
        status = {...status, 'auto': (body as Map)['auto']};
    }
    return status;
  }
}

void main() {
  late Fake api;
  late StreamController<Map<String, dynamic>> events;

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    events = StreamController<Map<String, dynamic>>.broadcast();
    addTearDown(events.close);
    await tester.pumpWidget(MaterialApp(home: WebDavPage(api: api.call, events: events.stream)));
    await tester.pumpAndSettle();
  }

  setUp(() => api = Fake());

  testWidgets('connects to 坚果云 and starts the first sync', (tester) async {
    await open(tester);
    expect(find.text('未设置'), findsOneWidget);
    final go = find.widgetWithText(FilledButton, '连接并同步');
    expect(tester.widget<FilledButton>(go).onPressed, isNull);
    expect(find.widgetWithText(TextField, '服务器地址'), findsOneWidget);
    expect(find.text('https://dav.jianguoyun.com/dav/'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, '坚果云账号（邮箱）'), 'me@example.com');
    await tester.enterText(find.widgetWithText(TextField, '应用密码'), 'app-pass-1');
    await tester.pump();
    await tester.tap(go);
    await tester.pump();
    await tester.pump();

    final put = api.calls.firstWhere((c) => c.$1 == 'PUT');
    final b = put.$3 as Map;
    expect((b['url'], b['user'], b['password'], b['folder'], b['media']), ('https://dav.jianguoyun.com/dav/', 'me@example.com', 'app-pass-1', 'LookStudio', false));
    expect(api.calls.any((c) => c.$2 == '/api/sync/run'), isTrue);
    expect(find.text('已连接 dav.jianguoyun.com'), findsOneWidget);
    expect(find.textContaining('app-pass-1'), findsNothing);

    events.add({'type': 'sync_progress', 'data': {'step': '同步文件', 'done': 3, 'total': 40, 'bytes': 2048}});
    await tester.pump();
    expect(find.text('同步文件 · 3 / 40 · 2.0 KB'), findsOneWidget);
  });

  testWidgets('shows why the account was rejected', (tester) async {
    api.failPut = ApiError(401, 'WebDAV 账号或应用密码不正确');
    await open(tester);
    await tester.tap(find.text('Nextcloud'));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, '服务器地址'), 'https://cloud.example.com/remote.php/dav/files/me/');
    await tester.enterText(find.widgetWithText(TextField, '账号'), 'me');
    await tester.enterText(find.widgetWithText(TextField, '应用密码'), 'x');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '连接并同步'));
    await tester.pumpAndSettle();
    expect(find.text('WebDAV 账号或应用密码不正确'), findsOneWidget);
    expect(find.text('未设置'), findsOneWidget);
  });

  testWidgets('reports conflicts and keeps the saved password when editing', (tester) async {
    api.status = {
      'configured': true, 'has_password': true, 'url': 'https://dav.jianguoyun.com/dav/', 'user': 'me@example.com', 'folder': 'LookStudio',
      'auto': true, 'media': false, 'running': false,
      'last': {'at': DateTime.now().millisecondsSinceEpoch, 'uploaded': 2, 'downloaded': 5, 'conflicts': 1, 'conflict_dir': '/lib/.sync-conflicts/x'},
    };
    await open(tester);
    expect(find.text('上传 2 · 下载 5'), findsOneWidget);
    expect(find.textContaining('1 个文件在两台设备上都改过'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '查看'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, '修改'));
    await tester.pumpAndSettle();
    expect(find.text('留空则沿用已保存的密码'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    final b = api.calls.lastWhere((c) => c.$1 == 'PUT').$3 as Map;
    expect(b.containsKey('password'), isFalse);
    expect(api.calls.any((c) => c.$2 == '/api/sync/run'), isFalse);
  });

  phoneLayouts();

  test('summary', () {
    expect(webdavSummary({'configured': false}), contains('坚果云'));
    expect(webdavSummary({'configured': true, 'running': true}), '正在同步…');
    expect(webdavSummary({'configured': true, 'url': 'https://dav.jianguoyun.com/dav/', 'auto': true, 'last': {'at': 0}}), 'dav.jianguoyun.com · 还没同步过 · 自动');
    expect(webdavSummary({'configured': true, 'last': {'error': '网盘空间不足'}}), '网盘空间不足');
  });
}

Map<String, dynamic> _storage() => {
      'library': '/home/me/LookStudio',
      'total': 3 << 30,
      'categories': [
        {'key': 'video', 'label': '视频与录音', 'bytes': 2 << 30, 'files': 12},
        {'key': 'slides', 'label': 'PPT 截图', 'bytes': 600 << 20, 'files': 900},
        {'key': 'text', 'label': '转写稿、笔记与题目', 'bytes': 30 << 20, 'files': 80},
        {'key': 'index', 'label': '索引', 'bytes': 40 << 20, 'files': 3},
        {'key': 'cache', 'label': '转写缓存与未完成下载', 'bytes': 300 << 20, 'files': 4},
      ],
      'cleanable': {'cache': 300 << 20, 'sync': 0, 'index': 4 << 20},
      'models': 1 << 30,
      'assistant': 12 << 20,
      'runtime': 160 << 20,
    };

void phoneLayouts() {
  for (final size in const [Size(360, 1800), Size(1000, 1800)]) {
    testWidgets('data pane and sync page lay out at ${size.width.toInt()} wide', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final cleaned = <Object?>[];
      Future<dynamic> call(String m, String p, [Object? body]) async => switch ((m, p)) {
            ('GET', '/api/sync') => {'configured': true, 'url': 'https://dav.jianguoyun.com/dav/', 'auto': true, 'last': {'at': 1}},
            ('GET', '/api/data/estimate') => {'files': 1200, 'bytes': 700 << 20, 'media_files': 12, 'media_bytes': 2 << 30},
            ('GET', '/api/storage') => _storage(),
            ('POST', '/api/storage/clean') => {'freed': (cleaned..add(body)).length},
            _ => const {},
          };
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: DataSettings(api: call, events: const Stream.empty()))),
      ));
      await tester.pumpAndSettle();
      expect(find.text('WebDAV 同步'), findsOneWidget);
      expect(find.textContaining('dav.jianguoyun.com'), findsOneWidget);
      expect(find.text('导出备份 · 约 700 MB'), findsOneWidget);
      expect(find.text('3.0 GB'), findsOneWidget);
      expect(find.textContaining('可释放 300 MB'), findsOneWidget);
      await tester.ensureVisible(find.widgetWithText(TextButton, '清理'));
      await tester.tap(find.widgetWithText(TextButton, '清理'));
      await tester.pumpAndSettle();
      expect(cleaned, [
        {'cache': true}
      ]);

      // The sync page, empty and connected.
      final api = Fake();
      await tester.pumpWidget(MaterialApp(home: WebDavPage(api: api.call, events: const Stream.empty())));
      await tester.pumpAndSettle();
      api.status = {
        'configured': true, 'has_password': true, 'url': 'https://cloud.example.com/remote.php/dav/files/someone-with-a-long-name/', 'user': 'someone@example.com',
        'folder': 'LookStudio', 'auto': true, 'media': true, 'running': false,
        'last': {'at': 1, 'error': 'WebDAV 服务器暂时限制了请求次数，稍后会自动继续', 'partial': true, 'errors': ['library/courses/很长的课程名称/很长的节次名称/notes/笔记.md：HTTP 500']},
      };
      await tester.pumpWidget(MaterialApp(home: WebDavPage(key: UniqueKey(), api: api.call, events: const Stream.empty())));
      await tester.pumpAndSettle();
      expect(find.textContaining('1 个文件没有同步成功'), findsOneWidget);
    });
  }
}
