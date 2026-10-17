import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../services/cloud_service.dart';
import '../core/theme.dart';
import 'device_overview.dart';
import '../core/formatters.dart';

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
            Card(
              margin: deviceCardMargin,
              child: ExpansionTile(
                shape: const Border(),
                collapsedShape: const Border(),
                title: Text(entry.value['name']?.toString() ?? 'Device'),
                subtitle: Text(
                  alerts
                      ? 'Alert activity'
                      : 'Recent observations • up to 256 readings',
                ),
                children: [
                  StreamBuilder<DatabaseEvent>(
                    stream: FirebaseDatabase.instance
                        .ref(
                          'devices/${user.uid}/${entry.key}/${alerts ? 'alerts' : 'history'}',
                        )
                        .onValue,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return const Padding(
                          padding: EdgeInsets.all(20),
                          child: Text(
                            'History could not be loaded. Check your connection.',
                          ),
                        );
                      }
                      if (!snapshot.hasData) {
                        return const LinearProgressIndicator();
                      }
                      final data = snapshot.data!.snapshot.value as Map? ?? {};
                      final rows = data.values
                          .whereType<Map>()
                          .map((v) => Map<String, dynamic>.from(v))
                          .toList();
                      rows.sort(
                        (a, b) => alerts
                            ? (b['at'] as num).compareTo(a['at'] as num)
                            : (a['observedAt'] as String).compareTo(
                                b['observedAt'] as String,
                              ),
                      );
                      if (rows.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            alerts
                                ? 'No alerts recorded.'
                                : 'No history yet. Sync this device to begin.',
                          ),
                        );
                      }
                      if (alerts) {
                        return Column(
                          children: rows
                              .take(30)
                              .map(
                                (r) => ListTile(
                                  title: Text(
                                    r['message']?.toString() ?? 'Alert',
                                  ),
                                  subtitle: Text(
                                    '${r['active'] == true ? 'Active' : 'Recovered'} • ${DateTime.fromMillisecondsSinceEpoch((r['at'] as num).toInt()).toLocal().toString().split('.').first}',
                                  ),
                                ),
                              )
                              .toList(),
                        );
                      }
                      final points = rows
                          .where(
                            (r) =>
                                (r['battery'] as Map?)?['percentage'] != null,
                          )
                          .toList();
                      return Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (points.length >= 2) ...[
                              const Text(
                                'Battery history',
                                style: TextStyle(fontSize: 18),
                              ),
                              const SizedBox(height: 12),
                              Semantics(
                                label:
                                    'Battery readings from ${points.first['observedAt']} to ${points.last['observedAt']}',
                                child: SizedBox(
                                  height: 130,
                                  width: double.infinity,
                                  child: CustomPaint(
                                    painter: BatteryChart(points),
                                  ),
                                ),
                              ),
                              Text(
                                '${points.first['observedAt']} → ${points.last['observedAt']}',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: muted,
                                ),
                              ),
                            ] else
                              const Text(
                                'Insufficient battery history for a chart.',
                              ),
                            const SizedBox(height: 16),
                            for (final row in rows.reversed.take(12))
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  'Battery: ${formatPercentage((row['battery'] as Map?)?['percentage'] as num?)}',
                                ),
                                subtitle: Text(row['observedAt'].toString()),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
        ],
      );
    },
  );
}

class BatteryChart extends CustomPainter {
  BatteryChart(this.rows);
  final List<Map<String, dynamic>> rows;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lime
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final grid = Paint()
      ..color = const Color(0xFF29372D)
      ..strokeWidth = 1;
    for (final fraction in [0.0, 0.5, 1.0]) {
      canvas.drawLine(
        Offset(0, size.height * fraction),
        Offset(size.width, size.height * fraction),
        grid,
      );
    }
    final start = DateTime.parse(rows.first['observedAt'] as String)
        .millisecondsSinceEpoch;
    final end = DateTime.parse(rows.last['observedAt'] as String)
        .millisecondsSinceEpoch;
    final path = Path();
    for (var i = 0; i < rows.length; i++) {
      final time = DateTime.parse(rows[i]['observedAt'] as String)
          .millisecondsSinceEpoch;
      final percentage = ((rows[i]['battery'] as Map)['percentage'] as num)
          .toDouble();
      final x = end == start
          ? size.width * i / (rows.length - 1)
          : size.width * (time - start) / (end - start);
      final y = size.height * (1 - percentage.clamp(0, 100) / 100);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant BatteryChart oldDelegate) =>
      oldDelegate.rows != rows;
}
