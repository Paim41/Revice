import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/local_snapshot.dart';
import 'background_monitoring.dart';

class CloudService extends ChangeNotifier {
  static const project = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const appId = String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
  static const sender = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const databaseUrl = String.fromEnvironment('FIREBASE_DATABASE_URL');
  static const gateway = String.fromEnvironment('CLOUDFLARE_GATEWAY_URL');
  static bool get configured => [
    project,
    apiKey,
    appId,
    sender,
    databaseUrl,
    gateway,
  ].every((v) => v.isNotEmpty);
  final _secure = const FlutterSecureStorage();
  FirebaseAuth? auth;
  Database? _db;
  String? ownerUid, deviceId, _credential;
  // Identifies the account owning the current public device cache.
  String? devicesOwnerUid;
  String? error;
  DateTime? lastSync;
  bool ready = false, syncing = false;
  bool backgroundEnabled = false;
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<DatabaseEvent>? _directorySubscription;
  final Map<String, StreamSubscription<DatabaseEvent>> _deviceSubscriptions =
      {};
  final Map<String, Map<String, dynamic>> devices = {};
  bool _disposed = false;

  Future<void> initialize({bool background = false}) async {
    if (!configured) {
      ready = true;
      _notify();
      return;
    }
    try {
      if (Uri.parse(gateway).scheme != 'https' ||
          Uri.parse(databaseUrl).scheme != 'https') {
        throw StateError('HTTPS configuration required');
      }
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: apiKey,
          appId: appId,
          messagingSenderId: sender,
          projectId: project,
          databaseURL: databaseUrl,
        ),
      );
      auth = FirebaseAuth.instance;
      _db = await openDatabase(
        p.join(await getDatabasesPath(), 'revice.db'),
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE queue (sequence INTEGER PRIMARY KEY AUTOINCREMENT, payload TEXT NOT NULL, observed INTEGER NOT NULL)',
          );
        },
      );
      ownerUid = await _secure.read(key: 'ownerUid');
      deviceId = await _secure.read(key: 'deviceId');
      _credential = await _secure.read(key: 'credential');
      final savedSync = await _secure.read(key: 'lastSync');
      lastSync = savedSync == null ? null : DateTime.tryParse(savedSync);
      backgroundEnabled =
          await _secure.read(key: 'backgroundEnabled') == 'true';
      if (!background) {
        _authSubscription = auth!.authStateChanges().listen((_) {
          _watchDevices();
          _notify();
        });
        if (backgroundEnabled && ownerUid != null) {
          await enableBackgroundMonitoring();
        }
      }
    } catch (_) {
      error = 'Cloud initialization failed. Check the public Firebase configuration.';
    }
    ready = true;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _watchDevices() async {
    devicesOwnerUid = null;
    await _directorySubscription?.cancel();
    for (final sub in _deviceSubscriptions.values) {
      await sub.cancel();
    }
    _deviceSubscriptions.clear();
    devices.clear();
    final user = auth?.currentUser;
    if (user == null || !user.emailVerified) return;
    final uid = user.uid;
    devicesOwnerUid = uid;
    _directorySubscription = FirebaseDatabase.instance
        .ref('directory/$uid')
        .onValue
        .listen(
          (event) {
            if (auth?.currentUser?.uid != uid) return;
            final map = event.snapshot.value as Map? ?? {};
            final ids = map.keys.map((key) => key.toString()).toSet();
            for (final old in _deviceSubscriptions.keys.toList()) {
              if (!ids.contains(old)) {
                _deviceSubscriptions.remove(old)?.cancel();
                devices.remove(old);
              }
            }
            for (final id in ids) {
              _deviceSubscriptions.putIfAbsent(
                id,
                () => FirebaseDatabase.instance
                    .ref('devices/$uid/$id/public')
                    .onValue
                    .listen(
                      (value) {
                        if (auth?.currentUser?.uid != uid) return;
                        if (value.snapshot.value is Map) {
                          devices[id] = Map<String, dynamic>.from(
                            value.snapshot.value as Map,
                          );
                        } else {
                          devices.remove(id);
                        }
                        _notify();
                      },
                      onError: (_) {
                        error = 'Cannot read device status. Check database rules and your session.';
                        _notify();
                      },
                    ),
              );
            }
            _notify();
          },
          onError: (_) {
            error = 'Cannot read registered devices. Check database rules.';
            _notify();
          },
        );
  }

  Future<void> signIn(
    String email,
    String password, {
    bool register = false,
  }) async {
    if (auth == null) throw StateError('Cloud configuration is required');
    if (register) {
      final result = await auth!.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      await result.user!.sendEmailVerification();
    } else {
      await auth!.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    }
    _notify();
  }

  Future<void> reloadUser() async {
    await auth?.currentUser?.reload();
    await auth?.currentUser?.getIdToken(true);
    await _watchDevices();
    _notify();
  }

  Future<void> signOut() async {
    await auth?.signOut();
    await _watchDevices();
    _notify();
  }

  Future<Map<String, dynamic>> call(
    String path,
    Map<String, dynamic> body, {
    bool owner = true,
    String? agentToken,
  }) async {
    final token = owner ? await auth?.currentUser?.getIdToken() : agentToken;
    if (owner && token == null) throw StateError('Sign in first');
    final response = await http
        .post(
          Uri.parse('$gateway$path'),
          headers: {
            'Content-Type': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20));
    final result = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw StateError(result['error']?.toString() ?? 'Gateway request failed');
    }
    return result;
  }

  String _random(int bytes) => List.generate(
    bytes,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  Future<void> _identity() async {
    deviceId ??= _random(16);
    _credential ??= _random(32);
    await _secure.write(key: 'deviceId', value: deviceId);
    await _secure.write(key: 'credential', value: _credential);
  }

  Future<void> enroll(LocalSnapshot snapshot) async {
    final uid = auth?.currentUser?.uid;
    if (ownerUid != null && ownerUid != uid) {
      throw StateError(
        'Unpair this phone before enrolling with a different owner',
      );
    }
    await _identity();
    final result = await call('/v1/devices/enroll-self', {
      'deviceId': deviceId,
      'credential': _credential,
      'name': snapshot.model,
      'platform': 'android',
    });
    ownerUid = result['ownerUid'] as String;
    await _secure.write(key: 'ownerUid', value: ownerUid);
    await enqueueAndSync(snapshot);
    _notify();
  }

  Future<void> join(String code, String name) async {
    if (ownerUid != null) throw StateError('Unpair this phone first');
    await _identity();
    await call('/v1/pairing/join', {
      'code': code.trim(),
      'deviceId': deviceId,
      'credential': _credential,
      'name': name,
      'platform': 'android',
    }, owner: false);
  }

  Future<String> pairingStatus(String code) async {
    final result = await call('/v1/pairing/status', {
      'code': code.trim(),
      'credential': _credential,
    }, owner: false);
    if (result['state'] == 'approved') {
      ownerUid = result['ownerUid'] as String;
      await _secure.write(key: 'ownerUid', value: ownerUid);
      _notify();
    }
    return result['state'] as String;
  }

  Future<void> unpair() async {
    if (syncing) throw StateError('Wait for the current sync before unpairing');
    await setBackground(false);
    ownerUid = null;
    deviceId = null;
    _credential = null;
    for (final key in ['ownerUid', 'deviceId', 'credential']) {
      await _secure.delete(key: key);
    }
    await _db?.delete('queue');
    lastSync = null;
    _notify();
  }

  Future<void> setBackground(bool enabled) async {
    if (enabled && ownerUid == null) throw StateError('Pair this phone first');
    if (enabled) {
      await enableBackgroundMonitoring();
    } else {
      await disableBackgroundMonitoring();
    }
    backgroundEnabled = enabled;
    await _secure.write(key: 'backgroundEnabled', value: enabled.toString());
    _notify();
  }

  Future<void> enqueueAndSync(LocalSnapshot snapshot) async {
    if (ownerUid == null || _db == null || syncing) return;
    syncing = true;
    _notify();
    try {
      final payload = {
        'schemaVersion': 1,
        'observedAt': snapshot.observedAt.toIso8601String(),
        'agentVersion': '0.2.0',
        'battery': {
          'percentage': snapshot.percentage,
          'charging': snapshot.charging,
          'temperatureC': snapshot.temperatureC,
          'voltageMv': snapshot.voltageMv,
          'health': snapshot.health,
          'cycleCount': snapshot.cycleCount,
        },
        'storage': snapshot.totalBytes == null
            ? null
            : {
                'totalBytes': snapshot.totalBytes,
                'availableBytes': snapshot.availableBytes,
              },
      };
      await _db!.transaction((txn) async {
        await txn.insert('queue', {
          'payload': jsonEncode(payload),
          'observed': snapshot.observedAt.millisecondsSinceEpoch,
        });
        await txn.rawDelete(
          'DELETE FROM queue WHERE sequence NOT IN (SELECT sequence FROM queue ORDER BY sequence DESC LIMIT 256) OR observed < ?',
          [
            DateTime.now()
                .subtract(const Duration(days: 7))
                .millisecondsSinceEpoch,
          ],
        );
      });
      // Send the newest durable observation first. Coalesce older pending readings
      // only after successful acceptance, preserving sequence monotonicity.
      final rows = await _db!.query(
        'queue',
        orderBy: 'sequence DESC',
        limit: 1,
      );
      if (rows.isNotEmpty) {
        final row = rows.first;
        final reading =
            jsonDecode(row['payload'] as String) as Map<String, dynamic>;
        reading['sequenceId'] = row['sequence'];
        await call(
          '/v1/telemetry',
          {'ownerUid': ownerUid, 'deviceId': deviceId, 'reading': reading},
          owner: false,
          agentToken: _credential,
        );
        await _db!.delete(
          'queue',
          where: 'sequence <= ?',
          whereArgs: [row['sequence']],
        );
        lastSync = DateTime.now();
        await _secure.write(
          key: 'lastSync',
          value: lastSync!.toUtc().toIso8601String(),
        );
        error = null;
      }
    } catch (_) {
      error = 'Sync failed. The latest reading is queued locally; verify connectivity and pairing.';
    } finally {
      syncing = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _authSubscription?.cancel();
    _directorySubscription?.cancel();
    for (final s in _deviceSubscriptions.values) {
      s.cancel();
    }
    _db?.close();
    super.dispose();
  }
}
