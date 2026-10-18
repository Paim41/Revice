import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/local_snapshot.dart';
import '../services/monitoring_controller.dart';
import '../services/cloud_service.dart';
import 'cloud_screen.dart';
import 'history_screen.dart';
import 'device_overview.dart';
import 'developer_credits.dart';
import 'floating_navigation_bar.dart';
import '../services/mini_dashboard.dart';
import 'mini_dashboard_settings.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.controller, required this.cloud});
  final MonitoringController controller;
  final CloudService cloud;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int page = 0;
  Timer? timer;
  late final MiniDashboard mini;
  MonitoringController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    mini = MiniDashboard(
      controller,
      widget.cloud,
      onNavigate: (target) {
        if (!mounted) return;
        Navigator.of(context).popUntil((route) => route.isFirst);
        setState(() => page = target == 'devices' ? 1 : 0);
      },
    );
    mini.initialize();
    timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (controller.onboarded) controller.refresh();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    timer?.cancel();
    if (state == AppLifecycleState.resumed) {
      mini.resume();
      if (controller.onboarded) controller.refresh();
      timer = Timer.periodic(const Duration(minutes: 1), (_) {
        if (controller.onboarded) controller.refresh();
      });
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    mini.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      if (!controller.ready) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (!controller.onboarded) return _onboarding();
      final titles = [
        'Overview',
        'Devices',
        'Insights',
        'Activity',
        'Settings',
      ];
      return Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              Image.asset(
                'assets/revice-header-logo.png',
                width: 112,
                height: 38,
                fit: BoxFit.contain,
                semanticLabel: 'Revice',
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(titles[page], overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Refresh local readings',
              onPressed: controller.busy ? null : controller.refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: controller.refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              if (controller.error != null) ...[
                Panel(
                  child: Text(
                    controller.error!,
                    style: const TextStyle(color: Color(0xFFF59E0B)),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (controller.busy) const LinearProgressIndicator(minHeight: 2),
              ...switch (page) {
                0 => _overview(),
                1 => _devices(),
                2 => _insights(),
                3 => _activity(),
                _ => _settings(),
              },
            ],
          ),
        ),
        bottomNavigationBar: ReviceFloatingNavigationBar(
          selectedIndex: page,
          reduceMotion: controller.reduceMotion,
          onDestinationSelected: (value) => setState(() => page = value),
        ),
      );
    },
  );

  Widget _onboarding() => Scaffold(
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(28),
        children: [
          const SizedBox(height: 32),
          const Text(
            'Your device at a glance',
            style: TextStyle(fontSize: 34, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          const Text(
            'A clearer view of the devices you depend on.',
            style: TextStyle(fontSize: 18, color: muted),
          ),
          const SizedBox(height: 32),
          const Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.monitor_heart_outlined, color: lime, size: 36),
                SizedBox(height: 20),
                Text(
                  'Start with this phone',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 12),
                Text(
                  'Read battery and storage directly from Android. No account or sensitive permissions are needed for local monitoring.',
                ),
                SizedBox(height: 16),
                Text(
                  'Monitor locally or connect devices through a configured cloud account. Optional background monitoring and Mini Dashboard notifications are available in Settings.',
                  style: TextStyle(color: muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: () => controller.setPreferences(onboarding: true),
            child: const Text('Monitor this device'),
          ),
          TextButton(
            onPressed: _cloudInfo,
            child: const Text('About connecting other devices'),
          ),
          if (controller.error != null) Text(controller.error!),
        ],
      ),
    ),
  );

  List<Widget> _overview() => [
    const Text(
      'YOUR DEVICES, AT A GLANCE',
      style: TextStyle(color: muted, letterSpacing: 1.8, fontSize: 11),
    ),
    const SizedBox(height: 18),
    const Text(
      'Stay in the know.',
      style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
    ),
    const SizedBox(height: 8),
    const Text(
      'This device • Live local readings',
      style: TextStyle(color: muted),
    ),
    const SizedBox(height: 24),
    if (controller.snapshot case final snapshot?) ...[
      _deviceCard(snapshot),
      const SizedBox(height: 16),
      _storageCard(snapshot),
    ] else
      const Panel(
        child: Text('No device reading yet. Use refresh to read this phone.'),
      ),
    const SizedBox(height: 24),
    RegisteredOverview(cloud: widget.cloud),
    const SizedBox(height: 16),
    OutlinedButton.icon(
      onPressed: _cloudInfo,
      icon: const Icon(Icons.add_rounded),
      label: const Text('Connect another device'),
    ),
  ];

  Widget _deviceCard(LocalSnapshot snapshot) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.phone_android_rounded, color: cyan),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                snapshot.model,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Text(
              'THIS DEVICE',
              style: TextStyle(fontSize: 10, color: muted),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Center(
          child: SizedBox(
            width: 176,
            height: 176,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: snapshot.percentage == null
                        ? 0
                        : snapshot.percentage! / 100,
                    strokeWidth: 10,
                    backgroundColor: const Color(0xFF29372D),
                    color: lime,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      snapshot.batteryLabel,
                      style: TextStyle(
                        fontSize: snapshot.percentage == null ? 20 : 34,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Text(
                      'BATTERY',
                      style: TextStyle(
                        color: muted,
                        fontSize: 11,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Center(
          child: Text(
            snapshot.chargingLabel,
            style: const TextStyle(color: cyan),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '${snapshot.isStale(DateTime.now()) ? 'Stale reading' : 'Local observation'} • ${_time(snapshot.observedAt)}',
          style: const TextStyle(color: muted, fontSize: 12),
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => DeviceDetails(controller: controller),
            ),
          ),
          child: const Text('View device details →'),
        ),
      ],
    ),
  );

  Widget _storageCard(LocalSnapshot snapshot) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.storage_rounded, color: cyan),
            SizedBox(width: 12),
            Text('Storage', style: TextStyle(fontSize: 18)),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          '${formatBytes(snapshot.usedBytes)} used',
          style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        LinearProgressIndicator(
          value: snapshot.storageFraction ?? 0,
          color: cyan,
          backgroundColor: const Color(0xFF29372D),
          minHeight: 8,
          borderRadius: BorderRadius.circular(8),
        ),
        const SizedBox(height: 12),
        Text(
          '${formatBytes(snapshot.availableBytes)} available / ${formatBytes(snapshot.totalBytes)} total',
          style: const TextStyle(color: muted),
        ),
        const SizedBox(height: 8),
        const Text(
          'Android data filesystem; may differ from advertised capacity.',
          style: TextStyle(color: muted, fontSize: 11),
        ),
      ],
    ),
  );

  List<Widget> _devices() => [
    CloudDevices(cloud: widget.cloud),
    const SizedBox(height: 20),
    const Text(
      'Your devices',
      style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
    ),
    const SizedBox(height: 12),
    const Text(
      'Local monitoring is always available. Registered devices appear below when signed in to a verified account.',
      style: TextStyle(color: muted),
    ),
    const SizedBox(height: 24),
    if (controller.snapshot case final snapshot?) _deviceCard(snapshot),
    const SizedBox(height: 16),
    OutlinedButton.icon(
      onPressed: _cloudInfo,
      icon: const Icon(Icons.add),
      label: const Text('Pair a device'),
    ),
  ];

  List<Widget> _insights() => [
    const Text(
      'History starts with observations',
      style: TextStyle(fontSize: 24),
    ),
    const SizedBox(height: 20),
    DeviceHistory(cloud: widget.cloud),
  ];

  List<Widget> _activity() => [
    const Text('Alerts & activity', style: TextStyle(fontSize: 24)),
    const SizedBox(height: 20),
    DeviceHistory(cloud: widget.cloud, alerts: true),
  ];
  List<Widget> _settings() => [
    const Text(
      'Make it yours',
      style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
    ),
    const SizedBox(height: 20),
    Panel(
      child: ListTile(
        leading: const Icon(Icons.notifications_outlined, color: cyan),
        title: const Text('Notifications'),
        subtitle: const Text('Mini Dashboard'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => MiniDashboardSettings(dashboard: mini),
          ),
        ),
      ),
    ),
    const SizedBox(height: 16),
    Panel(
      child: Column(
        children: [
          const ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Volt AMOLED'),
            subtitle: Text('Dark appearance • System font fallback'),
            leading: Icon(Icons.dark_mode_outlined, color: lime),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Reduce motion'),
            subtitle: const Text(
              'Also respects your device accessibility setting',
            ),
            value: controller.reduceMotion,
            onChanged: (value) => controller.setPreferences(motion: value),
          ),
        ],
      ),
    ),
    const SizedBox(height: 16),
    const Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Local monitoring',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 12),
          Text(
            'Refreshes once per minute while open and on resume. Paired phones sync while the app is open; failed uploads retain the latest reading locally. Optional background monitoring is available after pairing; Android may delay periodic work.',
          ),
          SizedBox(height: 12),
          Text(
            'No contacts, messages, photos, location or hardware identifiers are collected.',
            style: TextStyle(color: muted),
          ),
        ],
      ),
    ),
    const SizedBox(height: 16),
    Panel(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Account & pairing'),
        subtitle: const Text('Cloud setup required'),
        trailing: const Icon(Icons.chevron_right),
        onTap: _cloudInfo,
      ),
    ),
    const SizedBox(height: 16),
    Panel(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.code_rounded, color: cyan),
        title: const Text('Developer Credits'),
        subtitle: const Text('Revice • Developed by Paim41'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const DeveloperCredits()),
        ),
      ),
    ),
  ];

  void _cloudInfo() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => CloudScreen(cloud: widget.cloud, monitor: controller),
    ),
  );
}

String _time(DateTime time) => time.toLocal().toString().split('.').first;

class Panel extends StatelessWidget {
  const Panel({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: const EdgeInsets.all(22), child: child),
  );
}

class DeviceDetails extends StatelessWidget {
  const DeviceDetails({super.key, required this.controller});
  final MonitoringController controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final s = controller.snapshot;
      return Scaffold(
        appBar: AppBar(
          title: const Text('Device details'),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: controller.busy ? null : controller.refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (controller.error != null) Text(controller.error!),
            if (s != null)
              Panel(
                child: Column(
                  children: [
                    for (final row in <(String, String)>[
                      ('Model', s.model),
                      ('Manufacturer', s.manufacturer),
                      ('Android', s.androidVersion),
                      ('Battery', s.batteryLabel),
                      ('Power', s.chargingLabel),
                      (
                        'Temperature',
                        s.temperatureC == null
                            ? 'Unavailable'
                            : '${s.temperatureC!.toStringAsFixed(1)} °C',
                      ),
                      (
                        'Voltage',
                        s.voltageMv == null
                            ? 'Unavailable'
                            : '${s.voltageMv} mV',
                      ),
                      ('Health status', s.health ?? 'Unavailable'),
                      (
                        'Cycle count',
                        s.cycleCount?.toString() ?? 'Unsupported / unavailable',
                      ),
                      ('Storage total', formatBytes(s.totalBytes)),
                      ('Storage available', formatBytes(s.availableBytes)),
                      ('Observed', _time(s.observedAt)),
                      ('Cloud sync', 'Not configured'),
                    ])
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                row.$1,
                                style: const TextStyle(color: muted),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(row.$2, textAlign: TextAlign.right),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            const Text(
              'Health is the status reported by Android, not an estimated battery capacity percentage.',
              style: TextStyle(color: muted),
            ),
          ],
        ),
      );
    },
  );
}
