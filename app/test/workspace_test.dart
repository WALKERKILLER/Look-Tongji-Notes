import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:look_studio/core/lookd_service.dart';
import 'package:look_studio/core/workspace.dart';
import 'package:look_studio/features/setup/workspace_setup_page.dart';
import 'package:provider/provider.dart';

void main() {
  late Directory tmp;
  late Workspace ws;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('ws');
    ws = Workspace(
      info: () async => {
        // Android's real library path contains '=' (see Workspace.guestNative).
        'nativeLibraryDir': '/data/app/~~aB==/cn.lookstudio.look_studio-xY==/lib/arm64',
        'filesDir': '${tmp.path}/files',
        'cacheDir': '${tmp.path}/cache',
        'abi': 'arm64-v8a',
        'device': 'Google Pixel 8 ',
        'timezone': 'Asia/Shanghai',
      },
    );
    await ws.load();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('runs guest commands through proot with the native folder at a fixed path', () {
    final (exe, args, env) = ws.guest(['${Workspace.guestNative}/liblookd.so', '-data', ws.dataDir], env: {'LOOKD_TOKEN': 't'});
    expect(exe, '/data/app/~~aB==/cn.lookstudio.look_studio-xY==/lib/arm64/libproot.so');
    expect(args, containsAllInOrder(['-r', '${tmp.path}/files/ubuntu', '-b', '${tmp.path}/files']));
    expect(args, contains('/data/app/~~aB==/cn.lookstudio.look_studio-xY==/lib/arm64:/opt/look'));
    // env reads NAME=VALUE words up to the command, so nothing after it may be
    // mistaken for one and the command itself must not contain '='.
    final cmd = args.indexOf('/opt/look/liblookd.so');
    expect(args.sublist(args.indexOf('/usr/bin/env'), cmd), containsAll(['-i', 'TZ=Asia/Shanghai', 'LOOKD_TOKEN=t', 'HOME=/root']));
    expect(args.sublist(cmd), ['/opt/look/liblookd.so', '-data', '${tmp.path}/files/look-data']);
    expect(env['PROOT_LOADER'], endsWith('/lib/arm64/libproot_loader.so'));
    expect(Directory(env['PROOT_TMP_DIR']!).existsSync(), isTrue);
    expect(ws.device, 'Google Pixel 8');
    expect(ws.installed, isFalse);
  });

  testWidgets('setup page fits a small phone and shows a failed step', (tester) async {
    tester.view.physicalSize = const Size(720, 1280);
    tester.view.devicePixelRatio = 2; // 360 × 640 dp
    addTearDown(tester.view.reset);
    ws.error = '下载失败：网络不可用';
    final daemon = LookdService(workspace: ws);
    addTearDown(daemon.dispose);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: daemon,
      child: MaterialApp(theme: ThemeData(useMaterial3: true), home: const WorkspaceSetupPage()),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('准备 Linux 工作区'), findsOneWidget);
    expect(find.text('下载失败：网络不可用'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('重试'), 200);
    expect(find.text('重试'), findsOneWidget);
    for (final m in workspaceMirrors) {
      expect(find.text(m.name), findsOneWidget);
    }
  });
}
