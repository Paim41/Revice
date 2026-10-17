import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revice_android/core/theme.dart';
import 'package:revice_android/features/device_overview.dart';
import 'package:revice_android/services/cloud_service.dart';

void main() {
  testWidgets(
    'Overview includes Android and Windows, excludes this phone, and opens details',
    (tester) async {
      final cloud = CloudService()..deviceId = 'local';
      Map<String, dynamic> device(String name, String platform) => {
        'name': name,
        'platform': platform,
        'latest': {
          'observedAt': DateTime.now().toUtc().toIso8601String(),
          'battery': {'percentage': 52.99999999, 'charging': true},
          'storage': {'totalBytes': 2147483648, 'availableBytes': 1073741824},
        },
      };
      cloud.devices.addAll({
        'local': device('This phone', 'android'),
        'phone': device('Second Android', 'android'),
        'pc': device('Windows PC', 'windows'),
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: reviceTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: RegisteredOverview(cloud: cloud),
            ),
          ),
        ),
      );
      expect(find.text('Second Android'), findsOneWidget);
      expect(find.text('Windows PC'), findsOneWidget);
      expect(find.text('This phone'), findsNothing);
      expect(find.textContaining('53.00%'), findsNWidgets(2));
      expect(find.textContaining('Storage 50.00% used'), findsNWidgets(2));
      for (final card in tester.widgetList<Card>(find.byType(Card))) {
        expect(card.margin, deviceCardMargin);
      }
      await tester.ensureVisible(find.text('Windows PC'));
      await tester.tap(find.text('Windows PC'));
      await tester.pumpAndSettle();
      expect(find.text('Windows PC'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );
  test('Stale and missing observations remain truthful', () {
    final text = deviceSummary({
      'platform': 'windows',
      'latest': {'observedAt': '2020-01-01T00:00:00Z'},
    });
    expect(text, contains('Stale'));
    expect(text, contains('Battery unavailable'));
    expect(text, contains('Storage unavailable'));
    expect(
      deviceSummary({'platform': 'android'}),
      contains('Awaiting first report'),
    );
  });
  test('Selected navigation uses lime for icon and label', () {
    final nav = reviceTheme().navigationBarTheme;
    expect(nav.iconTheme!.resolve({WidgetState.selected})!.color, lime);
    expect(nav.labelTextStyle!.resolve({WidgetState.selected})!.color, lime);
  });
}
