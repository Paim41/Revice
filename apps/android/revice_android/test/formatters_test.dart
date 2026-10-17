import 'package:flutter_test/flutter_test.dart';
import 'package:revice_android/core/formatters.dart';
import 'package:revice_android/models/local_snapshot.dart';

void main() {
  test('Percentages round with two decimal places and preserve raw values', () {
    for (final entry in <num, String>{
      0: '0.00%',
      100: '100.00%',
      52.99999999: '53.00%',
      12.341: '12.34%',
      12.346: '12.35%',
      1.125: '1.13%',
    }.entries) {
      final snapshot = LocalSnapshot.fromMap({
        'observedAt': 0,
        'battery': {'percentage': entry.key},
      });
      expect(formatPercentage(entry.key), entry.value);
      expect(snapshot.batteryLabel, entry.value);
      expect(snapshot.percentage, entry.key);
    }
    expect(formatPercentage(null), 'Unavailable');
  });
}
