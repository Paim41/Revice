import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revice_android/core/theme.dart';
import 'package:revice_android/features/developer_credits.dart';

void main() {
  const channel = MethodChannel('app.revice/monitoring');
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  testWidgets('Credits use installed metadata and browser failure fallback', (
    tester,
  ) async {
    var opened = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'appMetadata') {
            return {'version': '9.8.7', 'build': '42'};
          }
          if (call.method == 'openDeveloperProfile') {
            opened = true;
            return false;
          }
          return null;
        });
    await tester.pumpWidget(
      MaterialApp(theme: reviceTheme(), home: const DeveloperCredits()),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Version: 9.8.7'));
    expect(find.text('Build: 42'), findsOneWidget);
    await tester.ensureVisible(find.text('Open GitHub'));
    await tester.tap(find.text('Open GitHub'));
    await tester.pumpAndSettle();
    expect(opened, isTrue);
    expect(find.textContaining('Could not open a browser'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
