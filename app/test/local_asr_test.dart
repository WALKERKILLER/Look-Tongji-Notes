import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:look_studio/features/settings/asr_bench.dart';
import 'package:look_studio/features/settings/local_asr_page.dart';

Map<String, dynamic> model(
  String id,
  String name,
  double cer,
  double rtf,
  int mb, {
  List<String> tags = const [],
  bool installed = false,
}) => {
  'id': id,
  'name': name,
  'org': 'Org',
  'langs': '中',
  'summary': '$name 简介',
  'punct': true,
  'license': 'Apache-2.0',
  'license_url': 'https://example.org/l',
  'upstream': 'https://example.org/u',
  'tags': tags,
  'bench': {'cer': cer, 'source': '论文', 'source_url': 'https://example.org/p'},
  'measured': {'rtf': rtf, 'peak_mb': mb},
  'size': 1000000000,
  'extra': 30000000,
  'installed': installed,
  'sources': ['hf-mirror'],
};

Map<String, dynamic> state({String active = '', Map<String, dynamic>? install, bool installed = false, Map<String, dynamic>? location}) => {
  'active': active,
  'source': 'hf-mirror',
  'custom_url': '',
  'github_proxy': '',
  'threads': 4,
  'status': {
    'supported': true,
    'platform': 'linux/amd64',
    'cpus': 8,
    'reference': {'machine': '测试机', 'clip': '测试音频'},
    'install': install ?? {'state': 'idle'},
    'location': location ?? {'dir': '/data/asr', 'default': '/data/asr', 'custom': false, 'used': 0, 'free': 50000000000},
    'sources': [
      {'id': 'hf-mirror', 'name': 'HF-Mirror', 'note': '镜像'},
      {'id': 'custom', 'name': '自定义地址', 'note': '模板'},
    ],
    'models': [
      model('fast', 'Fast', 7.4, 0.02, 470, tags: ['fast']),
      model('best', 'Best', 6.9, 0.16, 2400, tags: ['recommended'], installed: installed),
    ],
  },
};

void main() {
  testWidgets('board sorts by the chosen measure and reports values to screen readers', (tester) async {
    final rows = benchRows([model('a', 'A', 7.4, 0.02, 470), model('b', 'B', 6.9, 0.16, 2400)]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            child: AsrBenchBoard(metrics: benchMetrics({}), rows: rows, animate: false),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    double y(String t) => tester.getTopLeft(find.text(t)).dy;
    expect(y('B'), lessThan(y('A')), reason: 'lower error rate first');
    await tester.tap(find.text('按转写用时'));
    await tester.pumpAndSettle();
    expect(y('A'), lessThan(y('B')), reason: 'faster first');
    expect(find.text('1.8 分钟'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^A，错字率 7\.4%，转写用时 1\.8 分钟，内存 0\.5 GB$')), findsOneWidget);
  });

  testWidgets('downloads a model, follows progress and offers to use it', (tester) async {
    final events = StreamController<Map<String, dynamic>>.broadcast();
    addTearDown(events.close);
    final calls = <(String, String, Object?)>[];
    var current = state();
    Future<dynamic> api(String method, String path, [Object? body]) async {
      calls.add((method, path, body));
      if (method == 'POST' && path == '/api/asr/local/install') {
        current = state(install: {'state': 'running', 'model': 'best', 'step': '下载'});
      }
      return current;
    }

    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: LocalAsrPage(api: api, events: events.stream),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('在本机识别'), findsOneWidget);
    expect(find.textContaining('错字率来源'), findsOneWidget, reason: 'the recommended model is focused');

    await tester.tap(find.textContaining('（含引擎等）').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final post = calls.firstWhere((c) => c.$1 == 'POST');
    expect(post.$2, '/api/asr/local/install');
    expect(post.$3, {'model': 'best'});

    events.add({
      'type': 'asr_local',
      'data': {'state': 'running', 'model': 'best', 'step': '下载 models/decoder', 'done': 500000000, 'total': 1000000000, 'speed': 5000000},
    });
    await tester.pump();
    expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, 0.5);
    expect(find.text('暂停'), findsOneWidget);

    current = state(installed: true);
    events.add({
      'type': 'asr_local',
      'data': {'state': 'done', 'model': 'best'},
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text('使用这个模型'));
    await tester.pumpAndSettle();
    expect(calls.any((c) => c.$1 == 'PUT' && (c.$3 as Map)['asr.local.model'] == 'best'), isTrue);
  });

  testWidgets('custom source shows the template field and saves it', (tester) async {
    final calls = <(String, String, Object?)>[];
    var current = state();
    Future<dynamic> api(String method, String path, [Object? body]) async {
      calls.add((method, path, body));
      if (method == 'PUT') current = {...state(), 'source': (body as Map)['asr.local.source'] ?? current['source']};
      return current;
    }

    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: LocalAsrPage(api: api, events: const Stream.empty()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('地址模板'), findsNothing);
    await tester.tap(find.text('自定义地址'));
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.$1 == 'PUT').last.$3, {'asr.local.source': 'custom'});
    expect(find.text('地址模板'), findsOneWidget);
    expect(find.textContaining('{repo} 会换成模型仓库名'), findsOneWidget);
  });

  testWidgets('moves the models to a folder the user picks', (tester) async {
    final calls = <(String, String, Object?)>[];
    var current = state(location: {'dir': '/data/asr', 'default': '/data/asr', 'custom': false, 'used': 1500000000, 'free': 1000000000});
    Future<dynamic> api(String method, String path, [Object? body]) async {
      calls.add((method, path, body));
      if (method == 'PUT' && path == '/api/asr/local/location') {
        current = state(
          install: {'state': 'running', 'step': '移动到新位置', 'done': 0, 'total': 1500000000},
          location: {'dir': '/data/asr', 'default': '/data/asr', 'custom': false, 'used': 1500000000, 'free': 1000000000},
        );
        return current['status'];
      }
      return current;
    }

    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: LocalAsrPage(api: api, events: const Stream.empty())));
    await tester.pumpAndSettle();
    expect(find.text('默认位置'), findsOneWidget);
    expect(find.textContaining('剩余空间不多'), findsOneWidget);

    // No native picker in tests: it asks for the path instead.
    await tester.tap(find.text('更改位置'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50))); // the channel answers on real time
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '文件夹路径'), '/mnt/big/models');
    await tester.tap(find.widgetWithText(FilledButton, '选择'));
    await tester.pumpAndSettle();
    expect(find.text('把已下载的模型一起移过去？'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '移动'));
    await tester.pump();
    await tester.pump();
    final put = calls.lastWhere((c) => c.$1 == 'PUT');
    expect(put.$2, '/api/asr/local/location');
    expect(put.$3, {'dir': '/mnt/big/models', 'move': true});
    expect(find.text('正在移动模型'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.ancestor(of: find.text('更改位置'), matching: find.byWidgetPredicate((w) => w is FilledButton))).onPressed, isNull);
  });
}
