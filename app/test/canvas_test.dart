import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:look_studio/features/canvas/canvas_course.dart';
import 'package:look_studio/features/canvas/canvas_page.dart';

const schools = [
  {'id': 'tongji', 'name': '同济大学', 'canvas': 'https://canvas.tongji.edu.cn', 'sso': 'look', 'look': true, 'emblem_url': ''},
  {'id': 'fudan', 'name': '复旦大学', 'canvas': 'https://elearning.fudan.edu.cn', 'sso': 'uis', 'look': false, 'emblem_url': '', 'note': '复旦 iCourse 暂未接入'},
];

Map<String, dynamic> connected() => {
  'schools': schools,
  'status': {
    'connected': true,
    'school': 'tongji',
    'base': 'https://canvas.tongji.edu.cn',
    'mode': 'token',
    'user': '张三',
    'token_last4': 'abcd',
    'token_auto': true,
    'expires_at': '2027-01-19T00:00:00Z',
    'synced_at': DateTime.now().millisecondsSinceEpoch,
    'courses': [
      {'id': '1', 'name': '计算机视觉 42029401', 'look_course': 'cv', 'manual': false, 'open': 2, 'total': 3},
    ],
  },
};

class Fake {
  Fake(this.state);
  Map<String, dynamic> state;
  final calls = <(String, String, Object?)>[];
  Future<dynamic> call(String m, String p, [Object? body]) async {
    calls.add((m, p, body));
    if (m == 'GET' && p == '/api/canvas') return state;
    if (p == '/api/canvas/connect') return state['status'];
    if (p.startsWith('/api/canvas/links/')) return state['status'];
    if (p == '/api/canvas/courses/1') {
      return {
        'course': state['status']['courses'][0],
        'assignments': [
          {'id': '11', 'name': '第一次作业', 'due_at': DateTime.now().add(const Duration(hours: 5)).toUtc().toIso8601String(), 'done': false, 'html_url': 'https://x/a/11', 'points_possible': 10},
          {'id': '12', 'name': '第零次作业', 'due_at': '2026-09-01T15:59:59Z', 'done': true, 'submission': {'workflow_state': 'graded', 'score': 9}},
        ],
        'announcements': [
          {'id': '21', 'title': '调课通知', 'message': '<p>周三&nbsp;停课</p>', 'posted_at': '2026-10-20T02:00:00Z', 'author': {'display_name': '李老师'}},
        ],
      };
    }
    if (p == '/api/canvas/courses/1/files') return [{'id': '9', 'display_name': '讲义.pdf', 'size': 2048}, {'id': '8', 'display_name': '答案.pdf', 'locked_for_user': true}];
    if (p == '/api/canvas/files/9/download') return {'path': 'courses/计算机视觉/Canvas/讲义.pdf'};
    return {};
  }
}

Widget wrap(Widget w) => MaterialApp(home: w);

void tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('connect form: Fudan asks for UIS credentials and posts them', (tester) async {
    tall(tester);
    final api = Fake({'schools': schools, 'status': {'connected': false}});
    await tester.pumpWidget(wrap(CanvasPage(api: api.call, events: const Stream.empty(), lookCourses: const [], lookSignedIn: true)));
    await tester.pumpAndSettle();
    expect(find.text('同济大学'), findsOneWidget);
    expect(find.text('其他学校'), findsOneWidget);
    expect(find.text('沿用 Look Studio 的同济登录'), findsOneWidget);

    await tester.tap(find.text('复旦大学'));
    await tester.pumpAndSettle();
    expect(find.text('复旦 iCourse 暂未接入'), findsOneWidget);
    final connect = find.widgetWithText(FilledButton, '连接');
    expect(tester.widget<FilledButton>(connect).onPressed, isNull);
    await tester.enterText(find.widgetWithText(TextField, '复旦 UIS 学号'), '23300000000');
    await tester.enterText(find.widgetWithText(TextField, 'UIS 密码'), 'pw');
    await tester.pump();
    await tester.tap(connect);
    await tester.pumpAndSettle();
    final post = api.calls.firstWhere((c) => c.$2 == '/api/canvas/connect');
    expect(post.$3, {'school': 'fudan', 'base': 'https://elearning.fudan.edu.cn', 'mode': 'sso', 'username': '23300000000', 'password': 'pw'});
  });

  testWidgets('connect form: another school needs an https address and a pasted token', (tester) async {
    tall(tester);
    final api = Fake({'schools': schools, 'status': {'connected': false}});
    await tester.pumpWidget(wrap(CanvasPage(api: api.call, events: const Stream.empty(), lookCourses: const [], lookSignedIn: false)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('其他学校'));
    await tester.pumpAndSettle();
    expect(find.text('打开 Canvas 设置页'), findsOneWidget);
    final connect = find.widgetWithText(FilledButton, '连接');
    await tester.enterText(find.widgetWithText(TextField, 'Canvas 地址'), 'http://canvas.example.edu');
    await tester.enterText(find.widgetWithText(TextField, '访问令牌'), 'tok-1234');
    await tester.pump();
    expect(tester.widget<FilledButton>(connect).onPressed, isNull);
    await tester.enterText(find.widgetWithText(TextField, 'Canvas 地址'), 'https://canvas.example.edu');
    await tester.pump();
    await tester.tap(connect);
    await tester.pumpAndSettle();
    final post = api.calls.firstWhere((c) => c.$2 == '/api/canvas/connect');
    expect(post.$3, {'school': 'other', 'base': 'https://canvas.example.edu', 'mode': 'token', 'token': 'tok-1234'});
  });

  testWidgets('connected: status shows only the last 4 token characters and edits links', (tester) async {
    tall(tester);
    final api = Fake(connected());
    await tester.pumpWidget(wrap(CanvasPage(api: api.call, events: const Stream.empty(), lookCourses: const [(id: 'cv', title: '计算机视觉'), (id: 'os', title: '操作系统')])));
    await tester.pumpAndSettle();
    expect(find.textContaining('····abcd'), findsOneWidget);
    expect(find.textContaining('自动续期'), findsOneWidget);
    expect(find.text('1 门课程 · 2 项作业待交'), findsOneWidget);
    expect(find.text('自动：计算机视觉'), findsOneWidget);
    await tester.tap(find.text('自动：计算机视觉'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('操作系统'));
    await tester.pumpAndSettle();
    final put = api.calls.lastWhere((c) => c.$1 == 'PUT');
    expect(put.$2, '/api/canvas/links/1');
    expect(put.$3, {'course': 'os', 'auto': false});
  });

  testWidgets('course view lists assignments, downloads files and shows announcements', (tester) async {
    final api = Fake(connected());
    await tester.pumpWidget(wrap(Scaffold(body: CanvasCourseView(canvasId: '1', name: '计算机视觉', api: api.call, libraryRoot: '/lib'))));
    await tester.pumpAndSettle();
    expect(find.text('第一次作业'), findsOneWidget);
    expect(find.textContaining('还剩'), findsOneWidget);
    expect(find.textContaining('已批改 · 9 分'), findsOneWidget);

    await tester.tap(find.text('课件'));
    await tester.pumpAndSettle();
    expect(find.textContaining('老师已锁定'), findsOneWidget);
    await tester.tap(find.byTooltip('下载到课程文件夹').first);
    await tester.pumpAndSettle();
    final dl = api.calls.firstWhere((c) => c.$2 == '/api/canvas/files/9/download');
    expect(dl.$3, {'course': '1'});
    expect(find.byTooltip('打开'), findsOneWidget);

    await tester.tap(find.text('公告'));
    await tester.pumpAndSettle();
    expect(find.text('调课通知'), findsOneWidget);
    expect(find.text('周三 停课'), findsOneWidget);
  });

  testWidgets('phone width lays out the form, the connection and the course view without overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final looks = const [(id: 'cv', title: '计算机视觉与模式识别（双语）'), (id: 'os', title: '操作系统')];
    await tester.pumpWidget(wrap(CanvasPage(api: Fake({'schools': schools, 'status': {'connected': false}}).call, events: const Stream.empty(), lookCourses: looks, lookSignedIn: true)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('访问令牌'));
    await tester.pumpAndSettle();
    // Canvas names carry the term and the class code; the link goes under the name.
    const long = '(2026-2027-1)-42029401-01 计算机视觉与模式识别（双语）张三、李四';
    final st = connected();
    (st['status'] as Map)['courses'] = [
      {'id': '1', 'name': long, 'look_course': 'cv', 'manual': false, 'open': 2, 'total': 3},
    ];
    await tester.pumpWidget(wrap(CanvasPage(key: const ValueKey(2), api: Fake(st).call, events: const Stream.empty(), lookCourses: looks)));
    await tester.pumpAndSettle();
    expect(find.text('课程关联'), findsOneWidget);
    expect(tester.getTopLeft(find.byType(ActionChip)).dy, greaterThan(tester.getBottomLeft(find.text(long)).dy));
    await tester.pumpWidget(wrap(Scaffold(body: CanvasCourseView(canvasId: '1', name: '计算机视觉 42029401', api: Fake(connected()).call, libraryRoot: '/lib'))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('课件'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  test('assignment state words', () {
    expect(assignmentState({'done': true}).label, '已完成');
    expect(assignmentState({'due_at': '2020-01-01T00:00:00Z'}).alert, isTrue);
    expect(assignmentState({}).label, '没有截止时间');
  });
}
