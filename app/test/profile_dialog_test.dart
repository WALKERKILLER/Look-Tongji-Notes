import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:look_studio/core/app_state.dart';
import 'package:look_studio/core/lookd_service.dart';
import 'package:look_studio/core/profile.dart';
import 'package:look_studio/features/profile/profile_dialog.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('the profile dialog fits a phone: the six generated avatars share the row', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final profile = await UserProfile.load();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: profile),
        ChangeNotifierProvider(create: (_) => AppState(LookdService())),
      ],
      child: MaterialApp(
        home: Builder(builder: (context) => TextButton(onPressed: () => showProfileDialog(context), child: const Text('open'))),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('灵感'), findsOneWidget);
  });
}
