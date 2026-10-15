import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:look_studio/features/practice/practice_page.dart';
import 'package:look_studio/theme/prefs.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _quiz() => {
      'id': 'z1',
      'title': '傅里叶变换自测',
      'lecture_id': 'L1',
      'difficulty': 'medium',
      'count': 2,
      'attempts': 0,
      'questions': [
        {
          'stem': '矩形脉冲的频谱是？',
          'topic': '典型信号',
          'hint': '想想时域有限宽度对应什么',
          'options': [
            {'text': 'sinc 函数', 'rationale': '矩形窗的傅里叶变换'},
            {'text': '冲激函数', 'rationale': '那是直流信号的频谱'},
          ],
          'answer': 0,
          'ref': 'look://lecture/L1?t=120',
        },
        {
          'stem': '时域卷积对应频域的？',
          'topic': '性质',
          'options': [
            {'text': '相乘', 'rationale': '卷积定理'},
            {'text': '相加', 'rationale': '相加对应线性'},
          ],
          'answer': 0,
          'ref': 'look://slide/L1/3',
        },
      ],
    };

void main() {
  testWidgets('answer, reveal, finish and retry mistakes', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await UiPrefs.load();
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final posted = <Object?>[];
    Future<dynamic> fetch(String method, String path, [Object? body]) async {
      if (method == 'POST') {
        posted.add(body);
        return {
          'attempt': {'correct': 1, 'total': 2},
          'best': {'correct': 1, 'total': 2},
        };
      }
      return _quiz();
    }

    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: prefs,
      child: MaterialApp(home: PracticePage(quizId: 'z1', fetch: fetch)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('1 / 2'), findsOneWidget);

    // Next is disabled until an answer is chosen.
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '下一题')).onPressed, isNull);
    await tester.tap(find.text('提示'));
    await tester.pump();
    expect(find.text('想想时域有限宽度对应什么'), findsOneWidget);

    await tester.tap(find.text('冲激函数'));
    await tester.pumpAndSettle();
    expect(find.text('你的选择'), findsOneWidget);
    expect(find.text('正确答案'), findsOneWidget);
    expect(find.text('矩形窗的傅里叶变换'), findsOneWidget); // rationales revealed
    expect(find.text('查看出处'), findsOneWidget);

    await tester.tap(find.text('下一题'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.pumpAndSettle();
    expect(find.text('正确答案'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(posted.single, isA<Map>().having((m) => m['answers'], 'answers', [1, 0]));
    expect(find.textContaining('最好成绩 1/2'), findsOneWidget);
    expect(find.text('按知识点'), findsOneWidget);

    await tester.tap(find.text('重做错题 1'));
    await tester.pumpAndSettle();
    expect(find.text('1 / 1'), findsOneWidget);
    expect(find.text('矩形脉冲的频谱是？'), findsOneWidget);
    await tester.tap(find.text('sinc 函数'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(find.text('重做完成'), findsOneWidget);
    expect(posted, hasLength(1)); // retakes are not recorded
  });
}
