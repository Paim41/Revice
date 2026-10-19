import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revice_android/core/formatters.dart';
import 'package:revice_android/features/device_name_dialog.dart';

void main() {
  test('Compact percentages validate and round without modifying values', () {
    expect(compactPercentage(44, battery: true), '44%');
    expect(compactPercentage(52.99999999, battery: true), '53%');
    expect(compactPercentage(65.90), '65.9%');
    expect(compactPercentage(76), '76%');
    for (final value in [null, double.nan, double.infinity, -1, 101]) {
      expect(compactPercentage(value), 'N/A');
    }
    expect(platformLabel('windows'), 'Windows');
    expect(platformLabel('android'), 'Android');
  });
  test('Names preserve Unicode and capitalization, reject invalid input', () {
    expect(deviceNameError('  paIM 家 📱  '), isNull);
    for (final name in ['', '   ', 'a\nb', 'a\u0000b', 'x' * 41]) {
      expect(deviceNameError(name), isNotNull);
    }
  });
  testWidgets('Rename validates, reports network failure, retries and trims', (
    tester,
  ) async {
    var fail = true;
    String? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => editDeviceName(
                context,
                initial: 'Old Name',
                save: (value) async {
                  if (fail) throw StateError('offline');
                  saved = value;
                },
              ),
              child: const Text('Rename'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(find.text('Old Name'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a device name.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '  paIM 家  ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not save'), findsOneWidget);
    expect(saved, isNull);
    fail = false;
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved, 'paIM 家');
    expect(find.byType(AlertDialog), findsNothing);
  });
}
