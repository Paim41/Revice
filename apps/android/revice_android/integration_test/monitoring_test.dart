import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:revice_android/models/local_snapshot.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android returns filesystem and device observations', (_) async {
    const channel = MethodChannel('app.revice/monitoring');
    final map = await channel.invokeMapMethod<Object?, Object?>('readSnapshot');
    final s = LocalSnapshot.fromMap(map!);
    expect(s.model, isNotEmpty);
    expect(s.totalBytes, greaterThan(0));
    expect(s.availableBytes, inInclusiveRange(0, s.totalBytes!));
    expect(s.isStale(DateTime.now()), isFalse);
    if (s.percentage != null) expect(s.percentage, inInclusiveRange(0, 100));
  });
}
