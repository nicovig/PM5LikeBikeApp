import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pm5_bike/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'the live screen starts, pauses, and stays inside an iPhone 15 frame',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const ProviderScope(child: Pm5App()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Démarrer'), findsOneWidget);
      expect(find.text('Séance libre'), findsOneWidget);
      expect(find.text('WATTS'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.drag(find.byType(Slider), const Offset(120, 0));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Démarrer'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Pause'));
      await tester.pump();
      expect(find.text('Reprendre'), findsOneWidget);

      await tester.tap(find.text('Calibration'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Loi de puissance'), findsOneWidget);

      await tester.tap(find.text('Réglages'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Source de cadence'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the live screen fits in landscape', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(852, 393);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ProviderScope(child: Pm5App()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Démarrer'), findsOneWidget);
    expect(find.text('Séance libre'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a guided workout can be armed on the live screen', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ProviderScope(child: Pm5App()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Séance libre'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Répétitions'), findsOneWidget);

    await tester.tap(find.text('6 × 2 min + récup'));
    await tester.pump();
    final wattsField = find.byKey(const ValueKey('step-watts-0'));
    await tester.ensureVisible(wattsField);
    await tester.enterText(wattsField, '180');
    await tester.pump();

    await tester.tap(find.text('Utiliser'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('6 × (2:00 à 180 W + 2:00 récup)'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Démarrer'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('1/6'), findsOneWidget);
    expect(find.text('180 W'), findsOneWidget);
    expect(find.text('Démarrer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
