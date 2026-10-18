import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revice_android/core/theme.dart';
import 'package:revice_android/features/device_history_card.dart';

class Feeds {
  final controllers = <String, List<StreamController<Object?>>>{};
  int active = 0, cancelled = 0;
  Stream<Object?> open(String owner, String id, bool alerts) {
    final c = StreamController<Object?>(
      onListen: () => active++,
      onCancel: () {
        active--;
        cancelled++;
      },
    );
    controllers.putIfAbsent('$owner/$id/$alerts', () => []).add(c);
    return c.stream; // Deliberately single-subscription, like Firebase's async* wrapper.
  }

  StreamController<Object?> get(
    String id, {
    String owner = 'owner',
    bool alerts = false,
  }) => controllers['$owner/$id/$alerts']!.last;
  int get calls => controllers.values.fold(0, (sum, list) => sum + list.length);
  Future<void> close() async {
    for (final list in controllers.values) {
      for (final c in list) {
        await c.close();
      }
    }
  }
}

Map<String, Object?> history(int battery) => {
  'sample': {
    'observedAt': '2026-10-18T01:00:00Z',
    'battery': {'percentage': battery},
  },
};

void main() {
  late Feeds feeds;
  late HistorySource source;
  setUp(() {
    feeds = Feeds();
    source = feeds.open;
  });
  tearDown(() async {
    await feeds.close();
  });
  Future<void> show(
    WidgetTester tester, {
    bool visible = true,
    String owner = 'owner',
    bool alerts = false,
    bool reverse = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(600, 1600));
    await tester.pumpWidget(
      MaterialApp(
        theme: reviceTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: visible
                  ? [
                      for (final id
                          in (reverse
                              ? ['windows', 'android']
                              : ['android', 'windows']))
                        DeviceHistoryCard(
                          key: ValueKey('$owner/$id/$alerts'),
                          owner: owner,
                          device: id,
                          name: id,
                          alerts: alerts,
                          source: source,
                        ),
                    ]
                  : [const Text('Another tab')],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> toggle(WidgetTester tester, String id) async {
    await tester.ensureVisible(find.text(id));
    await tester.tap(find.text(id));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets(
    'Repeated and rapid expansion, independent devices, rebuilds and live cache',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await show(tester);
      expect(feeds.calls, 0);
      await toggle(tester, 'android');
      feeds.get('android').add(history(51));
      await tester.pumpAndSettle();
      await toggle(tester, 'windows');
      feeds.get('windows').add(history(72));
      await tester.pumpAndSettle();
      expect(feeds.active, 2);
      for (var i = 0; i < 5; i++) {
        await toggle(tester, 'android');
        await toggle(tester, 'android');
      }
      expect(find.text('Battery: 51.00%'), findsOneWidget);
      expect(find.text('Battery: 72.00%'), findsOneWidget);
      expect(feeds.calls, 2);
      for (var i = 0; i < 10; i++) {
        await tester.tap(find.text('android'));
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pumpAndSettle();
      expect(feeds.calls, 2);
      await toggle(tester, 'android');
      feeds.get('android').add(history(53));
      await tester.pump();
      await toggle(tester, 'android');
      expect(find.text('Battery: 53.00%'), findsOneWidget);
      // Cloud notifications, local/manual refresh, and device reordering rebuild
      // this subtree without transferring expansion state or reconnecting feeds.
      await show(tester, reverse: true);
      await tester.pumpAndSettle();
      expect(feeds.calls, 2);
      expect(find.text('Battery: 53.00%'), findsOneWidget);
      expect(find.text('Battery: 72.00%'), findsOneWidget);
      feeds.get('windows').add(history(74));
      await tester.pumpAndSettle();
      expect(find.text('Battery: 74.00%'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(feeds.active, 0);
      expect(feeds.cancelled, 2);
    },
  );

  testWidgets(
    'Leaving and returning creates fresh streams; owner and activity stay isolated',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await show(tester);
      await toggle(tester, 'windows');
      feeds.get('windows').add(history(61));
      await tester.pumpAndSettle();
      await show(tester, visible: false);
      await tester.pump();
      expect(feeds.active, 0);
      await show(tester);
      await toggle(tester, 'windows');
      feeds.get('windows').add(history(62));
      await tester.pumpAndSettle();
      expect(find.text('Battery: 62.00%'), findsOneWidget);
      expect(feeds.calls, 2);
      await show(tester, owner: 'different');
      await tester.pump();
      expect(find.text('Battery: 62.00%'), findsNothing);
      await toggle(tester, 'windows');
      feeds.get('windows', owner: 'different').add(null);
      await tester.pumpAndSettle();
      expect(
        find.text('No history yet. Sync this device to begin.'),
        findsOneWidget,
      );
      await show(tester, alerts: true);
      await toggle(tester, 'windows');
      feeds.get('windows', alerts: true).add(null);
      await tester.pumpAndSettle();
      expect(find.text('No alerts recorded.'), findsOneWidget);
      await toggle(tester, 'windows');
      await toggle(tester, 'windows');
      expect(feeds.active, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(feeds.active, 0);
    },
  );

  testWidgets(
    'Loading, Firebase error, retry and malformed data preserve cache',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await show(tester);
      await toggle(tester, 'windows');
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      feeds.get('windows').add(history(80));
      await tester.pumpAndSettle();
      feeds
          .get('windows')
          .addError(
            FirebaseException(
              plugin: 'firebase_database',
              code: 'permission-denied',
            ),
          );
      await tester.pumpAndSettle();
      expect(find.textContaining('temporarily unavailable'), findsOneWidget);
      expect(find.text('Battery: 80.00%'), findsOneWidget);
      await tester.ensureVisible(find.text('Retry'));
      await tester.tap(find.text('Retry'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(
        feeds.cancelled,
        1,
        reason: 'Retry cancels the original listener before reconnecting',
      );
      // Flush the cancellation future before checking the replacement listener.
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
      expect(feeds.calls, 2);
      expect(feeds.cancelled, 1);
      expect(feeds.active, 1);
      feeds.get('windows').add(history(81));
      await tester.pumpAndSettle();
      expect(find.text('Battery: 81.00%'), findsOneWidget);
      expect(find.textContaining('temporarily unavailable'), findsNothing);
      feeds.get('windows').add({
        'broken': {'observedAt': 'not a time'},
      });
      await tester.pumpAndSettle();
      expect(find.textContaining('could not be read'), findsOneWidget);
      expect(find.text('Battery: 81.00%'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(feeds.active, 0);
    },
  );

  test('History ordering uses actual timestamps and validates battery without inventing values', () {
    final rows = parseHistory({
      'late': {'observedAt': '2026-10-18T02:00:00Z'},
      'early': {'observedAt': '2026-10-18T09:00:00+08:00', 'battery': null},
    }, alerts: false);
    expect(rows.first['observedAt'], '2026-10-18T09:00:00+08:00');
    expect(rows.first['battery'], isNull);
    expect(
      () => parseHistory({
        'x': {'at': 'bad'},
      }, alerts: true),
      throwsFormatException,
    );
  });
}
