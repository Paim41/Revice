import 'package:flutter_test/flutter_test.dart';
import 'package:revice_android/models/local_snapshot.dart';

void main() {
  LocalSnapshot parse(Map<String, Object?> extra) =>
      LocalSnapshot.fromMap({'observedAt': 0, ...extra});
  test('Missing battery stays unavailable', () {
    final s = parse({});
    expect(s.percentage, isNull);
    expect(s.charging, isNull);
    expect(s.batteryLabel, 'Unavailable');
  });
  test('Invalid battery and inconsistent storage are rejected', () {
    final s = parse({
      'battery': {'percentage': 101},
      'storage': {'totalBytes': 100, 'availableBytes': 101},
    });
    expect(s.percentage, isNull);
    expect(s.totalBytes, isNull);
  });
  test(
    'Zero battery is valid',
    () => expect(
      parse({
        'battery': {'percentage': 0},
      }).batteryLabel,
      '0.00%',
    ),
  );
  test('Storage uses GiB consistently', () {
    final s = parse({
      'storage': {'totalBytes': 2147483648, 'availableBytes': 1073741824},
    });
    expect(s.storageFraction, 0.5);
    expect(formatBytes(s.usedBytes), '1.0 GiB');
  });
  test('Five minute and future readings are stale', () {
    final s = parse({});
    expect(
      s.isStale(DateTime.fromMillisecondsSinceEpoch(299999, isUtc: true)),
      isFalse,
    );
    expect(
      s.isStale(DateTime.fromMillisecondsSinceEpoch(300000, isUtc: true)),
      isTrue,
    );
    expect(
      s.isStale(DateTime.fromMillisecondsSinceEpoch(-120000, isUtc: true)),
      isTrue,
    );
  });
}
