import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'features/app_shell.dart';
import 'services/monitoring_controller.dart';
import 'services/cloud_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ReviceApp());
}

class ReviceApp extends StatefulWidget {
  const ReviceApp({super.key});
  @override
  State<ReviceApp> createState() => _ReviceAppState();
}

class _ReviceAppState extends State<ReviceApp> {
  final controller = MonitoringController();
  final cloud = CloudService();
  @override
  void initState() {
    super.initState();
    controller.initialize();
    cloud.initialize();
    controller.addListener(_syncObservation);
  }

  DateTime? _lastObserved;
  void _syncObservation() {
    final snapshot = controller.snapshot;
    if (snapshot != null && snapshot.observedAt != _lastObserved) {
      _lastObserved = snapshot.observedAt;
      cloud.enqueueAndSync(snapshot);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    cloud.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (_, _) => MaterialApp(
      title: 'Revice',
      debugShowCheckedModeBanner: false,
      theme: reviceTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations:
              controller.reduceMotion ||
              MediaQuery.of(context).disableAnimations,
        ),
        child: child!,
      ),
      home: AppShell(controller: controller, cloud: cloud),
    ),
  );
}
