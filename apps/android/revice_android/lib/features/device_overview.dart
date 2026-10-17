import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/formatters.dart';
import '../models/local_snapshot.dart';
import '../services/cloud_service.dart';

const deviceCardMargin = EdgeInsets.only(bottom: 12);

String deviceSummary(Map<String, dynamic> device, {DateTime? now}) {
  final latest = device['latest'] as Map?;
  final platform = device['platform']?.toString() ?? 'Device';
  if (device['revoked'] == true) return '$platform • Revoked';
  if (latest == null) return '$platform • Awaiting first report';
  final battery = latest['battery'] as Map?;
  final storage = latest['storage'] as Map?;
  final total = (storage?['totalBytes'] as num?)?.toInt();
  final available = (storage?['availableBytes'] as num?)?.toInt();
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
  final charging = battery?['charging'] as bool?;
  final batteryText = battery?['percentage'] == null
      ? 'Battery unavailable'
      : 'Battery ${formatPercentage(battery!['percentage'] as num)}';
  final storageText = validStorage
      ? 'Storage ${formatPercentage(100 * (total - available) / total)} used\n${formatBytes(total - available)} / ${formatBytes(total)}'
      : 'Storage unavailable';
  return '$platform • ${stale ? 'Stale' : 'Recent'}\n$batteryText${charging == null
      ? ''
      : charging
      ? ' • Charging'
      : ' • Not charging'}\n$storageText\nObserved ${observed?.toLocal().toString().split('.').first ?? 'Unknown time'}';
}

void showDeviceDetails(BuildContext context, Map<String, dynamic> device) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              device['name']?.toString() ?? 'Device',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            Text(deviceSummary(device), style: const TextStyle(height: 1.7)),
          ],
        ),
      ),
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
            'Other devices',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            '${devices.length} registered • Android & Windows',
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
                onTap: () => showDeviceDetails(context, entry.value),
              ),
            ),
        ],
      );
    },
  );
}
