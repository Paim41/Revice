import 'package:flutter/services.dart';

/// Public Android observations, available from foreground and headless engines.
class NativeMonitoring {
  static const channel = MethodChannel('app.revice/monitoring');
  Future<Map<Object?, Object?>?> readSnapshot() =>
      channel.invokeMapMethod<Object?, Object?>('readSnapshot');
}
