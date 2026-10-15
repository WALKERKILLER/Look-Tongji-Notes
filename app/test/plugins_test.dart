import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:look_studio/core/app_state.dart';
import 'package:look_studio/core/lookd_service.dart';
import 'package:look_studio/core/plugins.dart';
import 'package:look_studio/features/plugins/plugin_views.dart';
import 'package:look_studio/features/plugins/plugins_page.dart';
import 'package:provider/provider.dart';

Map<String, dynamic> _plugin(String id, {String state = 'enabled', Map<String, dynamic> contributes = const {}}) => {
      'id': id,
      'title': id.toUpperCase(),
      'summary': 's',
      'icon': 'hub',
      'state': state,
      'enabled': state != 'disabled',
      'contributes': contributes,
      'tools': [
        {'name': '${id}__draw', 'label': '画图'},
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  PluginStore storeWith(List<Map<String, dynamic>> plugins) => PluginStore(AppState(LookdService()))..installed = plugins;

  test('contributions come from active plugins only', () {
    final store = storeWith([
      _plugin('mindmap', contributes: {
        'actions': [
          {'id': 'a', 'title': '导图', 'action': 'draw', 'surface': 'note.toolbar'},
          {'id': 'b', 'title': '模式', 'action': 'toggle', 'surface': 'composer.plus'},
        ],
        'exporters': [
          {'id': 'x', 'title': 'Anki', 'action': 'export', 'scope': 'course'},
        ],
        'blocks': ['mindmap'],
      }),
      _plugin('off', state: 'disabled', contributes: {
        'actions': [
          {'id': 'a', 'title': '停用的', 'action': 'x', 'surface': 'note.toolbar'},
        ],
        'blocks': ['graph'],
      }),
    ]);
    expect(store.entries('actions', surface: 'note.toolbar').map((e) => e.title), ['导图']);
    expect(store.entries('exporters', scope: 'course').single.pluginId, 'mindmap');
    expect(store.entries('exporters', scope: 'note'), isEmpty);
    expect(store.rendersBlock('mindmap'), isTrue);
    expect(store.rendersBlock('graph'), isFalse);
    expect(store.toolPlugin('mindmap__draw')?['id'], 'mindmap');
    expect(store.toolLabel('mindmap__draw'), '画图');
    expect(store.toolPlugin('read_note'), isNull);
    expect(pluginIcon('unknown'), Icons.extension_outlined);
  });

  testWidgets('checklist and unknown views', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(children: const [
          PluginView(view: {
            'kind': 'checklist',
            'data': {
              'title': '作业要求',
              'items': [
                {'text': '实现栈', 'done': true},
                {'text': '写测试', 'note': '覆盖空栈'},
              ],
            },
          }),
          PluginView(view: {'kind': 'graph', 'data': {'nodes': []}}),
        ]),
      ),
    ));
    expect(find.text('作业要求'), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.text('覆盖空栈'), findsOneWidget);
    expect(find.text('「graph」视图'), findsOneWidget);
  });

  testWidgets('look-view blocks render only for declared kinds', (tester) async {
    final store = storeWith([
      _plugin('demo', contributes: {'blocks': ['checklist']}),
    ]);
    Widget? declared, undeclared, broken;
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: store,
      child: MaterialApp(home: Builder(builder: (context) {
        declared = lookViewBlock(context, 'look-view', '{"kind":"checklist","data":{"items":[]}}');
        undeclared = lookViewBlock(context, 'look-view', '{"kind":"graph","data":{}}');
        broken = lookViewBlock(context, 'look-view', '{not json');
        return const SizedBox();
      })),
    ));
    expect(declared, isA<PluginView>());
    expect(undeclared, isNull);
    expect(broken, isNull);
  });

  testWidgets('consent lists the permissions and flags third-party sources', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: ConsentDialog(preview: {
        'token': 't',
        'official': false,
        'source': 'path:/tmp/cph',
        'manifest': {
          'id': 'cph',
          'title': 'CPH 连接',
          'version': '1.0.0',
          'icon': 'code',
          'permissions': [
            {'id': 'localhost', 'label': '连接本机程序'},
            {'id': 'views', 'label': '在对话中显示交互视图'},
          ],
        },
        'update': {'from': '0.9.0', 'added_permissions': ['localhost']},
      }),
    ));
    expect(find.text('更新「CPH 连接」？'), findsOneWidget);
    expect(find.text('连接本机程序'), findsOneWidget);
    expect(find.text('新增'), findsOneWidget);
    expect(find.textContaining('第三方插件，来源：path:/tmp/cph'), findsOneWidget);
  });

  testWidgets('settings form checks ranges before saving', (tester) async {
    Map<String, dynamic>? saved;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PluginSettingsForm(
            schema: const {
              'type': 'object',
              'properties': {
                'port': {'type': 'integer', 'title': '端口', 'minimum': 1, 'maximum': 65535, 'default': 27121},
                'style': {'type': 'string', 'title': '引导力度', 'enum': ['温和', '严格'], 'default': '温和'},
                'auto': {'type': 'boolean', 'title': '自动发送'},
              },
            },
            values: const {'port': 27121},
            onSave: (v) => saved = v,
          ),
        ),
      ),
    ));
    await tester.enterText(find.widgetWithText(TextField, '端口'), '70000');
    await tester.tap(find.text('保存设置'));
    await tester.pump();
    expect(find.text('应在 1–65535 之间'), findsOneWidget);
    expect(saved, isNull);

    await tester.enterText(find.widgetWithText(TextField, '端口'), '10045');
    await tester.tap(find.text('严格'));
    await tester.tap(find.text('自动发送'));
    await tester.tap(find.text('保存设置'));
    await tester.pump();
    expect(saved, {'port': 10045, 'style': '严格', 'auto': true});
  });
}
