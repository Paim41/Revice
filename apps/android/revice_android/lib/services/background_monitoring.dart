import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:workmanager/workmanager.dart';

import '../models/local_snapshot.dart';
import 'cloud_service.dart';
import 'mini_dashboard.dart';

@pragma('vm:entry-point')
void monitoringDispatcher() {
  Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    final cloud = CloudService();
    try {
      await cloud.initialize(background: true);
      if (cloud.ownerUid == null || !cloud.backgroundEnabled) return true;
      final raw = await const MethodChannel('app.revice/monitoring')
          .invokeMapMethod<Object?, Object?>('readSnapshot');
      if (raw == null) return false;
      final snapshot = LocalSnapshot.fromMap(raw);
      await cloud.enqueueAndSync(snapshot);
      await updateBackgroundDashboard(cloud, snapshot);
      return cloud.error == null;
    } catch (_) {
      return false;
    } finally {
      cloud.dispose();
    }
  });
}

Future<void> enableBackgroundMonitoring() async {
  await Workmanager().initialize(monitoringDispatcher);
  await Workmanager().registerPeriodicTask(
    'revice-monitoring',
    'revice-monitoring',
    frequency: const Duration(minutes: 15),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    backoffPolicy: BackoffPolicy.exponential,
    backoffPolicyDelay: const Duration(minutes: 1),
  );
}

Future<void> disableBackgroundMonitoring() =>
    Workmanager().cancelByUniqueName('revice-monitoring');
