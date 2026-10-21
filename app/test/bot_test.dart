import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:look_studio/features/assistant/bot_avatar.dart';
import 'package:look_studio/features/assistant/bot_page.dart';
import 'package:look_studio/features/assistant/bot_widgets.dart';
import 'package:look_studio/theme/prefs.dart';
import 'package:look_studio/widgets/organic_shapes.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _host(Widget child, {bool reduceMotion = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Scaffold(body: Center(child: child)),
      ),
    );

void main() {
  test('every bot shape is a smooth profile without lobes or creases', () {
    for (final e in kBotShapes.values) {
      final r = shapeRadii(e.$1);
      expect(r.length, kShapeSamples);
      expect(r.every((v) => v > 0.5 && v <= 1.0), isTrue, reason: '${e.$1}');
      // The second difference spikes at a crease and ripples on scalloped
      // outlines (the retired cloud reached 0.17, the cookie 0.006).
      var bend = 0.0;
      for (var i = 0; i < r.length; i++) {
        final d = (r[(i + 1) % r.length] - 2 * r[i] + r[(i - 1 + r.length) % r.length]).abs();
        if (d > bend) bend = d;
      }
      expect(bend, lessThan(0.003), reason: '${e.$1}');
    }
  });

  testWidgets('the mascot draws every shape and mood, and morphs between shapes', (tester) async {
    for (final shape in kBotShapes.keys) {
      for (final mood in BotMood.values) {
        await tester.pumpWidget(_host(BotAvatar(size: 64, shape: shape, mood: mood, animate: false)));
      }
    }
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(_host(const BotAvatar(size: 96, shape: 'pebble', color: 'teal')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(_host(const BotAvatar(size: 96, shape: 'ghost', color: 'teal', mood: BotMood.dreaming)));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    await tester.pumpWidget(_host(const BotAvatar(size: 96, shape: 'droplet', color: 'rose', mood: BotMood.notify), reduceMotion: true));
    await tester.pump(const Duration(seconds: 7));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('ears, antennas and headphones stay inside the mascot\'s box', (tester) async {
    final key = GlobalKey();
    for (final shape in kBotShapes.keys) {
      for (final mood in [BotMood.idle, BotMood.happy, BotMood.confused, BotMood.dreaming, BotMood.notify]) {
        // A 100 px mascot in the middle of a 200 px transparent canvas.
        await tester.pumpWidget(Center(
          child: RepaintBoundary(
            key: key,
            child: SizedBox.square(dimension: 200, child: Center(child: BotAvatar(size: 100, shape: shape, mood: mood, animate: false))),
          ),
        ));
        final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final bytes = (await tester.runAsync(() async => (await boundary.toImage()).toByteData(format: ui.ImageByteFormat.rawRgba)))!;
        var inside = true;
        for (var i = 0; i < 200 * 200; i++) {
          final x = i % 200, y = i ~/ 200;
          if (bytes.getUint8(i * 4 + 3) > 40 && (x < 50 || x >= 150 || y < 50 || y >= 150)) inside = false;
        }
        expect(inside, isTrue, reason: '$shape $mood');
      }
    }
  });

  test('bot colours come from fixed roles: the same bot in light and dark', () {
    final light = ColorScheme.fromSeed(seedColor: Colors.blue);
    final dark = ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.dark);
    expect(botPalette(light, 'theme').body, light.primaryFixedDim);
    for (final k in kBotColorKeys) {
      final a = botPalette(light, k), b = botPalette(dark, k);
      expect(a.body, b.body, reason: k);
      // The face screen stands out from the shell (WCAG contrast of at least 4.5:1).
      final l1 = a.body.computeLuminance(), l2 = a.ink.computeLuminance();
      expect((l1 + 0.05) / (l2 + 0.05), greaterThan(4.5), reason: k);
      // The eyes glow on the dark face screen.
      final l3 = a.eye.computeLuminance();
      expect((l3 + 0.05) / (l2 + 0.05), greaterThan(7), reason: k);
    }
    expect(botPalette(light, 'teal').body, isNot(botPalette(light, 'rose').body));
    expect(kBotColorKeys.length, kSeedPalette.length + 1);
    expect(botColorLabel('teal'), kSeedPalette[1].$1);
  });

  testWidgets('a proposal card applies once, then offers undo', (tester) async {
    final calls = <String>[];
    var p = <String, dynamic>{'id': 'p1', 'kind': 'download', 'title': '下载 2 节的视频', 'lines': ['第 1 节', '第 2 节'], 'state': 'pending', 'undoable': true};
    late StateSetter set;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (context, s) {
          set = s;
          return ProposalCard(
            proposal: p,
            onApply: () async {
              calls.add('apply');
              set(() => p = {...p, 'state': 'applied'});
            },
            onDismiss: () async => calls.add('dismiss'),
            onUndo: () async {
              calls.add('undo');
              set(() => p = {...p, 'state': 'undone'});
            },
          );
        }),
      ),
    ));
    expect(find.text('第 2 节'), findsOneWidget);
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    expect(calls, ['apply']);
    expect(find.text('应用'), findsNothing);
    expect(find.text('已应用'), findsOneWidget);
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(calls, ['apply', 'undo']);
    expect(find.text('已撤销'), findsOneWidget);
    expect(find.text('撤销'), findsNothing);
  });

  testWidgets('a failing apply shows the reason on the card', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ProposalCard(
          proposal: const {'id': 'p1', 'kind': 'task', 'title': '定时任务', 'state': 'pending'},
          onApply: () async => throw Exception('这张卡片已过期'),
          onDismiss: () async {},
          onUndo: () async {},
        ),
      ),
    ));
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    expect(find.textContaining('这张卡片已过期'), findsOneWidget);
    expect(find.text('应用'), findsOneWidget);
  });

  testWidgets('an operation chip undoes once', (tester) async {
    var undone = 0;
    var done = false;
    late StateSetter set;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (context, s) {
          set = s;
          return AppOpChip(
            label: '已调整 界面字号',
            icon: Icons.check_circle_outline_rounded,
            done: done,
            onAction: () async {
              undone++;
              set(() => done = true);
            },
          );
        }),
      ),
    ));
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(undone, 1);
    expect(find.text('已撤销 · 已调整 界面字号'), findsOneWidget);
    expect(find.text('撤销'), findsNothing);
  });

  testWidgets('the memory editor names new files and refuses bad names', (tester) async {
    final saved = <(String, String)>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: MemoryEditor(path: null, content: '', save: (p, c) async => saved.add((p, c)))),
    ));
    await tester.enterText(find.byType(TextField).first, 'Bad Name');
    await tester.enterText(find.byType(TextField).last, '每周日复习');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(saved, isEmpty);
    expect(find.textContaining('小写字母'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'weekly-review');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(saved, [('notes/weekly-review.md', '每周日复习')]);
  });

  test('bot setting changes apply as a whole or not at all', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await UiPrefs.load();
    prefs.applyJson({'textScale': 1.2, 'lecturesNewestFirst': true});
    expect(prefs.textScale, 1.2);
    expect(prefs.lecturesNewestFirst, isTrue);
    prefs.applyJson({'textScale': 1.4, 'themeMode': 'purple'});
    expect(prefs.textScale, 1.2);
    expect(prefs.themeMode, ThemeMode.system);
    expect(prefs.toJson()['lecturesNewestFirst'], isTrue);
  });
}
