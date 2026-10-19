import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/cloud_service.dart';
import '../services/monitoring_controller.dart';
import '../core/theme.dart';
import 'device_overview.dart';
import 'device_name_dialog.dart';

class CloudScreen extends StatefulWidget {
  const CloudScreen({super.key, required this.cloud, required this.monitor});
  final CloudService cloud;
  final MonitoringController monitor;
  @override
  State<CloudScreen> createState() => _CloudScreenState();
}

class _CloudScreenState extends State<CloudScreen> {
  final email = TextEditingController(),
      password = TextEditingController(),
      code = TextEditingController();
  bool busy = false;
  String? message, ownerCode;
  Map<String, dynamic>? pairing;
  CloudService get cloud => widget.cloud;
  Future<void> action(Future<void> Function() work, [String? success]) async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await work();
      if (mounted) setState(() => message = success);
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(
          () => message =
              'Account action failed: ${e.code.replaceAll('-', ' ')}.',
        );
      }
    } on StateError catch (e) {
      if (mounted) setState(() => message = e.message.toString());
    } catch (_) {
      if (mounted) {
        setState(
          () => message =
              'Request failed. Check your connection and cloud configuration.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: cloud,
    builder: (context, _) {
      final user = cloud.auth?.currentUser;
      return Scaffold(
        appBar: AppBar(title: const Text('Account & pairing')),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (!CloudService.configured) ...[
              const Text(
                'Cloud configuration required',
                style: TextStyle(fontSize: 24),
              ),
              const SizedBox(height: 16),
              const Text(
                'This build is missing Firebase and gateway settings. Local monitoring remains available. Build with the public config.json after deploying the gateway.',
              ),
            ] else if (!cloud.ready)
              const LinearProgressIndicator()
            else ...[
              if (busy) const LinearProgressIndicator(),
              if (message != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(message!, style: const TextStyle(color: cyan)),
                ),
              if (cloud.error != null)
                Text(
                  cloud.error!,
                  style: const TextStyle(color: Colors.orange),
                ),
              if (user == null) ...[
                const Text(
                  'Your devices. Your account.',
                  style: TextStyle(fontSize: 26),
                ),
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                TextField(
                  controller: password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: busy
                      ? null
                      : () => action(() async {
                          await cloud.signIn(email.text, password.text);
                          password.clear();
                        }),
                  child: const Text('Sign in'),
                ),
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => action(
                          () async {
                            await cloud.signIn(
                              email.text,
                              password.text,
                              register: true,
                            );
                            password.clear();
                          },
                          'Account created. Check your email for verification.',
                        ),
                  child: const Text('Create account'),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => action(
                          () async {
                            await cloud.auth!.sendPasswordResetEmail(
                              email: email.text.trim(),
                            );
                          },
                          'If this email has an account, check for reset instructions.',
                        ),
                  child: const Text('Reset password'),
                ),
              ] else ...[
                Text(
                  user.email ?? 'Signed in',
                  style: const TextStyle(fontSize: 22),
                ),
                if (!user.emailVerified) ...[
                  const Text(
                    'Verify your email before accessing cloud devices.',
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => action(
                            () => user.sendEmailVerification(),
                            'Verification email sent.',
                          ),
                    child: const Text('Resend verification'),
                  ),
                  OutlinedButton(
                    onPressed: busy ? null : () => action(cloud.reloadUser),
                    child: const Text('I have verified my email'),
                  ),
                ] else ...[
                  FilledButton(
                    onPressed:
                        busy ||
                            widget.monitor.snapshot == null ||
                            cloud.ownerUid != null
                        ? null
                        : () => editDeviceName(
                            context,
                            initial: widget.monitor.snapshot!.model,
                            title: 'Register This Phone',
                            save: (name) => cloud.enroll(
                              widget.monitor.snapshot!,
                              name: name,
                            ),
                          ),
                    child: Text(
                      cloud.ownerUid == null
                          ? 'Register this phone'
                          : 'This phone is registered',
                    ),
                  ),
                  OutlinedButton(
                    onPressed: busy
                        ? null
                        : () => action(() async {
                            final response = await cloud.call(
                              '/v1/pairing/create',
                              {},
                            );
                            if (mounted) {
                              setState(() {
                                ownerCode = response['code'] as String;
                                pairing = null;
                              });
                            }
                          }),
                    child: const Text('Create pairing code'),
                  ),
                  if (ownerCode != null) ...[
                    SelectableText(
                      ownerCode!,
                      style: const TextStyle(
                        fontSize: 36,
                        letterSpacing: 8,
                        color: lime,
                      ),
                    ),
                    const Text(
                      'Expires after five minutes. Enter this code on the other device, then review its request here.',
                    ),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => action(() async {
                              final result = await cloud.call(
                                '/v1/pairing/inspect',
                                {'code': ownerCode},
                              );
                              if (mounted) setState(() => pairing = result);
                            }),
                      child: const Text('Check request'),
                    ),
                    if (pairing != null)
                      Text(
                        'Status: ${pairing!['state']}\nRequest: ${pairing!['request']?['name'] ?? 'Waiting'}',
                      ),
                    if (pairing?['state'] == 'requested')
                      FilledButton(
                        onPressed: busy
                            ? null
                            : () => editDeviceName(
                                context,
                                initial:
                                    pairing?['request']?['name']?.toString() ??
                                    'Device',
                                title: 'Approve Device',
                                save: (name) async {
                                  await cloud.call('/v1/pairing/approve', {
                                    'code': ownerCode,
                                    'name': name,
                                  });
                                  if (mounted) {
                                    setState(() {
                                      ownerCode = null;
                                      pairing = null;
                                    });
                                  }
                                },
                              ),
                        child: const Text('Approve this device'),
                      ),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => action(() async {
                              await cloud.call('/v1/pairing/reject', {
                                'code': ownerCode,
                              });
                              if (mounted) {
                                setState(() {
                                  ownerCode = null;
                                  pairing = null;
                                });
                              }
                            }),
                      child: const Text('Reject / cancel'),
                    ),
                  ],
                ],
                TextButton(
                  onPressed: busy ? null : () => action(cloud.signOut),
                  child: const Text('Sign out of dashboard'),
                ),
              ],

              const SizedBox(height: 24),
              const Text(
                'This phone • Monitoring',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              if (cloud.ownerUid == null) ...[
                const Text(
                  'Connect this phone as an agent',
                  style: TextStyle(fontSize: 22),
                ),
                TextField(
                  controller: code,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(
                    labelText: 'Six-digit pairing code',
                  ),
                ),
                FilledButton(
                  onPressed: busy
                      ? null
                      : () => action(
                          () => cloud.join(
                            code.text,
                            widget.monitor.snapshot?.model ?? 'Android phone',
                          ),
                          'Request sent. Approve it on the owner dashboard.',
                        ),
                  child: const Text('Request pairing'),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => action(() async {
                          final state = await cloud.pairingStatus(code.text);
                          if (mounted) {
                            setState(() => message = 'Pairing: $state');
                          }
                        }),
                  child: const Text('Check approval'),
                ),
              ] else ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Background monitoring'),
                  subtitle: const Text(
                    'About every 15 minutes. Android may delay work during sleep or battery optimization.',
                  ),
                  value: cloud.backgroundEnabled,
                  onChanged: busy
                      ? null
                      : (value) => action(() => cloud.setBackground(value)),
                ),
                const Text(
                  'This phone is paired',
                  style: TextStyle(fontSize: 22),
                ),
                Text(
                  'Last sync: ${cloud.lastSync?.toLocal().toString().split('.').first ?? 'No successful sync this session'}',
                ),
                FilledButton(
                  onPressed:
                      busy || cloud.syncing || widget.monitor.snapshot == null
                      ? null
                      : () => action(
                          () => cloud.enqueueAndSync(widget.monitor.snapshot!),
                        ),
                  child: const Text('Sync now'),
                ),
                const Text(
                  'Signing out of the dashboard does not stop the paired agent. Unpair to stop this phone from reporting.',
                  style: TextStyle(color: muted),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Unpair this phone?'),
                              content: const Text(
                                'Clears this phone’s credential and pending queue. Revoke it from the owner dashboard to disable its server credential too.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Unpair'),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true) await action(cloud.unpair);
                        },
                  child: const Text('Unpair this phone'),
                ),
              ],
            ],
          ],
        ),
      );
    },
  );
}

class CloudDevices extends StatelessWidget {
  const CloudDevices({super.key, required this.cloud});
  final CloudService cloud;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: cloud,
    builder: (context, _) {
      if (!CloudService.configured ||
          cloud.auth?.currentUser?.emailVerified != true) {
        return const SizedBox.shrink();
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Registered devices', style: TextStyle(fontSize: 22)),
          if (cloud.devices.isEmpty) const Text('No registered devices yet.'),
          for (final entry in cloud.devices.entries)
            Card(
              margin: deviceCardMargin,
              child: ListTile(
                title: Text(entry.value['name']?.toString() ?? 'Device'),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                  child: Text(deviceSummary(entry.value)),
                ),
                onTap: () => showDeviceDetails(
                  context,
                  entry.value,
                  cloud: cloud,
                  deviceId: entry.key,
                ),
                leading: IconButton(
                  tooltip: 'Rename Device',
                  icon: const Icon(Icons.edit_outlined, color: cyan),
                  onPressed: () => editDeviceName(
                    context,
                    initial: entry.value['name']?.toString() ?? 'Device',
                    save: (name) => cloud.renameDevice(entry.key, name),
                  ),
                ),
                trailing: entry.value['revoked'] == true
                    ? const Icon(Icons.block)
                    : IconButton(
                        tooltip: 'Revoke device',
                        icon: const Icon(Icons.link_off),
                        onPressed: () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Revoke device?'),
                              content: Text(
                                'Stop ${entry.value['name']} from sending further readings?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Revoke'),
                                ),
                              ],
                            ),
                          );
                          if (confirmed != true) return;
                          try {
                            await cloud.call('/v1/devices/revoke', {
                              'deviceId': entry.key,
                            });
                          } catch (_) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Revocation failed. Try again.',
                                  ),
                                ),
                              );
                            }
                          }
                        },
                      ),
              ),
            ),
        ],
      );
    },
  );
}
