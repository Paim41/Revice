import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revice_android/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.revice/monitoring');
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  testWidgets('Onboarding persists and channel values reach dashboard', (
    tester,
  ) async {
    var saved = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'preferences') return {'onboarded': saved};
          if (call.method == 'savePreferences') {
            saved = true;
            return null;
          }
          return {
            'observedAt': DateTime.now().millisecondsSinceEpoch,
            'device': {'model': 'Test phone'},
            'battery': {'percentage': 73, 'charging': true},
            'storage': {
              'totalBytes': 10737418240,
              'availableBytes': 5368709120,
            },
          };
        });
    await tester.pumpWidget(const ReviceApp());
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Monitor this device'), 200);
    await tester.ensureVisible(find.text('Monitor this device'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Monitor this device'));
    await tester.pumpAndSettle();
    expect(saved, isTrue);
    expect(find.text('73.00%'), findsOneWidget);
    expect(find.text('Test phone'), findsOneWidget);
    expect(find.text('Charging'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('View device details →'), 100);
    await tester.ensureVisible(find.text('View device details →'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View device details →'));
    await tester.pumpAndSettle();
    expect(find.text('Health status'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.insights_rounded));
    await tester.pumpAndSettle();
    expect(find.text('History starts with observations'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.devices_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Your devices'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.notifications_none_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Alerts & activity'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Reduce motion'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    await tester.scrollUntilVisible(find.text('Developer Credits'), 200);
    await tester.tap(find.text('Developer Credits'));
    await tester.pumpAndSettle();
    expect(find.text('Paim41'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.tune_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Read failures show error rather than fabricated metrics', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'preferences') return {'onboarded': true};
          throw PlatformException(code: 'READ');
        });
    await tester.pumpWidget(const ReviceApp());
    await tester.pumpAndSettle();
    expect(find.textContaining('could not read'), findsOneWidget);
    expect(find.textContaining('No device reading yet'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
