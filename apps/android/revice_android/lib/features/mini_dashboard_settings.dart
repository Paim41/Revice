import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/mini_dashboard.dart';

class MiniDashboardSettings extends StatelessWidget {
  const MiniDashboardSettings({super.key, required this.dashboard});
  final MiniDashboard dashboard;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([dashboard, dashboard.cloud]),
    builder: (context, _) {
      final options = dashboard.options;
      final user = dashboard.cloud.auth?.currentUser;
      final devices =
          user?.emailVerified == true &&
              dashboard.cloud.devicesOwnerUid == user?.uid
          ? dashboard.cloud.devices.entries
                .where(
                  (e) =>
                      e.key != dashboard.cloud.deviceId &&
                      e.value['revoked'] != true,
                )
                .toList()
          : <MapEntry<String, Map<String, dynamic>>>[];
      final favorites = List<String>.from(options['favorites'] as List? ?? []);
      Widget toggle(String key, String title, String subtitle) =>
          SwitchListTile(
            title: Text(title),
            subtitle: Text(subtitle),
            value: options[key] == true,
            onChanged: !dashboard.ready || dashboard.busy
                ? null
                : (value) => dashboard.save(key, value),
          );
      return Scaffold(
        appBar: AppBar(title: const Text('Mini Dashboard')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Your devices in the notification panel',
                style: TextStyle(
                  color: lime,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Uses existing readings, not an extra monitoring service. Remote observations are cached when Revice is not running. Their observation times show how old they are.',
                style: TextStyle(color: muted),
              ),
              const SizedBox(height: 16),
              Card(
                child: toggle(
                  'enabled',
                  'Enable Mini Dashboard',
                  'A silent notification showing up to four selected devices.',
                ),
              ),
              if (options['enabled'] == true && !dashboard.allowed) ...[
                const SizedBox(height: 12),
                const Text(
                  'Notifications are blocked. Allow Revice notifications in Android settings; monitoring still works without them.',
                ),
                OutlinedButton(
                  onPressed: dashboard.systemSettings,
                  child: const Text('Open notification settings'),
                ),
              ],
              if (dashboard.error != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(dashboard.error!),
                ),
              if (dashboard.dismissed && options['enabled'] == true)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Dashboard dismissed. It stays hidden until you choose Show again.',
                  ),
                ),
              if (options['enabled'] == true)
                OutlinedButton(
                  onPressed: dashboard.busy
                      ? null
                      : () => dashboard.save('enabled', true, showAgain: true),
                  child: const Text('Show again'),
                ),
              const SizedBox(height: 16),
              Card(
                child: Column(
                  children: [
                    toggle(
                      'local',
                      'Show local device',
                      'Include this phone’s actual readings.',
                    ),
                    toggle(
                      'remote',
                      'Show remote devices',
                      'Include authorized Android and Windows devices.',
                    ),
                    toggle(
                      'battery',
                      'Show battery',
                      'Unsupported battery readings appear as N/A.',
                    ),
                    toggle(
                      'storage',
                      'Show storage',
                      'Display used storage as a percentage.',
                    ),
                    toggle(
                      'updated',
                      'Show last updated',
                      'Show observation date and time, not a live indicator.',
                    ),
                    toggle(
                      'privacy',
                      'Hide details on lock screen',
                      'Hide device names and metrics on a secure lock screen; Android controls final visibility.',
                    ),
                    toggle(
                      'ongoing',
                      'Keep notification ongoing',
                      'Android may still allow dismissal. No foreground service is started.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Favorite devices',
                style: TextStyle(
                  color: cyan,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Select remote devices to include. With none selected, all authorized devices are eligible. Up to four appear; the rest are summarized.',
                style: TextStyle(color: muted),
              ),
              if (devices.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Sign in to a verified account and pair devices to select favorites.',
                  ),
                ),
              for (final entry in devices)
                CheckboxListTile(
                  title: Text(entry.value['name']?.toString() ?? 'Device'),
                  subtitle: Text(
                    entry.value['platform']?.toString() ?? 'Device',
                  ),
                  value: favorites.contains(entry.key),
                  onChanged: dashboard.busy
                      ? null
                      : (selected) {
                          final next = [...favorites];
                          if (selected == true) {
                            next.add(entry.key);
                          } else {
                            next.remove(entry.key);
                          }
                          dashboard.save('favorites', next);
                        },
                ),
              if (favorites.isNotEmpty)
                TextButton(
                  onPressed: dashboard.busy
                      ? null
                      : () => dashboard.save('favorites', <String>[]),
                  child: const Text('Clear favorites — include all devices'),
                ),
              const SizedBox(height: 16),
              const Text(
                'Tap the notification for Home, or View Devices for device details. Existing background monitoring can refresh this phone about every 15 minutes when paired and enabled; Android may delay it. No extra work is scheduled for this dashboard.',
                style: TextStyle(color: muted),
              ),
            ],
          ),
        ),
      );
    },
  );
}
