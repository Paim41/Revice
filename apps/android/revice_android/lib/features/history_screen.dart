import 'device_history_card.dart';

import 'package:flutter/material.dart';

import '../services/cloud_service.dart';

class DeviceHistory extends StatelessWidget {
  const DeviceHistory({super.key, required this.cloud, this.alerts = false});
  final CloudService cloud;
  final bool alerts;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: cloud,
    builder: (context, _) {
      final user = cloud.auth?.currentUser;
      if (user == null || !user.emailVerified) {
        return const Text(
          'Sign in to a verified account to view cloud history and activity. Local readings are available on Home.',
        );
      }
      if (cloud.devices.isEmpty) {
        return const Text(
          'Register or pair a device to start collecting history.',
        );
      }
      return Column(
        children: [
          for (final entry in cloud.devices.entries)
            DeviceHistoryCard(
              key: ValueKey('${user.uid}/${entry.key}/$alerts'),
              owner: user.uid,
              device: entry.key,
              name: entry.value['name']?.toString() ?? 'Device',
              alerts: alerts,
            ),
        ],
      );
    },
  );
}
