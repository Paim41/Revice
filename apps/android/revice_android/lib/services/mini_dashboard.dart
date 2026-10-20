import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/local_snapshot.dart';
import 'cloud_service.dart';
import 'monitoring_controller.dart';

const miniChannel = MethodChannel('app.revice/mini_dashboard');
const miniDefaults = <String, dynamic>{
  'enabled': false,
  'local': true,
  'remote': true,
  'battery': true,
  'storage': true,
  'updated': true,
  'privacy': true,
  'ongoing': false,
  'favorites': <String>[],
};

/// Only display-safe metrics cross the bridge. Never credentials or pairing codes.
Map<String, dynamic> miniLocalRow(LocalSnapshot value) => {
  'id': 'local',
  'local': true,
  'name': value.model,
  'platform': 'android',
  'battery': value.percentage,
  'charging': value.charging,
  'storage': value.storageFraction == null
      ? null
      : value.storageFraction! * 100,
  'observed': value.observedAt.millisecondsSinceEpoch,
};

Map<String, dynamic> miniPayload({
  required String? owner,
  required String? localId,
  required LocalSnapshot? local,
  required Map<String, Map<String, dynamic>> devices,
}) {
  final rows = <Map<String, dynamic>>[
    if (local != null)
      {
        ...miniLocalRow(local),
        if (owner != null && devices[localId]?['name'] != null)
          'name': devices[localId]!['name'],
      },
  ];
  if (owner != null) {
    for (final entry in devices.entries) {
      final device = entry.value;
      if (device['revoked'] == true || entry.key == localId) continue;
      final latest = device['latest'] is Map
          ? device['latest'] as Map
          : const {};
      final battery = latest['battery'] is Map
          ? latest['battery'] as Map
          : const {};
      final storage = latest['storage'] is Map
          ? latest['storage'] as Map
          : const {};
      final total = storage['totalBytes'],
          available = storage['availableBytes'];
      final valid =
          total is num &&
          total.isFinite &&
          total > 0 &&
          available is num &&
          available.isFinite &&
          available >= 0 &&
          available <= total;
      final percent = battery['percentage'];
      rows.add({
        'id': entry.key,
        'local': false,
        'name': device['name']?.toString() ?? 'Device',
        'platform': ['windows', 'ios'].contains(device['platform'])
            ? device['platform']
            : 'android',
        'battery':
            percent is num && percent.isFinite && percent >= 0 && percent <= 100
            ? percent
            : null,
        'charging': battery['charging'] == true,
        'storage': device['platform'] == 'ios'
            ? null
            : valid
            ? 100 * (total - available) / total
            : null,
        'observed': DateTime.tryParse(latest['observedAt']?.toString() ?? '')
            ?.millisecondsSinceEpoch,
      });
    }
  }
  return {'owner': owner ?? '', 'rows': rows};
}

class MiniDashboard extends ChangeNotifier {
  MiniDashboard(
    this.monitor,
    this.cloud, {
    this.channel = miniChannel,
    required this.onNavigate,
  });
  final MonitoringController monitor;
  final CloudService cloud;
  final MethodChannel channel;
  final void Function(String) onNavigate;
  Map<String, dynamic> options = Map.of(miniDefaults);
  bool ready = false,
      allowed = false,
      dismissed = false,
      busy = false,
      _disposed = false;
  String? error;
  bool _pending = false, _sending = false;
  String? _sent;

  Future<void> initialize() async {
    monitor.addListener(update);
    cloud.addListener(update);
    channel.setMethodCallHandler((call) async {
      if (call.method == 'navigationAvailable') await navigation();
    });
    await resume();
  }

  Future<void> navigation() async {
    try {
      final target = await channel.invokeMethod<String>('takeNavigation');
      if (!_disposed && (target == 'home' || target == 'devices')) {
        onNavigate(target!);
      }
    } on MissingPluginException {
      /* Native Android only. */
    } on PlatformException {
      /* A missing intent does not affect monitoring. */
    }
  }

  Future<void> resume() async {
    try {
      final result = await channel.invokeMapMethod<String, dynamic>('load');
      if (_disposed) return;
      final saved = jsonDecode(result?['options'] as String? ?? '{}') as Map;
      options = {...miniDefaults, ...Map<String, dynamic>.from(saved)};
      allowed = result?['allowed'] == true;
      dismissed = result?['dismissed'] == true;
      error = null;
    } on MissingPluginException {
      error = 'Mini Dashboard is available in the Android app.';
    } on PlatformException {
      error = 'Could not read notification settings.';
    } on FormatException {
      error = 'Saved notification settings could not be read.';
    }
    if (_disposed) return;
    ready = true;
    notifyListeners();
    _sent = null;
    update();
    await navigation();
  }

  Future<void> save(String key, dynamic value, {bool showAgain = false}) async {
    if (busy || _disposed) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      if (key == 'enabled' && value == true) {
        allowed = await channel.invokeMethod<bool>('permission') ?? false;
      }
      final next = {...options, key: value};
      await channel.invokeMethod<void>('save', {
        'options': jsonEncode(next),
        'showAgain': showAgain || (key == 'enabled' && value == true),
      });
      if (_disposed) return;
      options = next;
      if (showAgain || (key == 'enabled' && value == true)) dismissed = false;
      _sent = null;
      update();
    } on PlatformException {
      error = 'Could not change notification settings. Please try again.';
    } on MissingPluginException {
      error = 'Open the Android app to configure notifications.';
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> systemSettings() async {
    try {
      await channel.invokeMethod<void>('systemSettings');
    } on PlatformException {
      error = 'Android notification settings could not be opened.';
      if (!_disposed) notifyListeners();
    } on MissingPluginException {
      /* Native Android only. */
    }
  }

  void update() {
    if (!ready || _disposed) return;
    _pending = true;
    if (!_sending) unawaited(_flush());
  }

  Future<void> _flush() async {
    _sending = true;
    try {
      while (_pending && !_disposed) {
        _pending = false;
        if (options['enabled'] != true) continue;
        final user = cloud.auth?.currentUser;
        final payload = jsonEncode(
          miniPayload(
            owner: user?.emailVerified == true ? user!.uid : null,
            localId: cloud.deviceId,
            local: monitor.snapshot,
            devices: cloud.devicesOwnerUid == user?.uid
                ? cloud.devices
                : const {},
          ),
        );
        if (payload == _sent) continue;
        await channel.invokeMethod<void>('update', {'data': payload});
        _sent = payload;
      }
    } on PlatformException {
      error = 'Mini Dashboard could not be updated.';
      if (!_disposed) notifyListeners();
    } on MissingPluginException {
      /* Not available on desktop widget tests. */
    } finally {
      _sending = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    monitor.removeListener(update);
    cloud.removeListener(update);
    channel.setMethodCallHandler(null);
    super.dispose();
  }
}

/// Runs only as part of an existing Workmanager observation; no extra job/read.
Future<void> updateBackgroundDashboard(
  CloudService cloud,
  LocalSnapshot snapshot,
) async {
  try {
    final user = cloud.auth?.currentUser;
    await miniChannel.invokeMethod<void>('update', {
      'background': true,
      'data': jsonEncode(
        miniPayload(
          owner: user?.emailVerified == true ? user!.uid : null,
          localId: cloud.deviceId,
          local: snapshot,
          devices: const {},
        ),
      ),
    });
  } on PlatformException {
    /* Notifications never fail monitoring. */
  } on MissingPluginException {
    /* Optional native capability. */
  }
}
