import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:look_studio/core/api.dart';
import 'package:look_studio/features/login/login_page.dart';

const schools = [
  {'id': 'tongji', 'name': '同济大学', 'look': true, 'emblem_url': ''},
  {'id': 'fudan', 'name': '复旦大学', 'look': true, 'emblem_url': ''},
  {'id': 'other', 'name': '只有 Canvas 的学校', 'look': false, 'emblem_url': ''},
];

class Fake {
  final calls = <(String, String, Object?)>[];
  Object? loginError;
  Future<dynamic> call(String m, String p, [Object? body]) async {
    calls.add((m, p, body));
    if (p == '/api/schools') return schools;
    if (p == '/api/auth/login' && loginError != null) throw loginError!;
    return {'status': 'active'};
  }
}

void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 780);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Widget wrap(Fake api) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: LoginForm(brand: true, api: api.call),
        ),
      ),
    );

void main() {
  testWidgets('a phone picks Fudan among the schools with lecture replays and signs in to it', (tester) async {
    phone(tester);
    final api = Fake();
    await tester.pumpWidget(wrap(api));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('同济大学'), findsOneWidget);
    expect(find.text('复旦大学'), findsOneWidget);
    expect(find.text('只有 Canvas 的学校'), findsNothing);
    expect(find.textContaining('look.tongji.edu.cn'), findsOneWidget);

    await tester.tap(find.text('复旦大学'));
    await tester.pumpAndSettle();
    expect(find.textContaining('WebVPN'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '学号 / 工号'), '21300');
    await tester.enterText(find.widgetWithText(TextField, '密码'), 'secret');
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();
    final login = api.calls.singleWhere((c) => c.$2 == '/api/auth/login');
    expect(login.$1, 'POST');
    expect(login.$3, {'school': 'fudan', 'username': '21300', 'password': 'secret', 'captcha': '', 'remember': true});
    expect(tester.takeException(), isNull);
  });

  testWidgets('a rejected sign-in shows the reason next to the form', (tester) async {
    phone(tester);
    final api = Fake()..loginError = ApiError(401, '复旦 UIS 学号或密码错误');
    await tester.pumpWidget(wrap(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('复旦大学'));
    await tester.enterText(find.widgetWithText(TextField, '学号 / 工号'), '21300');
    await tester.enterText(find.widgetWithText(TextField, '密码'), 'wrong');
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();
    expect(find.text('复旦 UIS 学号或密码错误'), findsOneWidget);
  });
}
