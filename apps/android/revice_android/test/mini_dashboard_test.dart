import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revice_android/core/theme.dart';
import 'package:revice_android/features/mini_dashboard_settings.dart';
import 'package:revice_android/models/local_snapshot.dart';
import 'package:revice_android/services/cloud_service.dart';
import 'package:revice_android/services/mini_dashboard.dart';
import 'package:revice_android/services/monitoring_controller.dart';

class Owner extends Fake implements User {
  Owner(this.uid, {this.emailVerified = true});
  @override
  final String uid;
  @override
  final bool emailVerified;
}

class Auth extends Fake implements FirebaseAuth {
  @override
  User? currentUser = Owner('owner');
}

void main() {
  test('iOS notification payload never carries storage values', () {
    final payload = miniPayload(
      owner: 'owner',
      localId: null,
      local: null,
      devices: {
        'iphone': {
          'platform': 'ios',
          'name': 'My iPhone',
          'latest': {
            'battery': {'percentage': 76, 'charging': true},
            'storage': {'totalBytes': 100, 'availableBytes': 20},
          },
        },
      },
    );
    final row = (payload['rows'] as List).single as Map;
    expect(row['platform'], 'ios');
    expect(row['storage'], isNull);
    expect(row['battery'], 76);
  });
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.revice/mini_dashboard');
  final sample = LocalSnapshot(
    observedAt: DateTime.utc(2026, 10, 18),
    model: 'POCO F7',
    manufacturer: 'POCO',
    androidVersion: '16',
    percentage: 78,
    charging: true,
    totalBytes: 1000,
    availableBytes: 360,
  );
  Map<String, dynamic> remote(String name, {bool revoked = false}) => {
    'name': name,
    'platform': 'windows',
    'revoked': revoked,
    'credential': 'must-not-cross-bridge',
    'latest': {
      'observedAt': '2020-01-01T00:00:00Z',
      'battery': null,
      'storage': {'totalBytes': 100, 'availableBytes': 33},
    },
  };
  late MonitoringController monitor;
  test(
    'Registered local alias is used without modifying hardware metadata',
    () {
      final payload = miniPayload(
        owner: 'owner',
        localId: 'self',
        local: sample,
        devices: {'self': remote('paIM Phone')},
      );
      expect((payload['rows'] as List).single['name'], 'paIM Phone');
      expect(sample.model, 'POCO F7');
      final signedOut = miniPayload(
        owner: null,
        localId: 'self',
        local: sample,
        devices: {'self': remote('paIM Phone')},
      );
      expect((signedOut['rows'] as List).single['name'], 'POCO F7');
    },
  );
  late CloudService cloud;
  late MiniDashboard dashboard;
  late List<MethodCall> calls;
  late Map<String, dynamic> saved;
  bool permission = false;
  String? target;
  String? routed;
  setUp(() {
    calls = [];
    saved = {};
    permission = false;
    target = null;
    routed = null;
    monitor = MonitoringController()..snapshot = sample;
    cloud = CloudService()
      ..auth = Auth()
      ..devicesOwnerUid = 'owner'
      ..deviceId = 'self';
    cloud.devices.addAll({
      'self': remote('Duplicate local'),
      'pc': remote('Windows PC'),
      'gone': remote('Revoked', revoked: true),
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'load':
              return {
                'options': jsonEncode(saved),
                'allowed': permission,
                'dismissed': false,
              };
            case 'permission':
              return permission;
            case 'save':
              saved = Map<String, dynamic>.from(
                jsonDecode(call.arguments['options']),
              );
              return null;
            case 'takeNavigation':
              final next = target;
              target = null;
              return next;
            default:
              return null;
          }
        });
    dashboard = MiniDashboard(
      monitor,
      cloud,
      onNavigate: (value) => routed = value,
    );
  });
  tearDown(() {
    dashboard.dispose();
    monitor.dispose();
    cloud.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('Payload uses real metrics, excludes revoked/duplicate devices and secrets, preserves old times', () {
    final payload = miniPayload(
      owner: 'owner',
      localId: 'self',
      local: sample,
      devices: cloud.devices,
    );
    final rows = payload['rows'] as List;
    expect(rows.length, 2);
    expect(rows[0]['storage'], 64);
    expect(rows[0]['battery'], 78);
    expect(rows[1]['battery'], isNull);
    expect(rows[1]['storage'], 67);
    expect(rows[1]['observed'], DateTime.utc(2020).millisecondsSinceEpoch);
    expect(jsonEncode(payload), isNot(contains('must-not-cross-bridge')));
    expect(
      (miniPayload(
                owner: null,
                localId: null,
                local: sample,
                devices: cloud.devices,
              )['rows']
              as List)
          .length,
      1,
    );
  });

  testWidgets(
    'Default opt-out, denied permission explanation, settings persist and disable',
    (tester) async {
      await dashboard.initialize();
      await tester.pump();
      expect(dashboard.options['enabled'], false);
      expect(
        calls.where((c) => c.method == 'permission' || c.method == 'update'),
        isEmpty,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: reviceTheme(),
          home: MiniDashboardSettings(dashboard: dashboard),
        ),
      );
      await tester.tap(find.text('Enable Mini Dashboard'));
      await tester.pumpAndSettle();
      expect(calls.where((c) => c.method == 'permission').length, 1);
      expect(find.textContaining('Notifications are blocked'), findsOneWidget);
      expect(saved['enabled'], true);
      expect(saved['privacy'], true);
      await tester.tap(find.text('Open notification settings'));
      await tester.pump();
      expect(calls.last.method, 'systemSettings');
      await dashboard.save('favorites', ['pc']);
      await tester.pump();
      await dashboard.resume();
      expect(dashboard.options['favorites'], ['pc']);
      await dashboard.save('enabled', false);
      await tester.pump();
      expect(saved['enabled'], false);
      final updates = calls.where((c) => c.method == 'update').length;
      dashboard.update();
      await tester.pump();
      expect(calls.where((c) => c.method == 'update').length, updates);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Existing changes update once and sign-out clears remote data; only safe destinations',
    (tester) async {
      saved = {'enabled': true};
      permission = true;
      await dashboard.initialize();
      await tester.pump();
      Map data() => jsonDecode(
        calls.lastWhere((c) => c.method == 'update').arguments['data'],
      ) as Map;
      expect((data()['rows'] as List).length, 2);
      final before = calls.where((c) => c.method == 'update').length;
      dashboard.update();
      dashboard.update();
      await tester.pump();
      expect(calls.where((c) => c.method == 'update').length, before);
      cloud.devices['pc']!['revoked'] = true;
      dashboard.update();
      await tester.pump();
      expect((data()['rows'] as List).length, 1);
      cloud.devices['pc']!['revoked'] = false;
      (cloud.auth as Auth).currentUser = Owner('other');
      dashboard.update();
      await tester.pump();
      expect(
        (data()['rows'] as List).length,
        1,
        reason: 'Old account cache must not transfer to new owner',
      );
      (cloud.auth as Auth).currentUser = null;
      dashboard.update();
      await tester.pump();
      expect(data()['owner'], '');
      target = 'devices';
      await dashboard.navigation();
      expect(routed, 'devices');
      target = 'private/device/token';
      await dashboard.navigation();
      expect(routed, 'devices');
      target = 'home';
      await dashboard.navigation();
      expect(routed, 'home');
    },
  );

  testWidgets(
    'Background bridge uses only supplied observation and authenticated owner, no network',
    (tester) async {
      await updateBackgroundDashboard(cloud, sample);
      final call = calls.single;
      expect(call.method, 'update');
      expect(call.arguments['background'], true);
      final payload = jsonDecode(call.arguments['data']);
      expect(payload['owner'], 'owner');
      expect((payload['rows'] as List).length, 1);
      expect(payload['rows'][0]['name'], 'POCO F7');
    },
  );
}
