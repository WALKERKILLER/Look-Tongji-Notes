import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:look_studio/core/api.dart';
import 'package:look_studio/core/models.dart';
import 'package:look_studio/features/courses/local_course_dialog.dart';

class LocalApi extends Api {
  LocalApi() : super('http://localhost', 'test');
  int creates = 0;
  bool failSecond = true;
  final uploaded = <String>[];
  @override
  Future<dynamic> createLocalCourse(String title, {String teacher = ''}) async {
    creates++;
    return {'id': 'local-test'};
  }

  @override
  Future<dynamic> importLocalVideo(
    String course,
    String name,
    Stream<List<int>> data,
    int length,
  ) async {
    await data.drain<void>();
    if (name == '02.mp4' && failSecond) throw ApiError(400, '无法读取视频');
    uploaded.add(name);
    return {'id': 'lesson'};
  }
}

void main() {
  testWidgets(
    'local course creation validates name and retries remaining uploads',
    (tester) async {
      final api = LocalApi();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocalCourseDialog(
              api: api,
              pickFiles: () async => [
                XFile.fromData(Uint8List.fromList([1]), path: '02.mp4'),
                XFile.fromData(Uint8List.fromList([2]), path: '01.mp4'),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.widgetWithText(FilledButton, '新建本地课程'));
      await tester.pump();
      expect(find.text('请填写课程名称'), findsOneWidget);
      expect(api.creates, 0);
      await tester.enterText(find.byType(TextFormField).first, '操作系统期末速成');
      await tester.tap(find.text('选择视频'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '新建本地课程'));
      await tester.pumpAndSettle();
      expect(api.creates, 1);
      expect(api.uploaded, ['01.mp4']);
      expect(find.textContaining('02.mp4：无法读取视频'), findsOneWidget);
      api.failSecond = false;
      await tester.tap(find.widgetWithText(FilledButton, '重试'));
      await tester.pumpAndSettle();
      expect(api.creates, 1);
      expect(api.uploaded, ['01.mp4', '02.mp4']);
    },
  );

  test('local course has a distinct label', () {
    expect(Course({'id': 'local-test', 'term': 'local'}).termLabel, '本地课程');
    expect(Course({'id': '40309', 'term': '20261'}).isLocal, false);
  });
}
