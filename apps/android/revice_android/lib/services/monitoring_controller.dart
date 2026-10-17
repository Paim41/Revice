import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/local_snapshot.dart';

class MonitoringController extends ChangeNotifier {
  MonitoringController({MethodChannel? channel})
    : channel = channel ?? const MethodChannel('app.revice/monitoring');
  final MethodChannel channel;
  LocalSnapshot? snapshot;
  bool busy = false;
  bool ready = false;
  bool onboarded = false;
  bool reduceMotion = false;
  String? error;
  bool _disposed = false;

  Future<void> initialize() async {
    try {
      final prefs = await channel.invokeMapMethod<String, dynamic>(
        'preferences',
      );
      onboarded = prefs?['onboarded'] == true;
      reduceMotion = prefs?['reduceMotion'] == true;
    } on PlatformException {
      error = 'Could not read saved preferences. Please retry.';
    } on MissingPluginException {
      error = 'Device monitoring is available in the Android app.';
    }
    ready = true;
    _notify();
    if (onboarded) await refresh();
  }

  Future<void> setPreferences({bool? onboarding, bool? motion}) async {
    try {
      await channel.invokeMethod<void>('savePreferences', {
        'onboarded': onboarding ?? onboarded,
        'reduceMotion': motion ?? reduceMotion,
      });
      onboarded = onboarding ?? onboarded;
      reduceMotion = motion ?? reduceMotion;
      error = null;
      _notify();
      if (onboarding == true) await refresh();
    } on PlatformException {
      error = 'Could not save preferences. Please try again.';
      _notify();
    } on MissingPluginException {
      error = 'Open the Android app to save preferences.';
      _notify();
    }
  }

  Future<void> refresh() async {
    if (busy || _disposed) return;
    busy = true;
    error = null;
    _notify();
    try {
      final data = await channel.invokeMapMethod<Object?, Object?>(
        'readSnapshot',
      );
      if (data == null) throw const FormatException('Empty native reading');
      snapshot = LocalSnapshot.fromMap(data);
    } on PlatformException {
      error = 'Android could not read device metrics. Tap refresh to retry.';
    } on MissingPluginException {
      error = 'Real device readings require Android.';
    } on FormatException {
      error = 'Android returned an invalid reading.';
    } on TypeError {
      error = 'Android returned an incompatible reading.';
    } finally {
      busy = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
