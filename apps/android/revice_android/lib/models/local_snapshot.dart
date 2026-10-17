import '../core/formatters.dart';

class LocalSnapshot {
  const LocalSnapshot({
    required this.observedAt,
    required this.model,
    required this.manufacturer,
    required this.androidVersion,
    this.percentage,
    this.charging,
    this.temperatureC,
    this.voltageMv,
    this.health,
    this.cycleCount,
    this.totalBytes,
    this.availableBytes,
  });

  final DateTime observedAt;
  final String model, manufacturer, androidVersion;
  final double? percentage, temperatureC;
  final bool? charging;
  final int? voltageMv, cycleCount, totalBytes, availableBytes;
  final String? health;

  factory LocalSnapshot.fromMap(Map<Object?, Object?> data) {
    final battery = Map<Object?, Object?>.from(data['battery'] as Map? ?? {});
    final storage = Map<Object?, Object?>.from(data['storage'] as Map? ?? {});
    final device = Map<Object?, Object?>.from(data['device'] as Map? ?? {});
    final percent = (battery['percentage'] as num?)?.toDouble();
    final total = (storage['totalBytes'] as num?)?.toInt();
    final available = (storage['availableBytes'] as num?)?.toInt();
    final validStorage =
        total != null &&
        total > 0 &&
        available != null &&
        available >= 0 &&
        available <= total;
    return LocalSnapshot(
      observedAt: DateTime.fromMillisecondsSinceEpoch(
        data['observedAt'] as int,
        isUtc: true,
      ),
      model: device['model'] as String? ?? 'Android device',
      manufacturer: device['manufacturer'] as String? ?? 'Unavailable',
      androidVersion: device['androidVersion'] as String? ?? 'Unavailable',
      percentage:
          percent != null && percent.isFinite && percent >= 0 && percent <= 100
          ? percent
          : null,
      charging: battery['charging'] as bool?,
      temperatureC: (battery['temperatureC'] as num?)?.toDouble(),
      voltageMv: (battery['voltageMv'] as num?)?.toInt(),
      health: battery['health'] as String?,
      cycleCount: (battery['cycleCount'] as num?)?.toInt(),
      totalBytes: validStorage ? total : null,
      availableBytes: validStorage ? available : null,
    );
  }

  int? get usedBytes =>
      totalBytes == null ? null : totalBytes! - availableBytes!;
  double? get storageFraction =>
      totalBytes == null ? null : usedBytes! / totalBytes!;
  String get batteryLabel => formatPercentage(percentage);
  String get chargingLabel => charging == null
      ? 'Charging state unavailable'
      : charging!
      ? 'Charging'
      : 'Not charging';
  bool isStale(DateTime now) =>
      now.toUtc().difference(observedAt).inMinutes >= 5 ||
      observedAt.isAfter(now.toUtc().add(const Duration(minutes: 1)));
}

String formatBytes(int? value) => value == null
    ? 'Unavailable'
    : '${(value / 1073741824).toStringAsFixed(1)} GiB';
