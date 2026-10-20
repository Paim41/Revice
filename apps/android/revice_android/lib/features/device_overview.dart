import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/formatters.dart';
import '../models/local_snapshot.dart';
import '../services/cloud_service.dart';

int? safeBytes(Object? value) =>
    value is num && value.isFinite ? value.toInt() : null;

const deviceCardMargin = EdgeInsets.only(bottom: 12);

String deviceSummary(Map<String, dynamic> device, {DateTime? now}) {
  final latest = device['latest'] is Map ? device['latest'] as Map : null;
  final platform = platformLabel(device['platform']);
  if (device['revoked'] == true) return '$platform | Revoked';
  if (latest == null) return '$platform | Awaiting First Report';
  final battery = latest['battery'] is Map ? latest['battery'] as Map : null;
  final storage = latest['storage'] is Map ? latest['storage'] as Map : null;
  final total = safeBytes(storage?['totalBytes']);
  final available = safeBytes(storage?['availableBytes']);
  final validStorage =
      total != null &&
      total > 0 &&
      available != null &&
      available >= 0 &&
      available <= total;
  final observed = DateTime.tryParse(latest['observedAt']?.toString() ?? '');
  final clock = now ?? DateTime.now();
  final stale =
      observed == null ||
      clock.difference(observed).inMinutes >= 5 ||
      observed.isAfter(clock.add(const Duration(minutes: 2)));
  final charging = battery?['charging'] is bool
      ? battery!['charging'] as bool
      : null;
  final batteryText = battery?['percentage'] is! num
      ? 'Battery N/A'
      : 'Battery ${compactPercentage(battery!['percentage'] as num, battery: true)}';
  final storageText = device['platform'] == 'ios'
      ? 'Storage: Available on iPhone Only'
      : validStorage
      ? 'Storage Used: ${compactPercentage(100 * (total - available) / total)}\n${formatBytes(total - available)} / ${formatBytes(total)}'
      : 'Storage N/A';
  return '$platform | ${stale ? 'Stale' : 'Recent'}\n$batteryText${charging == null
      ? ''
      : charging
      ? ' | Charging'
      : ' | Not Charging'}\n$storageText\nLast Updated: ${friendlyTime(observed)}';
}

void showDeviceDetails(
  BuildContext context,
  Map<String, dynamic> device, {
  CloudService? cloud,
  String? deviceId,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => ListenableBuilder(
      listenable: Listenable.merge([?cloud]),
      builder: (context, _) {
        final current = cloud == null ? device : cloud.devices[deviceId];
        if (current == null) {
          return const SafeArea(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Device unavailable.'),
            ),
          );
        }
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  current['name']?.toString() ?? 'Device',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                Text(
                  deviceSummary(current),
                  style: const TextStyle(height: 1.7),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class RegisteredOverview extends StatelessWidget {
  const RegisteredOverview({super.key, required this.cloud});
  final CloudService cloud;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: cloud,
    builder: (context, _) {
      final devices = cloud.devices.entries
          .where((e) => e.key != cloud.deviceId)
          .toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Other Devices',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            '${devices.length} registered | Android, Windows & iOS',
            style: const TextStyle(color: muted),
          ),
          const SizedBox(height: 16),
          if (devices.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'Other registered devices appear here when you sign in to a verified account. Connect a device in Account & pairing.',
                ),
              ),
            ),
          for (final entry in devices)
            Card(
              margin: deviceCardMargin,
              child: ListTile(
                contentPadding: const EdgeInsets.all(20),
                leading: Icon(
                  entry.value['platform'] == 'windows'
                      ? Icons.desktop_windows_rounded
                      : entry.value['platform'] == 'ios'
                      ? Icons.phone_iphone_rounded
                      : Icons.phone_android_rounded,
                  color: cyan,
                ),
                title: Text(
                  entry.value['name']?.toString() ?? 'Device',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    deviceSummary(entry.value),
                    style: const TextStyle(height: 1.5),
                  ),
                ),
                onTap: () => showDeviceDetails(
                  context,
                  entry.value,
                  cloud: cloud,
                  deviceId: entry.key,
                ),
              ),
            ),
        ],
      );
    },
  );
}
