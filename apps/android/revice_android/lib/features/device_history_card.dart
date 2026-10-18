import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import 'device_overview.dart';
import 'battery_chart.dart';

typedef HistorySource = Stream<Object?> Function(
  String owner,
  String device,
  bool alerts,
);

Stream<Object?> firebaseHistory(String owner, String device, bool alerts) =>
    FirebaseDatabase.instance
        .ref('devices/$owner/$device/${alerts ? 'alerts' : 'history'}')
        .onValue
        .map((event) => event.snapshot.value);

/// Owns one lazy subscription for this account/device/feed until disposal.
/// Collapsing only hides the content; it never re-listens to a consumed stream.
class DeviceHistoryCard extends StatefulWidget {
  const DeviceHistoryCard({
    super.key,
    required this.owner,
    required this.device,
    required this.name,
    this.alerts = false,
    this.source = firebaseHistory,
  });
  final String owner, device, name;
  final bool alerts;
  final HistorySource source;
  @override
  State<DeviceHistoryCard> createState() => _DeviceHistoryCardState();
}

class _DeviceHistoryCardState extends State<DeviceHistoryCard> {
  StreamSubscription<Object?>? subscription;
  List<Map<String, dynamic>>? rows;
  bool started = false, loading = false;
  String? error;
  int generation = 0;

  Future<void> connect({bool clear = false}) async {
    final current = ++generation;
    final old = subscription;
    subscription = null;
    setState(() {
      started = true;
      loading = true;
      error = null;
      if (clear) rows = null;
    });
    await old?.cancel();
    if (!mounted || current != generation) return;
    subscription = widget
        .source(widget.owner, widget.device, widget.alerts)
        .listen(
          (value) {
            if (!mounted || current != generation) return;
            try {
              final parsed = parseHistory(value, alerts: widget.alerts);
              setState(() {
                rows = parsed;
                loading = false;
                error = null;
              });
            } on FormatException {
              setState(() {
                loading = false;
                error = 'Some history could not be read. Try again.';
              });
              if (kDebugMode) {
                debugPrint('Revice history: invalid snapshot shape');
              }
            }
          },
          onError: (Object failure, StackTrace stack) {
            if (!mounted || current != generation) return;
            if (failure is! FirebaseException && failure is! FormatException) {
              FlutterError.reportError(
                FlutterErrorDetails(
                  exception: failure,
                  stack: stack,
                  library: 'Revice history',
                ),
              );
            }
            if (kDebugMode) {
              debugPrint('Revice history stream error: ${failure.runtimeType}');
            }
            setState(() {
              loading = false;
              error = 'History is temporarily unavailable. Check your connection and retry.';
            });
          },
          onDone: () {
            if (!mounted || current != generation) return;
            setState(() {
              loading = false;
              error = 'Live history disconnected. Retry to reconnect.';
            });
          },
        );
  }

  @override
  void didUpdateWidget(covariant DeviceHistoryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.owner != widget.owner ||
        oldWidget.device != widget.device ||
        oldWidget.alerts != widget.alerts ||
        oldWidget.source != widget.source) {
      if (started) {
        connect(clear: true);
      }
    }
  }

  @override
  void dispose() {
    generation++;
    subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
    margin: deviceCardMargin,
    child: ExpansionTile(
      maintainState: true,
      shape: const Border(),
      collapsedShape: const Border(),
      title: Text(widget.name),
      subtitle: Text(
        widget.alerts
            ? 'Alert activity'
            : 'Recent observations • up to 256 readings',
      ),
      onExpansionChanged: (value) {
        if (value && !started) connect();
      },
      children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (loading) const LinearProgressIndicator(),
              if (error != null) ...[
                Text(error!, style: const TextStyle(color: muted)),
                if (rows?.isNotEmpty == true)
                  const Text(
                    'Showing previously loaded readings.',
                    style: TextStyle(color: muted),
                  ),
                TextButton(
                  onPressed: loading ? null : connect,
                  child: const Text('Retry'),
                ),
              ],
              if (rows != null) ...content(rows!),
            ],
          ),
        ),
      ],
    ),
  );

  List<Widget> content(List<Map<String, dynamic>> data) {
    if (data.isEmpty) {
      return [
        Text(
          widget.alerts
              ? 'No alerts recorded.'
              : 'No history yet. Sync this device to begin.',
        ),
      ];
    }
    if (widget.alerts) {
      return [
        for (final row in data.take(30))
          ListTile(
            title: Text(row['message']?.toString() ?? 'Alert'),
            subtitle: Text(
              '${row['active'] == true ? 'Active' : 'Recovered'} • ${DateTime.fromMillisecondsSinceEpoch((row['at'] as num).toInt()).toLocal().toString().split('.').first}',
            ),
          ),
      ];
    }
    final points = data
        .where((row) => row['battery']?['percentage'] is num)
        .toList();
    return [
      if (points.length >= 2) ...[
        const Text('Battery history', style: TextStyle(fontSize: 18)),
        const SizedBox(height: 12),
        Semantics(
          label:
              'Battery readings from ${points.first['observedAt']} to ${points.last['observedAt']}',
          child: SizedBox(
            height: 130,
            width: double.infinity,
            child: CustomPaint(painter: BatteryChart(points)),
          ),
        ),
        Text(
          '${points.first['observedAt']} → ${points.last['observedAt']}',
          style: const TextStyle(fontSize: 10, color: muted),
        ),
      ] else
        const Text('Insufficient battery history for a chart.'),
      const SizedBox(height: 16),
      for (final row in data.reversed.take(12))
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            'Battery: ${formatPercentage(row['battery']?['percentage'] as num?)}',
          ),
          subtitle: Text(row['observedAt'].toString()),
        ),
    ];
  }
}

List<Map<String, dynamic>> parseHistory(Object? value, {required bool alerts}) {
  if (value == null) return [];
  if (value is! Map) throw const FormatException('Invalid history');
  final result = <Map<String, dynamic>>[];
  for (final entry in value.values) {
    if (entry is! Map || entry.keys.any((key) => key is! String)) {
      throw const FormatException('Invalid row');
    }
    final row = Map<String, dynamic>.from(entry);
    if (alerts) {
      final at = row['at'];
      if (at is! num || !at.isFinite || at.abs() > 8640000000000000) {
        throw const FormatException('Invalid alert time');
      }
    } else {
      if (row['observedAt'] is! String ||
          DateTime.tryParse(row['observedAt']) == null) {
        throw const FormatException('Invalid time');
      }
      final battery = row['battery'];
      if (battery != null && battery is! Map) {
        throw const FormatException('Invalid battery');
      }
      final percent = battery?['percentage'];
      if (percent != null &&
          (percent is! num ||
              !percent.isFinite ||
              percent < 0 ||
              percent > 100)) {
        throw const FormatException('Invalid percentage');
      }
    }
    result.add(row);
  }
  result.sort(
    (a, b) => alerts
        ? (b['at'] as num).compareTo(a['at'] as num)
        : DateTime.parse(a['observedAt'])
              .compareTo(DateTime.parse(b['observedAt'])),
  );
  return alerts
      ? result.take(256).toList()
      : result.skip(result.length > 256 ? result.length - 256 : 0).toList();
}
