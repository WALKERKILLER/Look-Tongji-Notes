import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:look_studio/features/assistant/runtime_setup.dart';

void main() {
  Map<String, dynamic> status({bool node = false, bool deps = false, Map<String, dynamic>? install}) => {
        'node': {'ok': node, 'version': node ? 'v24.9.0' : '', 'source': node ? 'managed' : 'none'},
        'deps': {'ok': deps},
        'install': install ?? {'state': 'idle', 'log': []},
      };

  testWidgets('installs with the chosen mirror and follows progress events', (tester) async {
    final events = StreamController<Map<String, dynamic>>.broadcast();
    addTearDown(events.close);
    final calls = <(String, String, Object?)>[];
    var current = status();
    Future<dynamic> api(String method, String path, [Object? body]) async {
      calls.add((method, path, body));
      if (method == 'POST') current = status(install: {'state': 'running', 'step': '检查', 'log': []});
      return current;
    }

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: RuntimeSetupCard(api: api, events: events.stream)))));
    await tester.pumpAndSettle();
    expect(find.text('安装助手运行环境'), findsOneWidget);
    expect(find.text('未找到可用的 Node.js 22+'), findsOneWidget);

    await tester.tap(find.text('官方源'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始安装'));
    await tester.pump();
    expect((calls.last.$1, calls.last.$2), ('POST', '/api/agent/runtime/install'));
    expect(calls.last.$3, {'mirror': 'official'});

    events.add({'type': 'runtime', 'data': {'state': 'running', 'step': '下载 Node.js', 'progress': 0.4, 'log': ['下载 node-v24.9.0-linux-x64.tar.gz']}});
    await tester.pump();
    expect(find.text('下载 Node.js'), findsOneWidget);
    expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, 0.4);
    expect(find.text('正在安装'), findsOneWidget);

    current = status(node: true, install: {'state': 'failed', 'error': '安装依赖失败：exit status 1', 'log': ['npm ERR!']});
    events.add({'type': 'runtime', 'data': current['install']});
    await tester.pumpAndSettle();
    expect(find.text('安装依赖失败：exit status 1'), findsOneWidget);
    expect(find.text('v24.9.0 · 应用内安装'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('a ready runtime offers only a recheck', (tester) async {
    Future<dynamic> api(String method, String path, [Object? body]) async => status(node: true, deps: true);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: RuntimeSetupCard(api: api, events: const Stream.empty()))));
    await tester.pumpAndSettle();
    expect(find.text('运行环境已就绪'), findsOneWidget);
    expect(find.text('重新检查'), findsOneWidget);
    expect(find.text('开始安装'), findsNothing);
  });
}
